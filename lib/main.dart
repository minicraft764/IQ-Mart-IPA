import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const EcommerceApp());
}

class EcommerceApp extends StatelessWidget {
  const EcommerceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IQ Mart',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  static const MethodChannel _notificationChannel =
      MethodChannel('com.example.ecommerce/notifications');

  late final WebViewController _controller;
  bool _isLoading = true;
  String? _initError;

  static const String _pinchZoomBlockerJs = '''
    (function() {
      try {
        var meta = document.querySelector('meta[name="viewport"]');
        if (meta) meta.setAttribute('content', 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, shrink-to-fit=no');
        else {
          var m = document.createElement('meta');
          m.name = 'viewport';
          m.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, shrink-to-fit=no';
          document.head.appendChild(m);
        }
        function block(e){ e.preventDefault(); }
        document.addEventListener('gesturestart', block);
        document.addEventListener('gesturechange', block);
        document.addEventListener('gestureend', block);
        document.addEventListener('touchstart', function (e) { if (e.targetTouches.length > 1) block(e); }, { passive: false });
        document.addEventListener('touchmove', function (e) { if (e.targetTouches.length > 1) block(e); }, { passive: false });
      } catch (e) {}
    })();
  ''';

  @override
  void initState() {
    super.initState();
    _setupMethodChannel();
    _initWebView();
  }

  void _setupMethodChannel() {
    _notificationChannel.setMethodCallHandler((call) async {
      if (call.method == 'openProduct') {
        final prodId = call.arguments as String?;
        if (prodId != null && prodId.isNotEmpty) {
          _openProductInWebView(prodId);
        }
      }
    });
  }

  void _openProductInWebView(String productId) {
    _controller.runJavaScript('''
      (function() {
        if (window.location.pathname.indexOf('/account') !== -1) {
          window.location.href = '/?product=' + encodeURIComponent('$productId');
          return;
        }
        var count = 0;
        function tryOpen() {
          if (typeof window.openProductModal === 'function') {
            window.openProductModal('$productId', true);
          } else if (count < 40) {
            count++;
            setTimeout(tryOpen, 200);
          }
        }
        tryOpen();
      })();
    ''');
  }

  Future<void> _initWebView() async {
    try {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..addJavaScriptChannel(
          'NativeNotification',
          onMessageReceived: (JavaScriptMessage msg) async {
            try {
              final data = jsonDecode(msg.message);
              if (data['type'] == 'SHOW_NOTIFICATION') {
                debugPrint('NativeNotification: ignoring web local notification');
              } else if (data['type'] == 'SET_LANGUAGE') {
                final lang = data['lang'] as String? ?? 'en';
                await _notificationChannel.invokeMethod('setLanguage', {
                  'lang': lang,
                });
              } else if (data['type'] == 'DEBUG_LOG') {
                debugPrint('STORE_DEBUG: ${jsonEncode(data)}');
              }
            } catch (e) {
              debugPrint('NativeNotification error: $e');
            }
          },
        )
        ..addJavaScriptChannel(
          'NativeShare',
          onMessageReceived: (JavaScriptMessage msg) async {
            try {
              final data = jsonDecode(msg.message);
              await _notificationChannel.invokeMethod('share', {
                'title': data['title'] ?? '',
                'text': data['text'] ?? '',
                'url': data['url'] ?? '',
              });
            } catch (e) {
              debugPrint('NativeShare error: $e');
            }
          },
        )
        ..addJavaScriptChannel(
          'FlutterShare',
          onMessageReceived: (JavaScriptMessage msg) async {
            try {
              final data = jsonDecode(msg.message);
              await _notificationChannel.invokeMethod('share', {
                'title': data['title'] ?? '',
                'text': data['text'] ?? '',
                'url': data['url'] ?? '',
              });
            } catch (e) {
              debugPrint('FlutterShare error: $e');
            }
          },
        )
        ..addJavaScriptChannel(
          'NativeLocation',
          onMessageReceived: (JavaScriptMessage msg) async {
            try {
              final res =
                  await _notificationChannel.invokeMethod('getLocation');
              if (res != null && res is Map) {
                final success = res['success'] == true;
                final lat = res['latitude'];
                final lng = res['longitude'];
                final error = res['error'] ?? 'Unknown error';
                if (success && lat != null && lng != null) {
                  _controller.runJavaScript(
                    'if (typeof window.onNativeLocationSuccess === "function") window.onNativeLocationSuccess($lat, $lng);',
                  );
                } else {
                  final errClean = error.toString().replaceAll("'", "\\'");
                  _controller.runJavaScript(
                    'if (typeof window.onNativeLocationError === "function") window.onNativeLocationError(\'$errClean\');',
                  );
                }
              } else {
                _controller.runJavaScript(
                  'if (typeof window.onNativeLocationError === "function") window.onNativeLocationError("Could not retrieve location");',
                );
              }
            } catch (e) {
              final errClean = e.toString().replaceAll("'", "\\'");
              _controller.runJavaScript(
                'if (typeof window.onNativeLocationError === "function") window.onNativeLocationError(\'$errClean\');',
              );
            }
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              setState(() {
                _isLoading = true;
              });
            },
            onPageFinished: (String url) async {
              setState(() {
                _isLoading = false;
              });
              try {
                _controller.runJavaScript(_pinchZoomBlockerJs);
              } catch (_) {}
              try {
                final pendingProdId = await _notificationChannel
                    .invokeMethod<String>('getPendingProduct');
                if (pendingProdId != null && pendingProdId.isNotEmpty) {
                  _openProductInWebView(pendingProdId);
                }
              } catch (_) {}
            },
            onWebResourceError: (WebResourceError error) {
              debugPrint('WebResourceError: ${error.description}');
            },
            onNavigationRequest: (NavigationRequest request) {
              final url = request.url;
              if (url.startsWith('http://') || url.startsWith('https://')) {
                return NavigationDecision.navigate;
              }
              if (url.startsWith('file://') || url.startsWith('data:') || url.startsWith('about:')) {
                return NavigationDecision.navigate;
              }
              if (url.startsWith('flutter://')) {
                return NavigationDecision.navigate;
              }
              return NavigationDecision.navigate;
            },
          ),
        );

      // Enable WebChromeClient geolocation prompts on Android
      if (_controller.platform is AndroidWebViewController) {
        (_controller.platform as AndroidWebViewController)
            .setGeolocationPermissionsPromptCallbacks(
          onShowPrompt: (request) async {
            return const GeolocationPermissionsResponse(
              allow: true,
              retain: true,
            );
          },
        );
      }

      await _controller.loadFlutterAsset('assets/index.html');

      if (mounted) setState(() {});
    } catch (e) {
      setState(() {
        _initError = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text('Error loading store: $_initError'),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else {
          if (context.mounted) {
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        body: SafeArea(
          top: true,
          bottom: false,
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
