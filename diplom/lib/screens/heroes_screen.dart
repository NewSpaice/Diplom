import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../services/steam_service.dart';
import '../providers/steam_api_provider.dart';

class HeroesScreen extends StatefulWidget {
  final String steamId;

  const HeroesScreen({super.key, required this.steamId});

  @override
  State<HeroesScreen> createState() => _HeroesScreenState();
}

class _HeroesScreenState extends State<HeroesScreen> {
  bool _isLoading = true;
  List<dynamic> _heroes = [];
  Map<String, dynamic> _heroStats = {};

  @override
  void initState() {
    super.initState();
    _loadHeroes();
  }

  Future<void> _loadHeroes() async {
    try {
      final apiProvider = context.read<SteamApiProvider>();
      final prefs = await SharedPreferences.getInstance();
      final steamService = SteamService(apiProvider.apiKey!, prefs);
      
      final heroesData = await steamService.getHeroes();
      final statsData = await steamService.getPlayerStats(widget.steamId);
      
      setState(() {
        _heroes = heroesData['result']['heroes'];
        _heroStats = statsData['heroes'] ?? {};
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки героев: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Статистика героев'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _heroes.isEmpty
              ? const Center(child: Text('Нет доступных данных'))
              : ListView.builder(
                  itemCount: _heroes.length,
                  itemBuilder: (context, index) {
                    final hero = _heroes[index];
                    final stats = _heroStats[hero['id'].toString()] ?? {};
                    return _buildHeroCard(hero, stats);
                  },
                ),
    );
  }

  Widget _buildHeroCard(Map<String, dynamic> hero, Map<String, dynamic> stats) {
    final matches = stats['games'] ?? 0;
    final wins = stats['win'] ?? 0;
    final winRate = matches > 0 ? (wins / matches * 100) : 0.0;
    final kda = matches > 0
        ? ((stats['kills'] ?? 0) + (stats['assists'] ?? 0)) / (stats['deaths'] ?? 1)
        : 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundImage: NetworkImage(
            'https://cdn.dota2.com/apps/dota2/images/heroes/${hero['name'].replaceAll('npc_dota_hero_', '')}_full.png',
          ),
        ),
        title: Text(
          hero['localized_name'],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Матчей: $matches | Побед: ${winRate.toStringAsFixed(1)}%',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _buildStatRow('KDA', kda.toStringAsFixed(2)),
                _buildStatRow('Убийств', (stats['kills'] ?? 0).toString()),
                _buildStatRow('Смертей', (stats['deaths'] ?? 0).toString()),
                _buildStatRow('Помощи', (stats['assists'] ?? 0).toString()),
                _buildStatRow('GPM', (stats['gold_per_min'] ?? 0).toString()),
                _buildStatRow('XPM', (stats['xp_per_min'] ?? 0).toString()),
                _buildStatRow('Урон', (stats['hero_damage'] ?? 0).toString()),
                _buildStatRow('Лечение', (stats['hero_healing'] ?? 0).toString()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
} 