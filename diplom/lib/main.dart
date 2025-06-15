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
import 'screens/api_key_screen.dart';
import 'services/steam_auth_service.dart';
import 'providers/steam_api_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/app_state_provider.dart';
import 'providers/matches_provider.dart';
import 'services/steam_service.dart';
import 'services/cache_manager.dart';
import 'services/database_helper.dart';

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
  final themeProvider = ThemeProvider();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) => themeProvider,
        ),
        ChangeNotifierProvider(
          create: (context) => apiProvider,
        ),
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
    return Consumer2<SteamApiProvider, ThemeProvider>(
      builder: (context, apiProvider, themeProvider, child) {
        if (apiProvider.apiKey == null) {
          return MaterialApp(
            title: 'Dota 2 Stats',
            debugShowCheckedModeBanner: false,
            theme: ThemeProvider.lightTheme,
            darkTheme: ThemeProvider.darkTheme,
            themeMode: themeProvider.themeMode,
            home: ApiKeyScreen(),
            routes: {
              '/api-key': (context) => ApiKeyScreen(),
            },
          );
        }
        return MaterialApp(
          title: 'Dota 2 Stats',
          debugShowCheckedModeBanner: false,
          theme: ThemeProvider.lightTheme,
          darkTheme: ThemeProvider.darkTheme,
          themeMode: themeProvider.themeMode,
          home: LoginScreen(authService: authService),
          routes: {
            '/api-key': (context) => ApiKeyScreen(),
          },
        );
      },
    );
  }
}

class LoginScreen extends StatelessWidget {
  final SteamAuthService authService;

  const LoginScreen({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    final apiProvider = context.watch<SteamApiProvider>();
    
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
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ApiKeyScreen()),
                );
              },
              child: const Text('Изменить API ключ'),
            ),
            const SizedBox(height: 16),
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
  void initState() {
    super.initState();
    _loadSelectedIndex();
  }

  Future<void> _loadSelectedIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt('selected_tab_index') ?? 0;
    if (mounted) {
      setState(() {
        _selectedIndex = savedIndex;
      });
    }
  }

  Future<void> _saveSelectedIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selected_tab_index', index);
  }

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
          _saveSelectedIndex(index);
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


