import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'screens/profile_screen.dart';
import 'screens/matches_screen.dart';
import 'screens/heroes_screen.dart';
import 'screens/friends_stats_screen.dart';
import 'screens/steam_login_screen.dart';
import 'services/steam_auth_service.dart';
import 'providers/steam_api_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Инициализация WebView платформы
  if (WebViewPlatform.instance == null) {
    if (Platform.isAndroid) {
      WebViewPlatform.instance = AndroidWebViewPlatform();
    } else if (Platform.isIOS) {
      WebViewPlatform.instance = WebKitWebViewPlatform();
    }
  }
   
  final prefs = await SharedPreferences.getInstance();
  final authService = SteamAuthService(prefs);
  final apiProvider = SteamApiProvider(prefs);
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => apiProvider),
      ],
      child: MyApp(authService: authService),
    ),
  );
}

class MyApp extends StatelessWidget {
  final SteamAuthService authService;

  const MyApp({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dota 2 Stats',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: LoginScreen(authService: authService),
    );
  }
}

class LoginScreen extends StatelessWidget {
  final SteamAuthService authService;

  const LoginScreen({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    final apiProvider = context.watch<SteamApiProvider>();
    
    if (apiProvider.apiKey == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Dota 2 Stats',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Для работы приложения необходим API ключ Steam',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'API ключ Steam',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) async {
                    await apiProvider.setApiKey(value);
                  },
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () async {
                    const url = 'https://steamcommunity.com/dev/apikey';
                    if (await canLaunchUrl(Uri.parse(url))) {
                      await launchUrl(Uri.parse(url));
                    }
                  },
                  child: const Text('Получить API ключ'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Dota 2 Stats',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () async {
                if (await authService.isAuthenticated()) {
                  final steamId = await authService.getSteamId();
                  if (steamId != null) {
                    if (context.mounted) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (context) => HomeScreen(steamId: steamId),
                        ),
                      );
                    }
                  }
                } else {
                  if (context.mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const SteamLoginScreen(),
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.login),
              label: const Text('Войти через Steam'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final String steamId;

  const HomeScreen({super.key, required this.steamId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      ProfileScreen(steamId: widget.steamId),
      MatchesScreen(steamId: widget.steamId),
      HeroesScreen(steamId: widget.steamId),
      FriendsStatsScreen(steamId: widget.steamId),
    ];

    return Scaffold(
      body: screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.person),
            label: 'Профиль',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_esports),
            label: 'Матчи',
          ),
          NavigationDestination(
            icon: Icon(Icons.people),
            label: 'Герои',
          ),
          NavigationDestination(
            icon: Icon(Icons.group),
            label: 'Друзья',
          ),
        ],
      ),
    );
  }
}


