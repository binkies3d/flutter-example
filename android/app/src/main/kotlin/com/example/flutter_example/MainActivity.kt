package com.example.flutter_example

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(BinkiesWebViewPlugin())
    }
}

/**
 * The native side of BinkiesWebViewHost (lib/binkies_viewer.dart): what webview_flutter doesn't offer.
 * The WebView is the one webview_flutter created, looked up by its identifier.
 */
class BinkiesWebViewPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var binding: FlutterPlugin.FlutterPluginBinding? = null
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding
        channel = MethodChannel(binding.binaryMessenger, "binkies/webview").also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        this.binding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Number>("webViewId")?.toLong()
        val webView = binding?.let { binding -> id?.let { WebViewFlutterAndroidExternalApi.getWebView(binding, it) } }
        if (webView == null) return result.error("no_webview", "No WebView with id $id", null)

        when (call.method) {
            // Pauses the page (timers, the 3D render loop) while the app is in the background
            "setPaused" -> {
                if (call.argument<Boolean>("paused") == true) webView.onPause() else webView.onResume()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
