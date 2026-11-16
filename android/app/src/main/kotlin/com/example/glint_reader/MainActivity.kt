package com.example.glint_reader

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "glint_reader/files"
    private var pendingMethodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialFile" -> {
                        val file = readFileFromIntent(intent)
                        result.success(file)
                    }
                    "isIntentAvailable" -> result.success(true)
                    else -> result.notImplemented()
                }
            }
        pendingMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val file = readFileFromIntent(intent) ?: return
        pendingMethodChannel?.invokeMethod("onFile", file)
    }

    /** 从 intent 读取文件名与内容（文本，最多 2MB）。 */
    private fun readFileFromIntent(intent: Intent?): Map<String, String>? {
        if (intent == null) return null
        if (intent.action != Intent.ACTION_VIEW) return null
        val uri = intent.data ?: return null
        return try {
            val name = queryDisplayName(uri) ?: "unknown"
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return null
            if (bytes.size > 2 * 1024 * 1024) return mapOf(
                "name" to name,
                "error" to "file too large"
            )
            val content = String(bytes, Charsets.UTF_8)
            mapOf("name" to name, "content" to content)
        } catch (e: Exception) {
            mapOf("name" to "unknown", "error" to (e.message ?: "read failed"))
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && cursor.moveToFirst()) cursor.getString(idx) else null
            } ?: uri.lastPathSegment
        } catch (e: Exception) {
            uri.lastPathSegment
        }
    }
}
