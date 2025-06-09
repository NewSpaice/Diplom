import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:app_links/app_links.dart';
import 'package:provider/provider.dart';
import '../providers/steam_api_provider.dart';
import '../services/steam_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'dart:async';

class SteamLoginScreen extends StatefulWidget {
  const SteamLoginScreen({super.key});

  @override
  State<SteamLoginScreen> createState() => _SteamLoginScreenState();
}

class _SteamLoginScreenState extends State<SteamLoginScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  late SteamAuthService _authService;

  @override
  void initState() {
    super.initState();
    _initAuthService();
    _initWebView();
  }

  Future<void> _initAuthService() async {
    final prefs = await SharedPreferences.getInstance();
    _authService = SteamAuthService(prefs);
  }

  Future<bool> _checkConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  Future<void> _initWebView() async {
    // Проверяем интернет-соединение
    if (!await _checkConnectivity()) {
      _showError('Нет интернет-соединения. Проверьте подключение к сети.');
      return;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setUserAgent('Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36')
      ..enableZoom(true)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            print('📄 Page started loading: $url');
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            print('✅ Page finished loading: $url');
            setState(() {
              _isLoading = false;
            });
          },
          onNavigationRequest: (NavigationRequest request) async {
            print('🔍 Navigation request to: ${request.url}');
            
            if (request.url.startsWith('http://localhost:8080/auth/steam/callback')) {
              final uri = Uri.parse(request.url);
              final claimedId = uri.queryParameters['openid.claimed_id'];
              
              print('🎮 Claimed ID: $claimedId');
              
              if (claimedId != null && claimedId.contains('steamcommunity.com/openid/id/')) {
                final steamId = claimedId.split('/').last;
                print('✅ Extracted Steam ID: $steamId');
                
                // Сохраняем Steam ID
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('steam_id', steamId);
                
                if (mounted) {
                  // Переходим на главный экран
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => HomeScreen(steamId: steamId),
                    ),
                  );
                }
                return NavigationDecision.prevent;
              } else {
                _showError('Не удалось получить Steam ID из callback');
                return NavigationDecision.prevent;
              }
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (WebResourceError error) {
            print('❌ WebView error: ${error.description} (Code: ${error.errorCode})');
            if (mounted && error.errorCode != -999) { // Ignore cancelled requests
              _showError('Ошибка загрузки: ${error.description}');
            }
          },
          onHttpError: (HttpResponseError error) {
            print('❌ HTTP error: ${error.response?.statusCode}');
          },
        ),
      );

    // Загружаем URL авторизации Steam
    try {
      final loginUrl = await _authService.getSteamLoginUrl();
      print('🚀 Loading Steam auth URL: $loginUrl');
      
      // Добавляем таймаут
      Future.delayed(const Duration(seconds: 30), () {
        if (mounted && _isLoading) {
          _showError('Превышено время ожидания загрузки. Проверьте интернет-соединение.');
        }
      });
      
      await _controller.loadRequest(Uri.parse(loginUrl));
    } catch (e) {
      print('❌ Error loading auth URL: $e');
      if (mounted) {
        _showError('Ошибка загрузки страницы авторизации: $e');
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Повторить',
          textColor: Colors.white,
          onPressed: () {
            _initWebView();
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Вход через Steam'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initWebView,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Container(
              color: Colors.white.withOpacity(0.9),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Загрузка страницы входа Steam...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Это может занять несколько секунд',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 32),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _isLoading = false;
                        });
                      },
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('Отменить'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
} 