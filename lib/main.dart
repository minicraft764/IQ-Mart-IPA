import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

  HttpServer? _server;
  int? _serverPort;
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _setupMethodChannel();
    _startLocalServerAndInitWebView();
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

  Future<void> _startLocalServerAndInitWebView() async {
    try {
      // 1. Start local HTTP server on loopback (localhost)
      try {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8888);
      } catch (_) {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      }
      _serverPort = _server!.port;

      _server!.listen((HttpRequest request) async {
        try {
          var rawPath = request.uri.path;

          // Route mapping
          String assetPath;
          if (rawPath == '/' || rawPath.isEmpty || rawPath == '/index.html') {
            assetPath = 'assets/index.html';
          } else if (rawPath == '/account' ||
              rawPath == '/account/' ||
              rawPath == '/account/index.html') {
            assetPath = 'assets/account/index.html';
          } else if (rawPath.startsWith('/assets/')) {
            assetPath = rawPath.substring(1);
          } else {
            assetPath =
                'assets${rawPath.startsWith('/') ? rawPath : '/$rawPath'}';
          }

          // Determine MIME Content-Type
          String contentType = 'text/html; charset=utf-8';
          final lower = assetPath.toLowerCase();
          if (lower.endsWith('.js')) {
            contentType = 'application/javascript; charset=utf-8';
          } else if (lower.endsWith('.css')) {
            contentType = 'text/css; charset=utf-8';
          } else if (lower.endsWith('.png')) {
            contentType = 'image/png';
          } else if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
            contentType = 'image/jpeg';
          } else if (lower.endsWith('.ico')) {
            contentType = 'image/x-icon';
          } else if (lower.endsWith('.svg')) {
            contentType = 'image/svg+xml';
          } else if (lower.endsWith('.json')) {
            contentType = 'application/json; charset=utf-8';
          } else if (lower.endsWith('.woff2')) {
            contentType = 'font/woff2';
          } else if (lower.endsWith('.woff')) {
            contentType = 'font/woff';
          } else if (lower.endsWith('.ttf')) {
            contentType = 'font/ttf';
          }

          try {
            final byteData = await rootBundle.load(assetPath);
            request.response.headers.set('Content-Type', contentType);
            request.response.headers.set('Access-Control-Allow-Origin', '*');
            request.response.headers.set('Cache-Control', 'no-cache');
            request.response.add(byteData.buffer.asUint8List(
              byteData.offsetInBytes,
              byteData.lengthInBytes,
            ));
            await request.response.close();
          } catch (_) {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('Not found: $assetPath');
            await request.response.close();
          }
        } catch (_) {
          try {
            request.response.statusCode = HttpStatus.internalServerError;
            await request.response.close();
          } catch (_) {}
        }
      });

      // 2. Initialize WebViewController pointing to localhost
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..addJavaScriptChannel(
          'NativeNotification',
          onMessageReceived: (JavaScriptMessage msg) async {
            try {
              final data = jsonDecode(msg.message);
              if (data['type'] == 'SHOW_NOTIFICATION') {
                // Disabled: All notifications are broadcasted through Firebase Cloud Messaging (FCM)
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
              if (!url.startsWith('http://') && !url.startsWith('https://')) {
                return NavigationDecision.prevent;
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

      await _controller.loadRequest(Uri.parse('http://localhost:$_serverPort/'));

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
    _server?.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text('Error starting local server: $_initError'),
          ),
        ),
      );
    }

    if (_serverPort == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
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
