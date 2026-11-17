package com.example.android_host

import android.content.Context
import android.os.Bundle
import android.os.Environment
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val TAG = "SMS_HOST_MAIN"
    private val DIAG_CHANNEL = "com.example.sms_host/diagnostics"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.i(TAG, "MainActivity.onCreate() started")
        SmsHostApplication.writeNativeLog(applicationContext, "LIFECYCLE", "MainActivity.onCreate()")
    }

    override fun onResume() {
        super.onResume()
        Log.i(TAG, "MainActivity.onResume()")
        SmsHostApplication.writeNativeLog(applicationContext, "LIFECYCLE", "MainActivity.onResume()")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.i(TAG, "configureFlutterEngine() called")
        SmsHostApplication.writeNativeLog(applicationContext, "BOOT", "FlutterEngine configured")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DIAG_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getNativeLogs" -> {
                    try {
                        val prefs = getSharedPreferences("sms_host_crash_tracker", Context.MODE_PRIVATE)
                        val crashLogs = prefs.getString("last_crash", "") ?: ""
                        
                        val internalLog = File(filesDir, "sms_host_native.log")
                        val fileLogs = if (internalLog.exists()) internalLog.readText() else ""
                        
                        val combined = buildString {
                            if (crashLogs.isNotEmpty()) {
                                append("=== SAVED CRASH TRACKER LOGS ===\n")
                                append(crashLogs)
                                append("\n================================\n\n")
                            }
                            if (fileLogs.isNotEmpty()) {
                                append("=== NATIVE RUNTIME LOGS ===\n")
                                append(fileLogs)
                            }
                        }
                        result.success(if (combined.isEmpty()) "No native crash logs recorded." else combined)
                    } catch (e: Exception) {
                        result.success("Error reading native logs: ${e.message}")
                    }
                }
                "exportLogsToDownloads" -> {
                    try {
                        val logContent = call.argument<String>("content") ?: ""
                        val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                        if (downloadsDir != null && (downloadsDir.exists() || downloadsDir.mkdirs())) {
                            val exportFile = File(downloadsDir, "sms_host_diagnostics.txt")
                            exportFile.writeText(logContent)
                            result.success(exportFile.absolutePath)
                        } else {
                            result.error("STORAGE_ERROR", "Downloads directory is not accessible", null)
                        }
                    } catch (e: Exception) {
                        result.error("EXPORT_FAILED", e.message, null)
                    }
                }
                "clearNativeLogs" -> {
                    try {
                        val prefs = getSharedPreferences("sms_host_crash_tracker", Context.MODE_PRIVATE)
                        prefs.edit().clear().apply()
                        val internalLog = File(filesDir, "sms_host_native.log")
                        if (internalLog.exists()) internalLog.delete()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CLEAR_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}