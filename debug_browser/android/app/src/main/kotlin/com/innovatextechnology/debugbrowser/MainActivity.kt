package com.innovatextechnology.debugbrowser

import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Bridges downloads to Android's shared storage:
 *  - saveToDownloads: copies a finished file into the public Downloads folder
 *    via MediaStore (Android 10+, no storage permission needed)
 *  - open / share: hands a content:// URI to other apps
 *  - delete: removes a file this app saved to Downloads
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.innovatextechnology.debugbrowser/downloads"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BrowserBridge.CHANNEL)
            .setMethodCallHandler(BrowserBridge(flutterEngine))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                    "saveToDownloads" -> {
                        val path = call.argument<String>("path")!!
                        val name = call.argument<String>("name")!!
                        val mime = call.argument<String>("mime") ?: "application/octet-stream"
                        result.success(saveToDownloads(File(path), name, mime))
                    }
                    "open" -> result.success(open(call.argument<String>("uri")!!, call.argument<String>("mime")))
                    "share" -> {
                        share(call.argument<String>("uri")!!, call.argument<String>("mime"))
                        result.success(true)
                    }
                    "delete" -> result.success(
                        contentResolver.delete(Uri.parse(call.argument<String>("uri")!!), null, null) > 0
                    )
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("DOWNLOADS", e.message, null)
            }
        }
    }

    /** Returns the content:// URI of the saved copy, or null below Android 10. */
    private fun saveToDownloads(source: File, name: String, mime: String): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val resolver = contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Could not create download entry")
        try {
            resolver.openOutputStream(uri)!!.use { out -> source.inputStream().use { it.copyTo(out) } }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        return uri.toString()
    }

    /** Opens with the default app; false if no app can open this type. */
    private fun open(uri: String, mime: String?): Boolean {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(Uri.parse(uri), mime ?: contentResolver.getType(Uri.parse(uri)))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    private fun share(uri: String, mime: String?) {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = mime ?: "application/octet-stream"
            putExtra(Intent.EXTRA_STREAM, Uri.parse(uri))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
