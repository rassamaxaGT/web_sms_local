package com.example.android_host

import android.app.Application
import android.content.Context
import android.os.Build
import android.os.Environment
import android.util.Log
import io.flutter.app.FlutterApplication
import java.io.File
import java.io.FileWriter
import java.io.PrintWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class SmsHostApplication : FlutterApplication() {
    companion object {
        const val TAG = "SMS_HOST_APP"
        lateinit var instance: SmsHostApplication
            private set

        fun writeNativeLog(context: Context, tag: String, message: String, throwable: Throwable? = null) {
            try {
                val time = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US).format(Date())
                val logEntry = buildString {
                    append("[$time][$tag] $message\n")
                    if (throwable != null) {
                        append("Throwable: ${throwable.javaClass.name}: ${throwable.message}\n")
                        val sw = java.io.StringWriter()
                        throwable.printStackTrace(PrintWriter(sw))
                        append(sw.toString())
                        append("\n")
                    }
                }

                // 1. Write to internal filesDir
                val internalLog = File(context.filesDir, "sms_host_native.log")
                FileWriter(internalLog, true).use { it.write(logEntry) }

                // 2. Write to external filesDir if available
                context.getExternalFilesDir(null)?.let { extDir ->
                    val extLog = File(extDir, "sms_host_native.log")
                    FileWriter(extLog, true).use { it.write(logEntry) }
                }

                // 3. Write to Downloads folder (easily accessible via My Files / Мои файлы)
                try {
                    val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                    if (downloadsDir != null && (downloadsDir.exists() || downloadsDir.mkdirs())) {
                        val publicLog = File(downloadsDir, "sms_host_crash_log.txt")
                        FileWriter(publicLog, true).use { it.write(logEntry) }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Could not write to Downloads directory: ${e.message}")
                }

                // 4. Save to SharedPreferences for in-app recovery
                val prefs = context.getSharedPreferences("sms_host_crash_tracker", Context.MODE_PRIVATE)
                val existing = prefs.getString("last_crash", "") ?: ""
                val updated = if (existing.length > 50000) existing.takeLast(25000) + logEntry else existing + logEntry
                prefs.edit().putString("last_crash", updated).putLong("last_crash_time", System.currentTimeMillis()).apply()
            } catch (e: Exception) {
                Log.e(TAG, "Fatal error in writeNativeLog: ${e.message}")
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.i(TAG, "SmsHostApplication.onCreate() started")

        // Install earliest possible uncaught crash handler
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            Log.e(TAG, "FATAL UNCAUGHT NATIVE CRASH in thread '${thread.name}': ${throwable.message}", throwable)
            writeNativeLog(
                applicationContext,
                "FATAL_CRASH",
                "Fatal uncaught exception in thread ${thread.name} (id=${thread.id})",
                throwable
            )
            defaultHandler?.uncaughtException(thread, throwable)
        }

        // Record initial device environment
        val deviceInfo = "Device: ${Build.MANUFACTURER} ${Build.MODEL} (${Build.DEVICE}), Android OS: ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})"
        writeNativeLog(applicationContext, "BOOT", "Application initialized. $deviceInfo")
    }
}
