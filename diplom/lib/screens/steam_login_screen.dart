import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/steam_api_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

class SteamLoginScreen extends StatefulWidget {
  const SteamLoginScreen({super.key});

  @override
  State<SteamLoginScreen> createState() => _SteamLoginScreenState();
}

class _SteamLoginScreenState extends State<SteamLoginScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    _initWebView();
  }

  Future<void> _initWebView() async {
    final apiProvider = context.read<SteamApiProvider>();
    final loginUrl = 'https://steamcommunity.com/openid/login?'
        'openid.ns=http://specs.openid.net/auth/2.0&'
        'openid.mode=checkid_setup&'
        'openid.return_to=http://localhost:8080/auth/steam/callback&'
        'openid.realm=http://localhost:8080&'
        'openid.identity=http://specs.openid.net/auth/2.0/identifier_select&'
        'openid.claimed_id=http://specs.openid.net/auth/2.0/identifier_select';

    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onNavigationRequest: (NavigationRequest request) async {
            if (request.url.startsWith('http://localhost:8080/auth/steam/callback')) {
              final uri = Uri.parse(request.url);
              final steamId = uri.queryParameters['openid.claimed_id']?.split('/').last;
              
              if (steamId != null) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('steam_id', steamId);
                
                if (mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => HomeScreen(steamId: steamId),
                    ),
                  );
                }
                return NavigationDecision.prevent;
              }
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(loginUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Вход через Steam'),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
} 