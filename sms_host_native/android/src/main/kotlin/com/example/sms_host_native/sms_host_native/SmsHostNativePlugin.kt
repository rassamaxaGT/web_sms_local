package com.example.sms_host_native.sms_host_native

import android.Manifest
import android.app.Activity
import android.app.Service
import android.app.role.RoleManager
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.media.AudioManager
import android.media.AudioDeviceInfo
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.CallLog
import android.provider.Telephony
import android.telecom.TelecomManager
import android.telephony.PhoneStateListener
import android.telephony.SmsManager
import android.telephony.SmsMessage
import android.telephony.SubscriptionManager
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.ArrayList
import java.util.HashMap
import java.util.HashSet
import android.util.Log

/** SmsHostNativePlugin with Default SMS App support, Samsung One UI & Android 14+ compatibility */
class SmsHostNativePlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private val TAG = "SMS_HOST_NATIVE"
    private val METHOD_CHANNEL = "com.example.sms_host/methods"
    private val EVENT_CHANNEL = "com.example.sms_host/events"
    private val CALL_EVENT_CHANNEL = "com.example.sms_host/call_events"
    private val DEVICE_EVENT_CHANNEL = "com.example.sms_host/device_events"

    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var callEventChannel: EventChannel
    private lateinit var deviceEventChannel: EventChannel
    private var activity: Activity? = null
    private var smsReceiver: DynamicSmsReceiver? = null
    private var callStateListenerLegacy: PhoneStateListener? = null
    private var telephonyCallbackApi31: TelephonyCallback? = null
    private var audioDeviceCallback: Any? = null
    private var deviceStateReceiver: BroadcastReceiver? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        private const val REQUEST_CODE_ROLE_SMS = 1002
        private const val TAG_COMPANION = "SMS_HOST_NATIVE"

        @Volatile
        var activeEventSink: EventChannel.EventSink? = null

        @Volatile
        var activeCallEventSink: EventChannel.EventSink? = null

        @Volatile
        var activeDeviceEventSink: EventChannel.EventSink? = null

        @Volatile
        var currentCallingNumber: String? = null

        /** Safely inserts an incoming SMS message to the Android system SMS Inbox provider */
        fun insertInboxSms(context: Context, address: String, body: String, subId: Int?): Uri? {
            val uri = Uri.parse("content://sms/inbox")
            val threadId = try {
                Telephony.Threads.getOrCreateThreadId(context, address)
            } catch (e: Throwable) {
                null
            }
            val values = ContentValues().apply {
                put("address", address)
                put("body", body)
                put("date", System.currentTimeMillis())
                put("read", 0)
                put("type", 1) // 1 = MESSAGE_TYPE_INBOX
                if (threadId != null && threadId > 0) {
                    put("thread_id", threadId)
                }
                if (subId != null && subId != -1) {
                    put("sub_id", subId)
                }
            }
            return try {
                val resUri = context.contentResolver.insert(uri, values)
                Log.i(TAG_COMPANION, "Successfully inserted inbox SMS from $address: $resUri")
                resUri
            } catch (e: Throwable) {
                try {
                    values.remove("sub_id")
                    val fallbackUri = context.contentResolver.insert(uri, values)
                    Log.i(TAG_COMPANION, "Successfully inserted inbox SMS without sub_id: $fallbackUri")
                    fallbackUri
                } catch (ex: Throwable) {
                    Log.e(TAG_COMPANION, "Failed to insert inbox SMS: ${ex.message}", ex)
                    null
                }
            }
        }

        /** Safely inserts a sent SMS message to the Android system SMS Sent provider */
        fun insertSentSms(context: Context, address: String, body: String, subId: Int?): Uri? {
            val uri = Uri.parse("content://sms/sent")
            val threadId = try {
                Telephony.Threads.getOrCreateThreadId(context, address)
            } catch (e: Throwable) {
                null
            }
            val values = ContentValues().apply {
                put("address", address)
                put("body", body)
                put("date", System.currentTimeMillis())
                put("read", 1)
                put("type", 2) // 2 = MESSAGE_TYPE_SENT
                put("status", -1) // STATUS_NONE
                if (threadId != null && threadId > 0) {
                    put("thread_id", threadId)
                }
                if (subId != null && subId != -1) {
                    put("sub_id", subId)
                }
            }
            return try {
                val resUri = context.contentResolver.insert(uri, values)
                Log.i(TAG_COMPANION, "Successfully inserted sent SMS to $address (threadId=$threadId): $resUri")
                resUri
            } catch (e: Throwable) {
                try {
                    values.remove("sub_id")
                    val fallbackUri = context.contentResolver.insert(uri, values)
                    Log.i(TAG_COMPANION, "Successfully inserted sent SMS without sub_id: $fallbackUri")
                    fallbackUri
                } catch (ex: Throwable) {
                    Log.e(TAG_COMPANION, "Failed to insert sent SMS: ${ex.message}", ex)
                    null
                }
            }
        }

        /** Dispatch incoming SMS to active Flutter listener & persist to system Inbox */
        fun dispatchIncomingSms(context: Context, address: String, body: String, subId: Int?) {
            Log.i(TAG_COMPANION, "dispatchIncomingSms from $address (subId=$subId)")
            val data = HashMap<String, Any?>().apply {
                put("address", address)
                put("body", body)
                put("date", System.currentTimeMillis())
                put("subId", subId)
            }

            Handler(Looper.getMainLooper()).post {
                try {
                    activeEventSink?.success(data)
                } catch (e: Throwable) {
                    Log.e(TAG_COMPANION, "Failed to dispatch to activeEventSink: ${e.message}")
                }
            }

            // Always attempt to persist incoming SMS into Android's system Inbox database
            insertInboxSms(context, address, body, subId)
        }

        /** Parse SMS PDUs from Intent and dispatch */
        fun parseAndDispatchIntent(context: Context, intent: Intent) {
            try {
                val bundle = intent.extras ?: return
                val pdus = bundle.get("pdus") as? Array<*> ?: return
                val format = bundle.getString("format")
                val subId = bundle.getInt("subscription", -1)

                val fullBody = StringBuilder()
                var originatingAddress = "Unknown"

                for (i in pdus.indices) {
                    val pdu = pdus[i] as? ByteArray ?: continue
                    val msg = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        SmsMessage.createFromPdu(pdu, format)
                    } else {
                        @Suppress("DEPRECATION")
                        SmsMessage.createFromPdu(pdu)
                    }
                    if (msg.originatingAddress != null) {
                        originatingAddress = msg.originatingAddress ?: originatingAddress
                    }
                    fullBody.append(msg.messageBody ?: "")
                }

                if (fullBody.isNotEmpty()) {
                    dispatchIncomingSms(
                        context,
                        originatingAddress,
                        fullBody.toString(),
                        if (subId != -1) subId else null
                    )
                }
            } catch (e: Throwable) {
                Log.e(TAG_COMPANION, "Error parsing SMS intent: ${e.message}", e)
            }
        }
    }

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        Log.i(TAG, "onAttachedToEngine() called")
        context = flutterPluginBinding.applicationContext
        
        try {
            methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, METHOD_CHANNEL)
            methodChannel.setMethodCallHandler(this)

            eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, EVENT_CHANNEL)
            eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    Log.i(TAG, "EventChannel.onListen: Registering SMS receiver")
                    activeEventSink = events
                    registerSmsReceiverSafely()
                }

                override fun onCancel(arguments: Any?) {
                    Log.i(TAG, "EventChannel.onCancel: Unregistering SMS receiver")
                    activeEventSink = null
                    unregisterSmsReceiverSafely()
                }
            })

            callEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, CALL_EVENT_CHANNEL)
            callEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    Log.i(TAG, "CallEventChannel.onListen: Registering call state listener")
                    activeCallEventSink = events
                    registerCallStateListenerSafely()
                }

                override fun onCancel(arguments: Any?) {
                    Log.i(TAG, "CallEventChannel.onCancel: Unregistering call state listener")
                    activeCallEventSink = null
                    unregisterCallStateListenerSafely()
                }
            })

            deviceEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, DEVICE_EVENT_CHANNEL)
            deviceEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    Log.i(TAG, "DeviceEventChannel.onListen: Registering audio/device listener")
                    activeDeviceEventSink = events
                    registerDeviceListenersSafely()
                    dispatchCurrentDeviceState()
                }

                override fun onCancel(arguments: Any?) {
                    Log.i(TAG, "DeviceEventChannel.onCancel: Unregistering audio/device listener")
                    activeDeviceEventSink = null
                    unregisterDeviceListenersSafely()
                }
            })
        } catch (e: Throwable) {
            Log.e(TAG, "Fatal plugin attachment error: ${e.message}", e)
        }
    }

    private fun registerSmsReceiverSafely() {
        try {
            if (smsReceiver != null) {
                unregisterSmsReceiverSafely()
            }
            smsReceiver = DynamicSmsReceiver()
            val filter = IntentFilter().apply {
                addAction(Telephony.Sms.Intents.SMS_RECEIVED_ACTION)
                addAction(Telephony.Sms.Intents.SMS_DELIVER_ACTION)
                priority = 1000
            }

            // On Android 13+ (API 33+), system broadcasts require RECEIVER_EXPORTED
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                try {
                    ContextCompat.registerReceiver(
                        context,
                        smsReceiver,
                        filter,
                        ContextCompat.RECEIVER_EXPORTED
                    )
                } catch (ex: Throwable) {
                    Log.w(TAG, "Failed to register with RECEIVER_EXPORTED, trying default: ${ex.message}")
                    @Suppress("UnspecifiedRegisterReceiverFlag")
                    context.registerReceiver(smsReceiver, filter)
                }
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                context.registerReceiver(smsReceiver, filter)
            }
            Log.i(TAG, "SMS receiver registered successfully (EXPORTED for system broadcasts)")
        } catch (e: Throwable) {
            Log.e(TAG, "Failed to register SMS receiver: ${e.message}", e)
        }
    }

    private fun unregisterSmsReceiverSafely() {
        if (smsReceiver != null) {
            try {
                context.unregisterReceiver(smsReceiver)
            } catch (e: Throwable) {
                Log.e(TAG, "Error unregistering receiver: ${e.message}", e)
            }
            smsReceiver = null
        }
    }

    // ActivityAware implementation
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        Log.d(TAG, "onMethodCall: ${call.method}")
        try {
            when (call.method) {
                "isDefaultSmsApp" -> isDefaultSmsApp(result)
                "requestDefaultSmsApp" -> requestDefaultSmsApp(result)
                "getSimCards" -> getSimCards(result)
                "sendSms" -> {
                    val address = call.argument<String>("address")
                    val body = call.argument<String>("body")
                    val subId = call.argument<Int>("subId")
                    if (address != null && body != null && subId != null) {
                        sendSms(address, body, subId, result)
                    } else {
                        result.error("INVALID_ARGS", "Missing arguments for sendSms", null)
                    }
                }
                "getMessages" -> {
                    val limit = call.argument<Int>("limit") ?: 50
                    val offset = call.argument<Int>("offset") ?: 0
                    val address = call.argument<String>("address")
                    getMessages(limit, offset, address, result)
                }
                "deleteSms" -> {
                    val id = call.argument<Int>("id")
                    if (id != null) deleteSms(id, result) 
                    else result.error("ARGS", "Missing id for deleteSms", null)
                }
                "deleteThread" -> {
                    val threadId = call.argument<Int>("threadId")
                    if (threadId != null) deleteThread(threadId, result)
                    else result.error("ARGS", "Missing threadId for deleteThread", null)
                }
                "getThreads" -> {
                    val limit = call.argument<Int>("limit") ?: 50
                    getThreads(limit, result)
                }
                "makePhoneCall" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")
                    val subscriptionId = call.argument<Int>("subscriptionId")
                    if (phoneNumber != null) {
                        makeCall(phoneNumber, subscriptionId, result)
                    } else {
                        result.error("INVALID_ARGS", "Missing phoneNumber", null)
                    }
                }
                "endPhoneCall" -> {
                    endCall(result)
                }
                "getCallLogs" -> {
                    val limit = call.argument<Int>("limit") ?: 100
                    val offset = call.argument<Int>("offset") ?: 0
                    getCallLogs(limit, offset, result)
                }
                "requestCallLogPermission" -> {
                    requestCallLogPermission(result)
                }
                "hasCallLogPermission" -> {
                    result.success(hasPermission(Manifest.permission.READ_CALL_LOG))
                }
                "getDeviceVolume" -> {
                    getDeviceVolume(result)
                }
                "setDeviceVolume" -> {
                    val stream = call.argument<String>("stream") ?: "ring"
                    val volume = call.argument<Int>("volume") ?: 0
                    setDeviceVolume(stream, volume, result)
                }
                "adjustDeviceVolume" -> {
                    val stream = call.argument<String>("stream") ?: "ring"
                    val direction = call.argument<String>("direction") ?: "up"
                    adjustDeviceVolume(stream, direction, result)
                }
                else -> result.notImplemented()
            }
        } catch (e: Throwable) {
            Log.e(TAG, "Unhandled exception in methodCall ${call.method}: ${e.message}", e)
            result.error("NATIVE_ERROR", e.message, null)
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        Log.i(TAG, "onDetachedFromEngine() called")
        try {
            activeEventSink = null
            activeCallEventSink = null
            activeDeviceEventSink = null
            methodChannel.setMethodCallHandler(null)
            eventChannel.setStreamHandler(null)
            callEventChannel.setStreamHandler(null)
            deviceEventChannel.setStreamHandler(null)
            unregisterSmsReceiverSafely()
            unregisterCallStateListenerSafely()
            unregisterDeviceListenersSafely()
        } catch (e: Throwable) {
            Log.e(TAG, "Error in onDetachedFromEngine: ${e.message}", e)
        }
    }

    /** Dynamic receiver listening to both SMS_RECEIVED and SMS_DELIVER */
    class DynamicSmsReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            Log.i("SMS_HOST_NATIVE", "DynamicSmsReceiver.onReceive action: ${intent.action}")
            if (intent.action == Telephony.Sms.Intents.SMS_RECEIVED_ACTION ||
                intent.action == Telephony.Sms.Intents.SMS_DELIVER_ACTION) {
                parseAndDispatchIntent(context, intent)
            }
        }
    }

    private fun hasPermission(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun isDefaultSmsApp(result: Result) {
        try {
            val isDefault = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val roleManager = context.getSystemService(RoleManager::class.java)
                roleManager?.isRoleHeld(RoleManager.ROLE_SMS) ?: (Telephony.Sms.getDefaultSmsPackage(context) == context.packageName)
            } else {
                Telephony.Sms.getDefaultSmsPackage(context) == context.packageName
            }
            Log.i(TAG, "isDefaultSmsApp returned: $isDefault")
            result.success(isDefault)
        } catch (e: Throwable) {
            Log.e(TAG, "isDefaultSmsApp error: ${e.message}", e)
            val fallback = Telephony.Sms.getDefaultSmsPackage(context) == context.packageName
            result.success(fallback)
        }
    }

    private fun requestDefaultSmsApp(result: Result) {
        try {
            val currentActivity = activity
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val roleManager = context.getSystemService(RoleManager::class.java)
                if (roleManager != null && roleManager.isRoleAvailable(RoleManager.ROLE_SMS)) {
                    if (roleManager.isRoleHeld(RoleManager.ROLE_SMS)) {
                        Log.i(TAG, "App is already default SMS app")
                        result.success(true)
                        return
                    }
                    val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_SMS)
                    if (currentActivity != null) {
                        currentActivity.startActivityForResult(intent, REQUEST_CODE_ROLE_SMS)
                    } else {
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(intent)
                    }
                    result.success(true)
                    return
                }
            }

            // Android 4.4 - 9 or fallback
            val intent = Intent(Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT).apply {
                putExtra(Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, context.packageName)
                if (currentActivity == null) {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            }
            if (currentActivity != null) {
                currentActivity.startActivity(intent)
            } else {
                context.startActivity(intent)
            }
            result.success(true)
        } catch (e: Throwable) {
            Log.e(TAG, "requestDefaultSmsApp error: ${e.message}", e)
            result.error("ROLE_ERROR", "Failed to request default SMS role: ${e.message}", null)
        }
    }

    private fun getSimCards(result: Result) {
        try {
            if (!hasPermission(Manifest.permission.READ_PHONE_STATE)) {
                Log.w(TAG, "getSimCards: READ_PHONE_STATE not granted yet, returning empty list")
                result.success(emptyList<Map<String, Any?>>())
                return
            }

            val subscriptionManager = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            if (subscriptionManager == null) {
                result.success(emptyList<Map<String, Any?>>())
                return
            }
            val activeSubs = subscriptionManager.activeSubscriptionInfoList ?: emptyList()
            val simCards = activeSubs.map { sub ->
                mapOf(
                    "subscriptionId" to sub.subscriptionId,
                    "slotIndex" to sub.simSlotIndex,
                    "carrierName" to (sub.displayName?.toString() ?: "SIM ${sub.simSlotIndex + 1}")
                )
            }
            result.success(simCards)
        } catch (e: Throwable) {
            Log.e(TAG, "Failed to get SIM cards: ${e.message}", e)
            result.success(emptyList<Map<String, Any?>>())
        }
    }

    private fun sendSms(address: String, body: String, subId: Int, result: Result) {
        Thread {
            try {
                if (!hasPermission(Manifest.permission.SEND_SMS)) {
                    mainHandler.post { result.error("NO_PERMISSION", "SEND_SMS permission not granted", null) }
                    return@Thread
                }

                val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (subId != -1) {
                        context.getSystemService(SmsManager::class.java).createForSubscriptionId(subId)
                    } else {
                        context.getSystemService(SmsManager::class.java)
                    }
                } else {
                    @Suppress("DEPRECATION")
                    if (subId != -1) {
                        SmsManager.getSmsManagerForSubscriptionId(subId)
                    } else {
                        SmsManager.getDefault()
                    }
                }
                val parts = smsManager.divideMessage(body)
                if (parts.size > 1) {
                    smsManager.sendMultipartTextMessage(address, null, parts, null, null)
                } else {
                    smsManager.sendTextMessage(address, null, body, null, null)
                }

                // Always insert sent SMS into system database so other apps and web client reload can see it
                insertSentSms(context, address, body, if (subId != -1) subId else null)

                mainHandler.post { result.success("SMS Sent") }
            } catch (e: Throwable) {
                Log.e(TAG, "Failed to send SMS: ${e.message}", e)
                mainHandler.post { result.error("SEND_FAILED", "Failed to send SMS: ${e.message}", e.message) }
            }
        }.start()
    }

    private fun getMessages(limit: Int, offset: Int, address: String?, result: Result) {
        Thread {
            try {
                if (!hasPermission(Manifest.permission.READ_SMS)) {
                    Log.w(TAG, "getMessages: READ_SMS not granted yet, returning empty list")
                    mainHandler.post { result.success(emptyList<Map<String, Any?>>()) }
                    return@Thread
                }

                val messages = ArrayList<HashMap<String, Any?>>()
                val uri = Uri.parse("content://sms")
                
                var selection: String? = null
                var selectionArgs: Array<String>? = null
                
                if (address != null && address.trim().isNotEmpty()) {
                    val clean = address.replace(Regex("[^0-9]"), "")
                    val last10 = if (clean.length >= 10) clean.substring(clean.length - 10) else clean
                    val last7 = if (clean.length >= 7) clean.substring(clean.length - 7) else clean
                    selection = "address = ? OR address LIKE ? OR address LIKE ? OR address LIKE ?"
                    selectionArgs = arrayOf(address, "%$clean%", "%$last10%", "%$last7%")
                }

                val sortOrder = "date DESC"
                val cursor = context.contentResolver.query(uri, null, selection, selectionArgs, sortOrder)

                if (cursor != null) {
                    val idxId = cursor.getColumnIndex("_id")
                    val idxThreadId = cursor.getColumnIndex("thread_id")
                    val idxAddress = cursor.getColumnIndex("address")
                    val idxBody = cursor.getColumnIndex("body")
                    val idxDate = cursor.getColumnIndex("date")
                    val idxType = cursor.getColumnIndex("type")
                    
                    var idxSubId = cursor.getColumnIndex("sub_id")
                    if (idxSubId == -1) idxSubId = cursor.getColumnIndex("subscription_id")
                    if (idxSubId == -1) idxSubId = cursor.getColumnIndex("sim_id")
                    if (idxSubId == -1) idxSubId = cursor.getColumnIndex("sim_slot")

                    var currentPos = 0
                    while (cursor.moveToNext()) {
                        if (currentPos < offset) {
                            currentPos++
                            continue
                        }
                        if (messages.size >= limit) {
                            break
                        }

                        val map = HashMap<String, Any?>()
                        map["id"] = if (idxId != -1) cursor.getInt(idxId) else 0
                        map["threadId"] = if (idxThreadId != -1) cursor.getInt(idxThreadId) else 0
                        map["address"] = if (idxAddress != -1) cursor.getString(idxAddress) ?: "Unknown" else "Unknown"
                        map["body"] = if (idxBody != -1) cursor.getString(idxBody) ?: "" else ""
                        map["date"] = if (idxDate != -1) cursor.getLong(idxDate) else System.currentTimeMillis()
                        map["isSent"] = if (idxType != -1) (cursor.getInt(idxType) == 2) else false
                        val sId = if (idxSubId != -1) cursor.getInt(idxSubId) else -1
                        map["subId"] = if (sId != -1) sId else null
                        messages.add(map)
                        currentPos++
                    }
                    cursor.close()
                }
                mainHandler.post { result.success(messages) }
            } catch (e: Throwable) {
                Log.e(TAG, "Failed to read SMS: ${e.message}", e)
                mainHandler.post { result.success(emptyList<Map<String, Any?>>()) }
            }
        }.start()
    }

    private fun deleteSms(id: Int, result: Result) {
        try {
            val uri = Uri.parse("content://sms/$id")
            val count = context.contentResolver.delete(uri, null, null)
            if (count > 0) result.success(true) else result.success(false)
        } catch (e: Throwable) {
            Log.e(TAG, "deleteSms error: ${e.message}", e)
            result.error("DELETE_ERROR", "Check if app is Default SMS App: ${e.message}", e.message)
        }
    }

    private fun deleteThread(threadId: Int, result: Result) {
        try {
            val uri = Uri.parse("content://sms/conversations/$threadId")
            val count = context.contentResolver.delete(uri, null, null)
            if (count > 0) result.success(true) else result.success(false)
        } catch (e: Throwable) {
            Log.e(TAG, "deleteThread error: ${e.message}", e)
            result.error("DELETE_ERROR", "Check if app is Default SMS App: ${e.message}", e.message)
        }
    }

    private fun getThreads(limit: Int, result: Result) {
        Thread {
            try {
                if (!hasPermission(Manifest.permission.READ_SMS)) {
                    Log.w(TAG, "getThreads: READ_SMS not granted yet, returning empty list")
                    mainHandler.post { result.success(emptyList<Map<String, Any?>>()) }
                    return@Thread
                }

                Log.d(TAG, "Fetching threads with limit $limit")
                val threads = ArrayList<HashMap<String, Any?>>()
                val uri = Uri.parse("content://sms")
                val selection = "type = 1 OR type = 2"
                val sortOrder = "date DESC"
                val cursor = context.contentResolver.query(uri, null, selection, null, sortOrder)

                if (cursor != null) {
                    val idxId = cursor.getColumnIndex("_id")
                    val idxThreadId = cursor.getColumnIndex("thread_id")
                    val idxAddress = cursor.getColumnIndex("address")
                    val idxBody = cursor.getColumnIndex("body")
                    val idxDate = cursor.getColumnIndex("date")
                    val idxType = cursor.getColumnIndex("type")
                    
                    var idxSubId = cursor.getColumnIndex("sub_id")
                    if (idxSubId == -1) idxSubId = cursor.getColumnIndex("subscription_id")
                    if (idxSubId == -1) idxSubId = cursor.getColumnIndex("sim_id")

                    val seenThreads = HashSet<Int>()
                    val seenAddresses = HashSet<String>()

                    while (cursor.moveToNext() && threads.size < limit) {
                        val threadId = if (idxThreadId != -1) cursor.getInt(idxThreadId) else -1
                        val rawAddress = if (idxAddress != -1) cursor.getString(idxAddress) ?: "" else ""
                        val cleanDigits = rawAddress.replace(Regex("[^0-9]"), "")
                        val normalizedKey = if (cleanDigits.length >= 10) cleanDigits.substring(cleanDigits.length - 10) else cleanDigits

                        val isNewThread = (threadId > 0 && !seenThreads.contains(threadId)) ||
                                          (normalizedKey.isNotEmpty() && !seenAddresses.contains(normalizedKey))

                        if (isNewThread) {
                            if (threadId > 0) seenThreads.add(threadId)
                            if (normalizedKey.isNotEmpty()) seenAddresses.add(normalizedKey)

                            val map = HashMap<String, Any?>()
                            map["id"] = if (idxId != -1) cursor.getInt(idxId) else 0
                            map["threadId"] = threadId
                            map["address"] = if (rawAddress.isNotEmpty()) rawAddress else "Unknown"
                            map["body"] = if (idxBody != -1) cursor.getString(idxBody) ?: "" else ""
                            map["date"] = if (idxDate != -1) cursor.getLong(idxDate) else System.currentTimeMillis()
                            map["isSent"] = if (idxType != -1) (cursor.getInt(idxType) == 2) else false
                            val sId = if (idxSubId != -1) cursor.getInt(idxSubId) else -1
                            map["subId"] = if (sId != -1) sId else null
                            threads.add(map)
                        }
                    }
                    cursor.close()
                }
                mainHandler.post { result.success(threads) }
            } catch (e: Throwable) {
                Log.e(TAG, "Threads error: ${e.message}", e)
                mainHandler.post { result.success(emptyList<Map<String, Any?>>()) }
            }
        }.start()
    }

    private fun requestCallLogPermission(result: Result) {
        try {
            if (hasPermission(Manifest.permission.READ_CALL_LOG)) {
                result.success(true)
                return
            }
            val curActivity = activity
            if (curActivity != null) {
                ActivityCompat.requestPermissions(
                    curActivity,
                    arrayOf(Manifest.permission.READ_CALL_LOG),
                    202
                )
                result.success(true)
            } else {
                result.success(false)
            }
        } catch (e: Throwable) {
            Log.e(TAG, "requestCallLogPermission error: ${e.message}", e)
            result.error("PERM_ERROR", e.message, null)
        }
    }

    private fun getCallLogs(limit: Int, offset: Int, result: Result) {
        Thread {
            try {
                if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED) {
                    Log.w(TAG, "READ_CALL_LOG permission not granted")
                    mainHandler.post { result.success(emptyList<Map<String, Any>>()) }
                    return@Thread
                }
                val list = ArrayList<Map<String, Any>>()
                val uri = CallLog.Calls.CONTENT_URI
                val projection = arrayOf(
                    CallLog.Calls._ID,
                    CallLog.Calls.NUMBER,
                    CallLog.Calls.CACHED_NAME,
                    CallLog.Calls.DATE,
                    CallLog.Calls.DURATION,
                    CallLog.Calls.TYPE
                )
                val sortOrder = "${CallLog.Calls.DATE} DESC"
                context.contentResolver.query(uri, projection, null, null, sortOrder)?.use { cursor ->
                    val idIdx = cursor.getColumnIndex(CallLog.Calls._ID)
                    val numIdx = cursor.getColumnIndex(CallLog.Calls.NUMBER)
                    val nameIdx = cursor.getColumnIndex(CallLog.Calls.CACHED_NAME)
                    val dateIdx = cursor.getColumnIndex(CallLog.Calls.DATE)
                    val durIdx = cursor.getColumnIndex(CallLog.Calls.DURATION)
                    val typeIdx = cursor.getColumnIndex(CallLog.Calls.TYPE)

                    if (offset > 0) {
                        cursor.moveToPosition(offset - 1)
                    }
                    var count = 0
                    while (cursor.moveToNext() && count < limit) {
                        val typeInt = if (typeIdx >= 0) cursor.getInt(typeIdx) else 0
                        val typeStr = when (typeInt) {
                            CallLog.Calls.INCOMING_TYPE -> "INCOMING"
                            CallLog.Calls.OUTGOING_TYPE -> "OUTGOING"
                            CallLog.Calls.MISSED_TYPE -> "MISSED"
                            CallLog.Calls.REJECTED_TYPE -> "REJECTED"
                            CallLog.Calls.BLOCKED_TYPE -> "BLOCKED"
                            CallLog.Calls.VOICEMAIL_TYPE -> "VOICEMAIL"
                            else -> "UNKNOWN"
                        }
                        val map = HashMap<String, Any>()
                        map["id"] = if (idIdx >= 0) cursor.getLong(idIdx).toString() else ""
                        map["number"] = if (numIdx >= 0) (cursor.getString(numIdx) ?: "") else ""
                        map["name"] = if (nameIdx >= 0) (cursor.getString(nameIdx) ?: "") else ""
                        map["date"] = if (dateIdx >= 0) cursor.getLong(dateIdx) else 0L
                        map["durationSeconds"] = if (durIdx >= 0) cursor.getInt(durIdx) else 0
                        map["type"] = typeStr
                        list.add(map)
                        count++
                    }
                }
                Log.i(TAG, "getCallLogs retrieved ${list.size} entries directly from Android CallLog ContentProvider")
                mainHandler.post { result.success(list) }
            } catch (e: Throwable) {
                Log.e(TAG, "Failed to query call logs: ${e.message}", e)
                mainHandler.post { result.success(emptyList<Map<String, Any>>()) }
            }
        }.start()
    }

    private fun registerCallStateListenerSafely() {
        try {
            if (!hasPermission(Manifest.permission.READ_PHONE_STATE)) {
                Log.w(TAG, "Cannot register call listener: READ_PHONE_STATE not granted")
                return
            }
            val telephonyManager = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                telephonyCallbackApi31 = Api31TelephonyHelper.register(telephonyManager, context) { state ->
                    dispatchCallState(state)
                }
                Log.i(TAG, "Registered TelephonyCallback (API 31+)")
            } else {
                val listener = object : PhoneStateListener() {
                    @Deprecated("Deprecated in Java")
                    override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                        dispatchCallState(state, phoneNumber)
                    }
                }
                callStateListenerLegacy = listener
                telephonyManager.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
                Log.i(TAG, "Registered PhoneStateListener (Legacy)")
            }
        } catch (e: Throwable) {
            Log.e(TAG, "Failed to register call state listener: ${e.message}", e)
        }
    }

    private fun unregisterCallStateListenerSafely() {
        try {
            val telephonyManager = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                telephonyCallbackApi31?.let {
                    Api31TelephonyHelper.unregister(telephonyManager, it)
                    telephonyCallbackApi31 = null
                }
            } else {
                callStateListenerLegacy?.let {
                    telephonyManager.listen(it, PhoneStateListener.LISTEN_NONE)
                    callStateListenerLegacy = null
                }
            }
        } catch (e: Throwable) {
            Log.e(TAG, "Failed to unregister call state listener: ${e.message}", e)
        }
    }

    private fun dispatchCallState(state: Int, incomingOrOutgoingNumber: String? = null) {
        val stateStr = when (state) {
            TelephonyManager.CALL_STATE_OFFHOOK -> "OFFHOOK"
            TelephonyManager.CALL_STATE_RINGING -> "RINGING"
            TelephonyManager.CALL_STATE_IDLE -> "IDLE"
            else -> "UNKNOWN"
        }
        val phone = if (!incomingOrOutgoingNumber.isNullOrEmpty()) incomingOrOutgoingNumber else (currentCallingNumber ?: "")
        Log.i(TAG, "dispatchCallState: state=$stateStr, phone=$phone")
        val data = hashMapOf<String, Any>(
            "state" to stateStr,
            "phoneNumber" to phone,
            "timestamp" to System.currentTimeMillis()
        )
        mainHandler.post {
            activeCallEventSink?.success(data)
        }

        if (state == TelephonyManager.CALL_STATE_IDLE) {
            currentCallingNumber = null
        }
    }

    private fun registerDeviceListenersSafely() {
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            if (audioManager != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val callback = object : android.media.AudioDeviceCallback() {
                    override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                        Log.i(TAG, "Audio devices added")
                        dispatchCurrentDeviceState()
                    }

                    override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                        Log.i(TAG, "Audio devices removed")
                        dispatchCurrentDeviceState()
                    }
                }
                audioManager.registerAudioDeviceCallback(callback, mainHandler)
                audioDeviceCallback = callback
            }
        } catch (e: Throwable) {
            Log.w(TAG, "Failed to register AudioDeviceCallback: ${e.message}")
        }

        try {
            if (deviceStateReceiver != null) {
                unregisterDeviceListenersSafely()
            }
            deviceStateReceiver = object : BroadcastReceiver() {
                override fun onReceive(ctx: Context?, intent: Intent?) {
                    val action = intent?.action ?: return
                    Log.d(TAG, "Device state broadcast received: $action")
                    dispatchCurrentDeviceState()
                }
            }
            val filter = IntentFilter().apply {
                addAction("android.media.VOLUME_CHANGED_ACTION")
                addAction(AudioManager.RINGER_MODE_CHANGED_ACTION)
                addAction(Intent.ACTION_HEADSET_PLUG)
                addAction(BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED)
                addAction(BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED)
                addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
                addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                try {
                    ContextCompat.registerReceiver(
                        context,
                        deviceStateReceiver,
                        filter,
                        ContextCompat.RECEIVER_EXPORTED
                    )
                } catch (ex: Throwable) {
                    @Suppress("UnspecifiedRegisterReceiverFlag")
                    context.registerReceiver(deviceStateReceiver, filter)
                }
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                context.registerReceiver(deviceStateReceiver, filter)
            }
            Log.i(TAG, "Device state receiver registered successfully")
        } catch (e: Throwable) {
            Log.w(TAG, "Failed to register deviceStateReceiver: ${e.message}")
        }
    }

    private fun unregisterDeviceListenersSafely() {
        try {
            if (audioDeviceCallback != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                if (audioDeviceCallback is android.media.AudioDeviceCallback) {
                    audioManager?.unregisterAudioDeviceCallback(audioDeviceCallback as android.media.AudioDeviceCallback)
                }
                audioDeviceCallback = null
            }
        } catch (e: Throwable) {
            Log.w(TAG, "Failed to unregister AudioDeviceCallback: ${e.message}")
        }

        try {
            if (deviceStateReceiver != null) {
                context.unregisterReceiver(deviceStateReceiver)
                deviceStateReceiver = null
            }
        } catch (e: Throwable) {
            Log.w(TAG, "Failed to unregister deviceStateReceiver: ${e.message}")
        }
    }

    private fun dispatchCurrentDeviceState() {
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
            val volumeMap = getVolumeMap(audioManager)
            mainHandler.post {
                try {
                    activeDeviceEventSink?.success(volumeMap)
                } catch (e: Throwable) {
                    Log.w(TAG, "Failed to send to activeDeviceEventSink: ${e.message}")
                }
            }
        } catch (e: Throwable) {
            Log.e(TAG, "dispatchCurrentDeviceState error: ${e.message}", e)
        }
    }



    private fun wakeUpDevice() {
        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            val wakeLock = powerManager?.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                "SMS_HOST:CallWakeLock"
            )
            wakeLock?.acquire(3000L)
            Log.i(TAG, "Acquired WakeLock for call dispatch")
        } catch (e: Throwable) {
            Log.w(TAG, "WakeLock error: ${e.message}")
        }
    }

    private fun makeCall(phoneNumber: String, subscriptionId: Int?, result: Result) {
        currentCallingNumber = phoneNumber
        wakeUpDevice()
        val hasCallPermission = hasPermission(Manifest.permission.CALL_PHONE)

        if (hasCallPermission) {
            val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
            if (telecomManager != null) {
                try {
                    val uri = Uri.fromParts("tel", phoneNumber, null)
                    val extras = Bundle()
                    if (subscriptionId != null && subscriptionId != -1 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val accounts = telecomManager.callCapablePhoneAccounts
                        for (handle in accounts) {
                            if (handle.id.contains(subscriptionId.toString())) {
                                extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle)
                                break
                            }
                        }
                    }
                    telecomManager.placeCall(uri, extras)
                    Log.i(TAG, "TelecomManager.placeCall initiated successfully for $phoneNumber")
                    mainHandler.post { result.success(true) }
                    return
                } catch (e: Throwable) {
                    Log.w(TAG, "TelecomManager.placeCall failed, falling back to Intent: ${e.message}")
                }
            }
        }

        // Fallback: startActivity(Intent.ACTION_CALL / ACTION_DIAL)
        try {
            val action = if (hasCallPermission) Intent.ACTION_CALL else Intent.ACTION_DIAL
            val intent = Intent(action).apply {
                data = Uri.parse("tel:$phoneNumber")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }

            if (subscriptionId != null && subscriptionId != -1 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                val list = telecomManager?.callCapablePhoneAccounts ?: emptyList()
                for (handle in list) {
                    if (handle.id.contains(subscriptionId.toString())) {
                        intent.putExtra(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle)
                        break
                    }
                }
            }
            context.startActivity(intent)
            mainHandler.post { result.success(true) }
        } catch (e: Throwable) {
            Log.e(TAG, "ACTION_CALL failed, falling back to ACTION_DIAL: ${e.message}")
            try {
                val intent = Intent(Intent.ACTION_DIAL).apply {
                    data = Uri.parse("tel:$phoneNumber")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(intent)
                mainHandler.post { result.success(true) }
            } catch (ex: Throwable) {
                Log.e(TAG, "ACTION_DIAL also failed: ${ex.message}", ex)
                mainHandler.post { result.error("CALL_ERROR", ex.message, null) }
            }
        }
    }

    private fun endCall(result: Result) {
        try {
            var terminated = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                if (telecomManager != null && hasPermission(Manifest.permission.ANSWER_PHONE_CALLS)) {
                    terminated = telecomManager.endCall()
                    Log.i(TAG, "TelecomManager.endCall returned: $terminated")
                }
            }

            if (!terminated) {
                try {
                    val telephonyManager = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                    val getITelephony = telephonyManager?.javaClass?.getDeclaredMethod("getITelephony")
                    getITelephony?.isAccessible = true
                    val iTelephony = getITelephony?.invoke(telephonyManager)
                    val endCallMethod = iTelephony?.javaClass?.getDeclaredMethod("endCall")
                    endCallMethod?.isAccessible = true
                    terminated = (endCallMethod?.invoke(iTelephony) as? Boolean) ?: false
                    Log.i(TAG, "Reflection endCall returned: $terminated")
                } catch (e: Throwable) {
                    Log.w(TAG, "Reflection endCall fallback failed: ${e.message}")
                }
            }

            mainHandler.post { result.success(terminated) }
        } catch (e: Throwable) {
            Log.e(TAG, "endCall error: ${e.message}", e)
            mainHandler.post { result.error("END_CALL_ERROR", e.message, null) }
        }
    }

    private fun getVolumeMap(audioManager: AudioManager): Map<String, Any> {
        val ringVol = try { audioManager.getStreamVolume(AudioManager.STREAM_RING) } catch (_: Throwable) { 0 }
        val maxRingVol = try { audioManager.getStreamMaxVolume(AudioManager.STREAM_RING) } catch (_: Throwable) { 15 }
        val callVol = try { audioManager.getStreamVolume(AudioManager.STREAM_VOICE_CALL) } catch (_: Throwable) { 0 }
        val maxCallVol = try { audioManager.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL) } catch (_: Throwable) { 5 }
        val ringerMode = try { audioManager.ringerMode } catch (_: Throwable) { 2 }

        var isBtConnected = false
        var btDeviceName: String? = null
        var isWiredConnected = false

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                for (device in devices) {
                    val type = device.type
                    val isBluetooth = type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                            type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && type == AudioDeviceInfo.TYPE_BLE_HEADSET) ||
                            (Build.VERSION.SDK_INT >= 28 && type == AudioDeviceInfo.TYPE_HEARING_AID)

                    if (isBluetooth) {
                        isBtConnected = true
                        val name = device.productName?.toString()?.trim()
                        if (!name.isNullOrEmpty() && btDeviceName == null) {
                            btDeviceName = name
                        }
                    } else if (type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                        type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                        type == AudioDeviceInfo.TYPE_USB_HEADSET
                    ) {
                        isWiredConnected = true
                    }
                }
            } catch (e: Throwable) {
                Log.w(TAG, "AudioDeviceInfo check failed: ${e.message}")
            }
        }

        if (!isBtConnected) {
            try {
                if (audioManager.isBluetoothA2dpOn || audioManager.isBluetoothScoOn) {
                    isBtConnected = true
                }
            } catch (_: Throwable) {}
        }
        if (!isWiredConnected) {
            try {
                @Suppress("DEPRECATION")
                if (audioManager.isWiredHeadsetOn) {
                    isWiredConnected = true
                }
            } catch (_: Throwable) {}
        }

        return mapOf(
            "ringVolume" to ringVol,
            "maxRingVolume" to maxRingVol,
            "callVolume" to callVol,
            "maxCallVolume" to maxCallVol,
            "ringerMode" to ringerMode,
            "isBluetoothConnected" to isBtConnected,
            "bluetoothDeviceName" to (btDeviceName ?: if (isBtConnected) "Bluetooth-гарнитура" else ""),
            "isWiredHeadsetConnected" to isWiredConnected
        )
    }

    private fun getDeviceVolume(result: Result) {
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val volumeMap = getVolumeMap(audioManager)
            mainHandler.post { result.success(volumeMap) }
        } catch (e: Throwable) {
            Log.e(TAG, "getDeviceVolume error: ${e.message}", e)
            mainHandler.post { result.error("VOLUME_ERROR", e.message, null) }
        }
    }

    private fun setDeviceVolume(streamType: String, volume: Int, result: Result) {
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val stream = if (streamType.equals("call", ignoreCase = true)) AudioManager.STREAM_VOICE_CALL else AudioManager.STREAM_RING
            val max = audioManager.getStreamMaxVolume(stream)
            val clamped = volume.coerceIn(0, max)
            audioManager.setStreamVolume(stream, clamped, AudioManager.FLAG_SHOW_UI)
            val volumeMap = getVolumeMap(audioManager)
            mainHandler.post { result.success(volumeMap) }
            dispatchCurrentDeviceState()
        } catch (e: Throwable) {
            Log.e(TAG, "setDeviceVolume error: ${e.message}", e)
            mainHandler.post { result.error("VOLUME_ERROR", e.message, null) }
        }
    }

    private fun adjustDeviceVolume(streamType: String, direction: String, result: Result) {
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val stream = if (streamType.equals("call", ignoreCase = true)) AudioManager.STREAM_VOICE_CALL else AudioManager.STREAM_RING
            val adjust = if (direction.equals("down", ignoreCase = true)) AudioManager.ADJUST_LOWER else AudioManager.ADJUST_RAISE
            audioManager.adjustStreamVolume(stream, adjust, AudioManager.FLAG_SHOW_UI)
            val volumeMap = getVolumeMap(audioManager)
            mainHandler.post { result.success(volumeMap) }
            dispatchCurrentDeviceState()
        } catch (e: Throwable) {
            Log.e(TAG, "adjustDeviceVolume error: ${e.message}", e)
            mainHandler.post { result.error("VOLUME_ERROR", e.message, null) }
        }
    }
}

