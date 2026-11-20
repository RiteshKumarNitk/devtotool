package com.innovatextechnology.debugbrowser

import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
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
    private val linksChannelName = "com.innovatextechnology.debugbrowser/links"
    private val roleRequestCode = 4711

    private var linksChannel: MethodChannel? = null
    private var pendingRoleResult: MethodChannel.Result? = null

    /** Link this activity was launched with (consumed once by Flutter). */
    private var initialUrl: String? = null

    private fun webUrlOf(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val url = intent.dataString ?: return null
        return if (url.startsWith("http://") || url.startsWith("https://")) url else null
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        initialUrl = webUrlOf(intent)
        super.onCreate(savedInstanceState)
    }

    /** A link opened from another app while we're running: new tab. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        webUrlOf(intent)?.let { linksChannel?.invokeMethod("openUrl", it) }
    }

    private fun isDefaultBrowser(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = getSystemService(RoleManager::class.java)
            return rm != null && rm.isRoleAvailable(RoleManager.ROLE_BROWSER) && rm.isRoleHeld(RoleManager.ROLE_BROWSER)
        }
        val probe = Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com"))
        val info = packageManager.resolveActivity(probe, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
        return info?.activityInfo?.packageName == packageName
    }

    /** Shows the system "Set as default browser?" dialog (Android 10+). */
    private fun requestDefaultBrowser(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = getSystemService(RoleManager::class.java)
            if (rm != null && rm.isRoleAvailable(RoleManager.ROLE_BROWSER)) {
                if (rm.isRoleHeld(RoleManager.ROLE_BROWSER)) {
                    result.success(true)
                    return
                }
                pendingRoleResult = result
                @Suppress("DEPRECATION")
                startActivityForResult(rm.createRequestRoleIntent(RoleManager.ROLE_BROWSER), roleRequestCode)
                return
            }
        }
        // Older Android: open the default-apps settings screen.
        try {
            startActivity(Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS))
        } catch (e: ActivityNotFoundException) {
            startActivity(Intent(Settings.ACTION_SETTINGS))
        }
        result.success(false)
    }

    @Deprecated("Required for RoleManager on API 29")
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == roleRequestCode) {
            pendingRoleResult?.success(isDefaultBrowser())
            pendingRoleResult = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        linksChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, linksChannelName).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeInitialUrl" -> {
                        result.success(initialUrl)
                        initialUrl = null
                    }
                    "isDefaultBrowser" -> result.success(isDefaultBrowser())
                    "requestDefaultBrowser" -> requestDefaultBrowser(result)
                    else -> result.notImplemented()
                }
            }
        }
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
