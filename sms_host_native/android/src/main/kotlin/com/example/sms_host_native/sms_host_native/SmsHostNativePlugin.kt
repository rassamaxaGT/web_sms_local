package com.example.sms_host_native.sms_host_native

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import android.telephony.SmsMessage
import android.telephony.SubscriptionManager
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.ArrayList
import java.util.HashMap
import java.util.HashSet
import android.util.Log

/** SmsHostNativePlugin */
class SmsHostNativePlugin : FlutterPlugin, MethodCallHandler {
    private val METHOD_CHANNEL = "com.example.sms_host/methods"
    private val EVENT_CHANNEL = "com.example.sms_host/events"

    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var smsReceiver: SmsReceiver? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                smsReceiver = SmsReceiver(events)
                val filter = IntentFilter("android.provider.Telephony.SMS_RECEIVED")
            
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    context.registerReceiver(smsReceiver, filter, Context.RECEIVER_EXPORTED)
                } else {
                    context.registerReceiver(smsReceiver, filter)
                }
            }

            override fun onCancel(arguments: Any?) {
                if (smsReceiver != null) {
                    context.unregisterReceiver(smsReceiver)
                    smsReceiver = null
                }
            }
        })
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "getSimCards" -> getSimCards(result)
            "sendSms" -> {
                val address = call.argument<String>("address")
                val body = call.argument<String>("body")
                val subId = call.argument<Int>("subId")
                if (address != null && body != null && subId != null) {
                    sendSms(address, body, subId, result)
                } else {
                    result.error("INVALID_ARGS", "Missing arguments", null)
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
                else result.error("ARGS", "Missing id", null)
            }
            "deleteThread" -> {
                val threadId = call.argument<Int>("threadId")
                if (threadId != null) deleteThread(threadId, result)
                else result.error("ARGS", "Missing threadId", null)
            }
            "getThreads" -> {
                val limit = call.argument<Int>("limit") ?: 50
                getThreads(limit, result)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        if (smsReceiver != null) {
            context.unregisterReceiver(smsReceiver)
            smsReceiver = null
        }
    }

    class SmsReceiver(private val events: EventChannel.EventSink?) : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == "android.provider.Telephony.SMS_RECEIVED") {
                val bundle = intent.extras
                if (bundle != null) {
                    val pdus = bundle.get("pdus") as Array<*>?
                    if (pdus != null) {
                        for (i in pdus.indices) {
                            val msg = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                SmsMessage.createFromPdu(pdus[i] as ByteArray, bundle.getString("format"))
                            } else {
                                SmsMessage.createFromPdu(pdus[i] as ByteArray)
                            }
                            val subId = bundle.getInt("subscription", -1)
                            val data = HashMap<String, Any?>()
                            data["address"] = msg.originatingAddress
                            data["body"] = msg.messageBody
                            data["date"] = System.currentTimeMillis()
                            data["subId"] = if (subId != -1) subId else null
                            events?.success(data)
                        }
                    }
                }
            }
        }
    }

    private fun getSimCards(result: Result) {
        try {
            val subscriptionManager = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
            val activeSubs = subscriptionManager.activeSubscriptionInfoList ?: emptyList()
            val simCards = activeSubs.map { sub ->
                mapOf(
                    "subscriptionId" to sub.subscriptionId,
                    "slotIndex" to sub.simSlotIndex,
                    "carrierName" to (sub.displayName?.toString() ?: "Unknown Carrier")
                )
            }
            result.success(simCards)
        } catch (e: Exception) {
            result.error("ERROR", "Failed to get SIM cards", e.message)
        }
    }

    private fun sendSms(address: String, body: String, subId: Int, result: Result) {
        Thread {
            try {
                val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    context.getSystemService(SmsManager::class.java).createForSubscriptionId(subId)
                } else {
                    @Suppress("DEPRECATION")
                    SmsManager.getSmsManagerForSubscriptionId(subId)
                }
                val parts = smsManager.divideMessage(body)
                if (parts.size > 1) {
                    smsManager.sendMultipartTextMessage(address, null, parts, null, null)
                } else {
                    smsManager.sendTextMessage(address, null, body, null, null)
                }
                mainHandler.post { result.success("SMS Sent") }
            } catch (e: Exception) {
                mainHandler.post { result.error("SEND_FAILED", "Failed to send SMS", e.message) }
            }
        }.start()
    }

    private fun getMessages(limit: Int, offset: Int, address: String?, result: Result) {
        Thread {
            try {
                val messages = ArrayList<HashMap<String, Any?>>()
                val uri = Uri.parse("content://sms")
                val projection = arrayOf("_id", "thread_id", "address", "body", "date", "type", "sub_id")
                
                var selection: String? = null
                var selectionArgs: Array<String>? = null
                
                if (address != null) {
                    selection = "address = ?"
                    selectionArgs = arrayOf(address)
                }

                val sortOrder = "date DESC LIMIT $limit OFFSET $offset"
                val cursor = context.contentResolver.query(uri, projection, selection, selectionArgs, sortOrder)

                if (cursor != null) {
                    val idxId = cursor.getColumnIndex("_id")
                    val idxThreadId = cursor.getColumnIndex("thread_id")
                    val idxAddress = cursor.getColumnIndex("address")
                    val idxBody = cursor.getColumnIndex("body")
                    val idxDate = cursor.getColumnIndex("date")
                    val idxType = cursor.getColumnIndex("type")
                    val idxSubId = cursor.getColumnIndex("sub_id")

                    while (cursor.moveToNext()) {
                        val map = HashMap<String, Any?>()
                        map["id"] = cursor.getInt(idxId)
                        map["threadId"] = cursor.getInt(idxThreadId)
                        map["address"] = if (idxAddress != -1) cursor.getString(idxAddress) ?: "Unknown" else "Unknown"
                        map["body"] = if (idxBody != -1) cursor.getString(idxBody) ?: "" else ""
                        map["date"] = cursor.getLong(idxDate)
                        map["isSent"] = cursor.getInt(idxType) == 2 
                        val sId = if (idxSubId != -1) cursor.getInt(idxSubId) else -1
                        map["subId"] = if (sId != -1) sId else null
                        messages.add(map)
                    }
                    cursor.close()
                }
                mainHandler.post { result.success(messages) }
            } catch (e: Exception) {
                mainHandler.post { result.error("READ_ERROR", "Failed to read SMS", e.message) }
            }
        }.start()
    }

    private fun deleteSms(id: Int, result: Result) {
        try {
            val uri = Uri.parse("content://sms/$id")
            val count = context.contentResolver.delete(uri, null, null)
            if (count > 0) result.success(true) else result.success(false)
        } catch (e: Exception) {
            result.error("DELETE_ERROR", "Check if app is Default SMS App", e.message)
        }
    }

    private fun deleteThread(threadId: Int, result: Result) {
        try {
            val uri = Uri.parse("content://sms/conversations/$threadId")
            val count = context.contentResolver.delete(uri, null, null)
            if (count > 0) result.success(true) else result.success(false)
        } catch (e: Exception) {
            result.error("DELETE_ERROR", "Check if app is Default SMS App", e.message)
        }
    }

    private fun getThreads(limit: Int, result: Result) {
        Thread {
            try {
                Log.d("SMS_HOST_NATIVE", "Fetching threads with limit $limit")
                val threads = ArrayList<HashMap<String, Any?>>()
                val uri = Uri.parse("content://sms")
                val projection = arrayOf("_id", "thread_id", "address", "body", "date", "type", "sub_id")
                val selection = "type = 1 OR type = 2" // Только входящие и исходящие
                val sortOrder = "date DESC"
                val cursor = context.contentResolver.query(uri, projection, selection, null, sortOrder)

                if (cursor != null) {
                    Log.d("SMS_HOST_NATIVE", "Cursor size: ${cursor.count}")
                    val idxId = cursor.getColumnIndex("_id")
                    val idxThreadId = cursor.getColumnIndex("thread_id")
                    val idxAddress = cursor.getColumnIndex("address")
                    val idxBody = cursor.getColumnIndex("body")
                    val idxDate = cursor.getColumnIndex("date")
                    val idxType = cursor.getColumnIndex("type")
                    val idxSubId = cursor.getColumnIndex("sub_id")

                    val seenThreads = HashSet<Int>()

                    while (cursor.moveToNext() && threads.size < limit) {
                        val threadId = if (idxThreadId != -1) cursor.getInt(idxThreadId) else -1
                        if (threadId != -1 && !seenThreads.contains(threadId)) {
                            seenThreads.add(threadId)
                            val map = HashMap<String, Any?>()
                            map["id"] = cursor.getInt(idxId)
                            map["threadId"] = threadId
                            map["address"] = if (idxAddress != -1) cursor.getString(idxAddress) ?: "Unknown" else "Unknown"
                            map["body"] = if (idxBody != -1) cursor.getString(idxBody) ?: "" else ""
                            map["date"] = cursor.getLong(idxDate)
                            map["isSent"] = cursor.getInt(idxType) == 2 
                            val sId = if (idxSubId != -1) cursor.getInt(idxSubId) else -1
                            map["subId"] = if (sId != -1) sId else null
                            threads.add(map)
                        }
                    }
                    cursor.close()
                    Log.d("SMS_HOST_NATIVE", "Found ${threads.size} unique threads")
                }
                mainHandler.post { result.success(threads) }
            } catch (e: Exception) {
                Log.e("SMS_HOST_NATIVE", "Threads error", e)
                mainHandler.post { result.error("READ_ERROR", "Failed to read threads", e.message) }
            }
        }.start()
    }
}
