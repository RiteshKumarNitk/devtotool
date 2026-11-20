package com.innovatextechnology.debugbrowser

import androidx.webkit.ProfileStore
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.ScriptHandler
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi
import java.util.concurrent.Executor

/**
 * Browser features that need the native WebView:
 *  - Private tabs: a separate WebView Profile ("private") with its own cookies
 *    and storage (androidx.webkit MULTI_PROFILE, WebView 110+).
 *  - Proxy: routes all WebView traffic through a user-supplied proxy
 *    (androidx.webkit PROXY_OVERRIDE). Affects only this app's WebViews.
 */
class BrowserBridge(private val engine: FlutterEngine) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "com.innovatextechnology.debugbrowser/browser"
        const val PRIVATE_PROFILE = "private"
    }

    private val direct = Executor { it.run() }

    /** Current document-start scripts per WebView id (replaced on update). */
    private val startScripts = mutableMapOf<Long, List<ScriptHandler>>()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "privateSupported" -> result.success(WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE))
                "setPrivateProfile" -> result.success(setPrivateProfile(call.argument<Number>("id")!!.toLong()))
                "clearPrivateData" -> {
                    clearPrivateData()
                    result.success(true)
                }
                "startScriptSupported" ->
                    result.success(WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT))
                "setStartScripts" -> result.success(
                    setStartScripts(call.argument<Number>("id")!!.toLong(), call.argument<List<String>>("scripts") ?: emptyList())
                )
                "setTextZoom" -> {
                    @Suppress("DEPRECATION")
                    val wv = WebViewFlutterAndroidExternalApi.getWebView(engine, call.argument<Number>("id")!!.toLong())
                    wv?.settings?.textZoom = call.argument<Number>("percent")!!.toInt().coerceIn(50, 300)
                    result.success(wv != null)
                }
                "setBlockImages" -> {
                    @Suppress("DEPRECATION")
                    val wv = WebViewFlutterAndroidExternalApi.getWebView(engine, call.argument<Number>("id")!!.toLong())
                    // Data saver: don't download images.
                    wv?.settings?.blockNetworkImage = call.argument<Boolean>("block") == true
                    result.success(wv != null)
                }
                "saveWebArchive" -> {
                    @Suppress("DEPRECATION")
                    val wv = WebViewFlutterAndroidExternalApi.getWebView(engine, call.argument<Number>("id")!!.toLong())
                    if (wv == null) {
                        result.success(null)
                    } else {
                        // Saves the page as a single MHTML file (offline reading).
                        wv.saveWebArchive(call.argument<String>("path")!!, false) { saved -> result.success(saved) }
                    }
                }
                "proxySupported" -> result.success(WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE))
                "setProxy" -> setProxy(call, result)
                "clearProxy" -> clearProxy(result)
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("BROWSER", e.message ?: e.javaClass.simpleName, null)
        }
    }

    /** Puts a freshly created, not-yet-used WebView in the private profile. Verified. */
    @Suppress("DEPRECATION")
    private fun setPrivateProfile(id: Long): Boolean {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) return false
        val webView = WebViewFlutterAndroidExternalApi.getWebView(engine, id) ?: return false
        ProfileStore.getInstance().getOrCreateProfile(PRIVATE_PROFILE)
        WebViewCompat.setProfile(webView, PRIVATE_PROFILE)
        // Only report success if the WebView really uses the private profile.
        return WebViewCompat.getProfile(webView).name == PRIVATE_PROFILE
    }

    /**
     * Runs each script in every frame before the page's own scripts, on every
     * navigation of this WebView. Each is registered separately, so a syntax
     * error in one (e.g. a user script) can't break the others. Replaces any
     * previous scripts; an empty list removes them.
     */
    @Suppress("DEPRECATION")
    private fun setStartScripts(id: Long, scripts: List<String>): Boolean {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) return false
        startScripts.remove(id)?.forEach { it.remove() }
        if (scripts.isEmpty()) return true
        val webView = WebViewFlutterAndroidExternalApi.getWebView(engine, id) ?: return false
        startScripts[id] = scripts.filter { it.isNotEmpty() }
            .map { WebViewCompat.addDocumentStartJavaScript(webView, it, setOf("*")) }
        return true
    }

    /** Wipes cookies, storage and permissions of the private profile. */
    private fun clearPrivateData() {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) return
        val profile = ProfileStore.getInstance().getProfile(PRIVATE_PROFILE) ?: return
        profile.cookieManager.removeAllCookies(null)
        profile.cookieManager.flush()
        profile.webStorage.deleteAllData()
        profile.geolocationPermissions.clearAll()
    }

    private fun setProxy(call: MethodCall, result: MethodChannel.Result) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
            result.success(false)
            return
        }
        val rule = call.argument<String>("rule")!!
        val bypass = call.argument<List<String>>("bypass") ?: emptyList()
        val builder = ProxyConfig.Builder().addProxyRule(rule)
        bypass.filter { it.isNotBlank() }.forEach { builder.addBypassRule(it.trim()) }
        if (call.argument<Boolean>("bypassLocal") == true) builder.bypassSimpleHostnames()
        ProxyController.getInstance().setProxyOverride(builder.build(), direct) { result.success(true) }
    }

    private fun clearProxy(result: MethodChannel.Result) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
            result.success(false)
            return
        }
        ProxyController.getInstance().clearProxyOverride(direct) { result.success(true) }
    }
}
