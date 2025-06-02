import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/steam_api_provider.dart';
import '../providers/theme_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ApiKeyScreen extends StatelessWidget {
  final _apiKeyController = TextEditingController();

  ApiKeyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Введите API ключ Steam'),
        actions: [
          IconButton(
            icon: Icon(
              context.watch<ThemeProvider>().isDarkMode
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            onPressed: () {
              context.read<ThemeProvider>().toggleTheme();
            },
            tooltip: context.watch<ThemeProvider>().isDarkMode
                ? 'Светлая тема'
                : 'Темная тема',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Для работы приложения необходим API ключ Steam',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API ключ Steam',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final apiKey = _apiKeyController.text.trim();
                if (apiKey.isNotEmpty) {
                  context.read<SteamApiProvider>().setApiKey(apiKey);
                  Navigator.pop(context);
                }
              },
              child: const Text('Сохранить'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                context.read<SteamApiProvider>().clearApiKey();
                Navigator.pop(context);
              },
              child: const Text('Очистить API ключ'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                launchUrl(Uri.parse('https://steamcommunity.com/dev/apikey'));
              },
              child: const Text('Как получить API ключ?'),
            ),
          ],
        ),
      ),
    );
  }
} 