@androidx.annotation.RequiresApi(Build.VERSION_CODES.S)
private object Api31TelephonyHelper {
    fun register(telephonyManager: TelephonyManager, context: Context, onState: (Int) -> Unit): TelephonyCallback {
        val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
            override fun onCallStateChanged(state: Int) {
                onState(state)
            }
        }
        telephonyManager.registerTelephonyCallback(context.mainExecutor, callback)
        return callback
    }

    fun unregister(telephonyManager: TelephonyManager, callback: TelephonyCallback) {
        telephonyManager.unregisterTelephonyCallback(callback)
    }
}

/** BroadcastReceiver for android.provider.Telephony.SMS_DELIVER (Default SMS App) */
class SmsDeliverReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.i("SMS_HOST_NATIVE", "SmsDeliverReceiver.onReceive triggered")
        if (intent.action == Telephony.Sms.Intents.SMS_DELIVER_ACTION) {
            SmsHostNativePlugin.parseAndDispatchIntent(context, intent)
        }
    }
}

/** BroadcastReceiver for android.provider.Telephony.WAP_PUSH_DELIVER (Required for Default SMS App) */
class WapPushDeliverReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.i("SMS_HOST_NATIVE", "WapPushDeliverReceiver.onReceive triggered: ${intent.action}")
    }
}

/** Service for responding via message (Required for Default SMS App) */
class HeadlessSmsSendService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
}
