package com.example.glint_reader

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "glint_reader/files"
    private var pendingMethodChannel: MethodChannel? = null

    // 文件选择请求码与挂起的 Result
    private val pickFileRequest = 4201
    private var pendingPickResult: MethodChannel.Result? = null

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
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("BAD_ARGS", "path required", null)
                        } else {
                            try {
                                installApk(path)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("INSTALL_FAILED", e.message, null)
                            }
                        }
                    }
                    "pickFile" -> {
                        if (pendingPickResult != null) {
                            result.error("ALREADY_ACTIVE", "A pick is already in progress", null)
                        } else {
                            pendingPickResult = result
                            launchFilePicker()
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        pendingMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
    }

    /**
     * 用 ACTION_GET_CONTENT 直接调起文件管理器浏览视图：
     * - 多数 ROM 上 GET_CONTENT 直达文件列表，而非 OPEN_DOCUMENT 的
     *   「最近 / 收藏」聚合首页
     * - EXTRA_INITIAL_URI 指向 Download，打开即文件列表（API 26+）
     * - EXTRA_MIME_TYPES 限定应用支持的文本类格式
     * 选中后复制到应用缓存目录，返回可读路径。
     */
    private fun launchFilePicker() {
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "*/*"
            addCategory(Intent.CATEGORY_OPENABLE)
            // 限定支持的文件格式后缀（MIME 过滤，匹配的才可选）
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "text/*",
                    "application/json",
                    "application/xml",
                    "application/yaml",
                    "application/x-yaml",
                    "application/toml",
                    "application/javascript",
                    "application/typescript",
                    "application/x-sh",
                    "application/x-python",
                    "application/sql",
                    "application/graphql",
                    "application/x-protobuf",
                    "application/xhtml+xml",
                    "application/rss+xml",
                    "text/csv",
                    "application/vnd.ms-excel",
                    "application/md",
                    "application/octet-stream"
                )
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // 落在 Download：用户直接看到文件列表
                putExtra(
                    DocumentsContract.EXTRA_INITIAL_URI,
                    DocumentsContract.buildRootUri(
                        "com.android.providers.downloads.documents",
                        "downloads"
                    )
                )
            }
        }
        try {
            startActivityForResult(
                Intent.createChooser(intent, "打开文件"),
                pickFileRequest
            )
        } catch (e: Exception) {
            pendingPickResult?.error("NO_PICKER", e.message, null)
            pendingPickResult = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickFileRequest) return
        val result = pendingPickResult
        pendingPickResult = null
        if (result == null) return

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null) // 用户取消
            return
        }
        try {
            val path = copyUriToCache(data.data!!)
            result.success(path)
        } catch (e: Exception) {
            result.error("COPY_FAILED", e.message, null)
        }
    }

    /** 把 content:// 复制到缓存目录，返回文件路径。 */
    private fun copyUriToCache(uri: Uri): String {
        val displayName = queryDisplayName(uri)
            ?: "picked_${System.currentTimeMillis()}"
        // 补扩展名（部分提供方不带显示名扩展）
        val name = if (displayName.contains('.')) displayName
            else "$displayName.txt"
        val dir = File(cacheDir, "picked").apply {
            if (!exists()) mkdirs()
        }
        val dest = File(dir, name)
        contentResolver.openInputStream(uri)?.use { input ->
            dest.outputStream().use { output ->
                input.copyTo(output)
            }
        } ?: throw IllegalStateException("Cannot open $uri")
        return dest.absolutePath
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val file = readFileFromIntent(intent) ?: return
        pendingMethodChannel?.invokeMethod("onFile", file)
    }

    /** 通过 FileProvider + ACTION_VIEW 调起系统 APK 安装器。 */
    private fun installApk(path: String) {
        val file = File(path)
        require(file.exists()) { "APK not found: $path" }
        val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.fileprovider",
                file
            )
        } else {
            Uri.fromFile(file)
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    /** 从 intent 读取文件名与内容（文本，最多 2MB）。 */
    private fun readFileFromIntent(intent: Intent?): Map<String, String>? {
        if (intent == null) return null
        if (intent.action != Intent.ACTION_VIEW) return null
        val uri = intent.data ?: return null
        // 安装器返回的 intent 不当文件读
        if (intent.type == "application/vnd.android.package-archive") return null
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
