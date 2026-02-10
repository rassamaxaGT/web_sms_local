package com.example.android_host

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.telephony.SmsManager
import android.telephony.SmsMessage
import android.telephony.SubscriptionManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayList
import java.util.HashMap

class MainActivity: FlutterActivity() {
    private val METHOD_CHANNEL = "com.example.sms_host/methods"
    private val EVENT_CHANNEL = "com.example.sms_host/events"
    
    private var smsReceiver: SmsReceiver? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
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
                "getAllMessages" -> getAllMessages(result)
                
                // === НОВЫЕ МЕТОДЫ УДАЛЕНИЯ ===
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
                // ==============================

                else -> result.notImplemented()
            }
        }

       // Найти этот блок в configureFlutterEngine:
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            smsReceiver = SmsReceiver(events)
            val filter = IntentFilter("android.provider.Telephony.SMS_RECEIVED")
        
        // ИСПРАВЛЕНИЕ: Добавляем флаг экспорта для новых версий Android
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    registerReceiver(smsReceiver, filter, Context.RECEIVER_EXPORTED)
                } else {
                    registerReceiver(smsReceiver, filter)
                }
            }

            override fun onCancel(arguments: Any?) {
                if (smsReceiver != null) {
                    unregisterReceiver(smsReceiver)
                    smsReceiver = null
                }
            }
        })
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

    private fun getSimCards(result: MethodChannel.Result) {
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

    private fun sendSms(address: String, body: String, subId: Int, result: MethodChannel.Result) {
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
                runOnUiThread { result.success("SMS Sent") }
            } catch (e: Exception) {
                runOnUiThread { result.error("SEND_FAILED", "Failed to send SMS", e.message) }
            }
        }.start()
    }

    private fun getAllMessages(result: MethodChannel.Result) {
        Thread {
            try {
                val messages = ArrayList<HashMap<String, Any?>>()
                val uri = Uri.parse("content://sms")
                // ДОБАВИЛИ _id и thread_id в запрос
                val projection = arrayOf("_id", "thread_id", "address", "body", "date", "type", "sub_id")
                val cursor = contentResolver.query(uri, projection, null, null, "date DESC LIMIT 150")

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
                        map["address"] = cursor.getString(idxAddress)
                        map["body"] = cursor.getString(idxBody)
                        map["date"] = cursor.getLong(idxDate)
                        map["isSent"] = cursor.getInt(idxType) == 2 
                        val sId = cursor.getInt(idxSubId)
                        map["subId"] = if (sId != -1) sId else null
                        messages.add(map)
                    }
                    cursor.close()
                }
                runOnUiThread { result.success(messages) }
            } catch (e: Exception) {
                runOnUiThread { result.error("READ_ERROR", "Failed to read SMS", e.message) }
            }
        }.start()
    }

    // === РЕАЛИЗАЦИЯ УДАЛЕНИЯ ===
    
    private fun deleteSms(id: Int, result: MethodChannel.Result) {
        try {
            val uri = Uri.parse("content://sms/$id")
            val count = contentResolver.delete(uri, null, null)
            if (count > 0) result.success(true) else result.success(false)
        } catch (e: Exception) {
            result.error("DELETE_ERROR", "Check if app is Default SMS App", e.message)
        }
    }

    private fun deleteThread(threadId: Int, result: MethodChannel.Result) {
        try {
            val uri = Uri.parse("content://sms/conversations/$threadId")
            val count = contentResolver.delete(uri, null, null)
            if (count > 0) result.success(true) else result.success(false)
        } catch (e: Exception) {
            result.error("DELETE_ERROR", "Check if app is Default SMS App", e.message)
        }
    }
}