import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// Page that runs the Binkies integration (the 3D viewer) full size in its #target element.
/// The app only loads it once and then drives it through window.binkies.setSettings.
const viewerUrl = 'https://mobile-app.binkies3d.com/';

/// What the viewer shows. Pass a new one to [BinkiesViewer] to change something, it then updates the page.
///
/// - [product]: Binkies content id, e.g. "samsung-galaxy-z-flip8-cream"
/// - [thumbnailsPlacement]: where the thumbnail strip is placed
/// - [thumbnailsSelectedColor]: border color of the selected thumbnail
@immutable
class BinkiesSettings {
  const BinkiesSettings({
    required this.product,
    this.thumbnailsPlacement = ThumbnailsPlacement.bottom,
    this.thumbnailsSelectedColor = const Color(0xFF262626),
  });

  final String product;
  final ThumbnailsPlacement thumbnailsPlacement;
  final Color thumbnailsSelectedColor;

  /// The settings in the shape the page expects. The page rejects unknown keys and invalid values with an "error" message.
  Map<String, Object> toJson() => {
    'product': product,
    'gallery': {
      'thumbnails': {'placement': thumbnailsPlacement.name, 'selectedColor': _cssColor(thumbnailsSelectedColor)},
    },
  };
}

enum ThumbnailsPlacement { bottom, left, right }

/// The 3D viewer page in a WebView, talking to it over the BinkiesNative bridge.
///
/// - [settings] is what the viewer shows. Changing them (e.g. another product) updates the viewer without reloading the page.
/// - [visible] is whether the viewer takes up space. Pass in what [onVisibilityChange] last reported.
/// - [onVisibilityChange] is called with true when the page sends "show" (the product's 3D model has loaded)
///   and with false when it sends "hide" (the product has no 3D model, or the device can't render it).
/// - [onError] is called with everything the page logs as an error, e.g. to forward it to your crash reporting.
///   The errors are printed with debugPrint either way.
///
/// Hiding collapses a clipping box instead of removing the WebView: a WebView that isn't shown pauses
/// the page's rendering, so the next model would never finish loading and "show" would never arrive.
/// The WebView keeps its full size and only gets clipped away.
class BinkiesViewer extends StatefulWidget {
  const BinkiesViewer({
    super.key,
    required this.settings,
    required this.visible,
    required this.onVisibilityChange,
    this.onError,
  });

  final BinkiesSettings settings;
  final bool visible;
  final ValueChanged<bool> onVisibilityChange;
  final ValueChanged<String>? onError;

  @override
  State<BinkiesViewer> createState() => _BinkiesViewerState();
}

class _BinkiesViewerState extends State<BinkiesViewer> with WidgetsBindingObserver {
  // One WebView for the lifetime of this widget. Unlike an Android Activity, Flutter keeps it on rotation.
  final _controller = WebViewController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    // chrome://inspect for debug builds (Safari's Web Inspector on iOS)
    if (kDebugMode) {
      final platform = _controller.platform;
      if (platform is AndroidWebViewController) await AndroidWebViewController.enableDebugging(true);
      if (platform is WebKitWebViewController) await platform.setInspectable(true);
    }
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    // Must be added before loading, the page posts as soon as it starts (it asks for the settings right away)
    await _controller.addJavaScriptChannel(
      'BinkiesNative',
      onMessageReceived: (message) => _onBridgeMessage(message.message),
    );
    await _controller.loadRequest(Uri.parse(viewerUrl));
  }

  // The page posts {"type": "setSettings" | "show" | "hide"} and {"type": "error", "message": "...", "stack": "..."} (stack is optional)
  void _onBridgeMessage(String json) {
    debugPrint('[Binkies] bridge message: $json');
    if (!mounted) return;
    final message = jsonDecode(json);
    if (message is! Map<String, dynamic>) return;
    switch (message['type']) {
      // The page is ready and asks for its settings, once per page load
      case 'setSettings':
        _setSettings(widget.settings);
      case 'show':
        widget.onVisibilityChange(true);
      case 'hide':
        widget.onVisibilityChange(false);
      // Anything the page logged as an error, e.g. invalid settings
      case 'error':
        final error = _errorText(message['message'] as String? ?? '', message['stack'] as String? ?? '');
        debugPrint('[Binkies] page error: $error');
        widget.onError?.call(error);
    }
  }

  // Sends the full settings to the page. JSON is a valid JS object literal, so it can be inlined into the script.
  // window.binkies only exists once the page is ready, before that this does nothing.
  // Errors (e.g. invalid settings) are logged with console.error, which the page sends back as an "error" message.
  void _setSettings(BinkiesSettings settings) {
    final script =
        'try { window.binkies?.setSettings(${jsonEncode(settings.toJson())}) } catch (error) { console.error(error) }';
    unawaited(
      _controller
          .runJavaScript(script)
          .catchError((Object error) => debugPrint('[Binkies] runJavaScript failed: $error')),
    );
  }

  @override
  void didUpdateWidget(BinkiesViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sends the settings whenever they change. While the page is still loading this does nothing,
    // the page asks for the current settings once it is ready.
    // Compared as JSON, so a field added to toJson is compared too.
    if (jsonEncode(widget.settings.toJson()) != jsonEncode(oldWidget.settings.toJson())) _setSettings(widget.settings);
  }

  // Pauses the page (timers, the 3D render loop) while the app is in the background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(BinkiesWebViewHost.setPaused(_controller, true));
    if (state == AppLifecycleState.resumed) unawaited(BinkiesWebViewHost.setPaused(_controller, false));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Full width, 5:6 (width:height) leaves room for the model and the thumbnails below it
        final viewerHeight = constraints.maxWidth * 1.2;

        // The box animates its height and clips, the WebView inside it always keeps viewerHeight,
        // pinned to the top, so the page never gets resized and the viewer is revealed from the top down
        return TweenAnimationBuilder<double>(
          tween: Tween(end: widget.visible ? viewerHeight : 0),
          duration: const Duration(milliseconds: 300),
          curve: Curves.fastOutSlowIn,
          builder: (context, height, child) => SizedBox(height: height, child: child),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: viewerHeight,
              maxHeight: viewerHeight,
              child: WebViewWidget(controller: _controller),
            ),
          ),
        );
      },
    );
  }
}

// CSS hex color with alpha: #RRGGBBAA
String _cssColor(Color color) {
  final argb = color.toARGB32();
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  final alpha = (argb >>> 24).toRadixString(16).padLeft(2, '0');
  return '#$rgb$alpha';
}

// A JS stack usually starts with the message itself, so it's only added when it doesn't
String _errorText(String message, String stack) {
  if (stack.isEmpty) return message;
  if (stack.startsWith(message)) return stack;
  return '$message\n$stack';
}

/// What webview_flutter doesn't offer, done natively on the app side (MainActivity.kt): pausing the WebView.
abstract final class BinkiesWebViewHost {
  static const _channel = MethodChannel('binkies/webview');

  /// Pauses or resumes the page. Only Android needs it, iOS suspends a WebView in the background on its own.
  static Future<void> setPaused(WebViewController controller, bool paused) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final android = controller.platform as AndroidWebViewController;
    // Identifies the native WebView, see WebViewFlutterAndroidExternalApi
    await _channel.invokeMethod<void>('setPaused', {'webViewId': android.webViewIdentifier, 'paused': paused});
  }
}
