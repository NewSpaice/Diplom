import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../services/steam_service.dart';
import '../providers/steam_api_provider.dart';

class MatchesScreen extends StatefulWidget {
  final String steamId;

  const MatchesScreen({super.key, required this.steamId});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  bool _isLoading = true;
  List<dynamic> _matches = [];
  String _selectedHero = 'Все герои';
  String _selectedResult = 'Все результаты';
  List<String> _heroes = ['Все герои'];

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  Future<void> _loadMatches() async {
    try {
      final apiProvider = context.read<SteamApiProvider>();
      final prefs = await SharedPreferences.getInstance();
      final steamService = SteamService(apiProvider.apiKey!, prefs);
      
      final matchesData = await steamService.getMatchHistory(widget.steamId);
      final heroesData = await steamService.getHeroes();
      
      setState(() {
        _matches = matchesData['result']['matches'] ?? [];
        _heroes = ['Все герои', ...heroesData['result']['heroes'].map((h) => h['localized_name']).toList()];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки матчей: $e')),
        );
      }
    }
  }

  List<dynamic> get _filteredMatches {
    return _matches.where((match) {
      final heroMatch = _selectedHero == 'Все герои' || 
          match['hero_name'] == _selectedHero;
      final resultMatch = _selectedResult == 'Все результаты' ||
          (_selectedResult == 'Победа' && match['radiant_win'] == (match['player_slot'] < 128)) ||
          (_selectedResult == 'Поражение' && match['radiant_win'] != (match['player_slot'] < 128));
      return heroMatch && resultMatch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('История матчей'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _matches.isEmpty
              ? const Center(child: Text('Нет доступных матчей'))
              : ListView.builder(
                  itemCount: _filteredMatches.length,
                  itemBuilder: (context, index) {
                    final match = _filteredMatches[index];
                    return _buildMatchCard(match);
                  },
                ),
    );
  }

  Widget _buildMatchCard(Map<String, dynamic> match) {
    final isWin = match['radiant_win'] == (match['player_slot'] < 128);
    final duration = Duration(seconds: match['duration']);
    final startTime = DateTime.fromMillisecondsSinceEpoch(match['start_time'] * 1000);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isWin ? Colors.green : Colors.red,
          child: Icon(
            isWin ? Icons.emoji_events : Icons.sports_esports,
            color: Colors.white,
          ),
        ),
        title: Text(
          '${match['hero_name']}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${startTime.day}.${startTime.month}.${startTime.year} ${startTime.hour}:${startTime.minute}\n'
          'Длительность: ${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'KDA: ${match['kills']}/${match['deaths']}/${match['assists']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'GPM: ${match['gold_per_min']}',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
        onTap: () => _showMatchDetails(match),
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Фильтры'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedHero,
              decoration: const InputDecoration(labelText: 'Герой'),
              items: _heroes.map((hero) {
                return DropdownMenuItem(
                  value: hero,
                  child: Text(hero),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedHero = value!;
                });
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedResult,
              decoration: const InputDecoration(labelText: 'Результат'),
              items: ['Все результаты', 'Победа', 'Поражение'].map((result) {
                return DropdownMenuItem(
                  value: result,
                  child: Text(result),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedResult = value!;
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _selectedHero = 'Все герои';
                _selectedResult = 'Все результаты';
              });
              Navigator.pop(context);
            },
            child: const Text('Сбросить'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  void _showMatchDetails(Map<String, dynamic> match) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Детали матча',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                _buildDetailRow('Герой', match['hero_name']),
                _buildDetailRow('Результат', match['radiant_win'] == (match['player_slot'] < 128) ? 'Победа' : 'Поражение'),
                _buildDetailRow('KDA', '${match['kills']}/${match['deaths']}/${match['assists']}'),
                _buildDetailRow('GPM', match['gold_per_min'].toString()),
                _buildDetailRow('XPM', match['xp_per_min'].toString()),
                _buildDetailRow('Урон', match['hero_damage'].toString()),
                _buildDetailRow('Лечение', match['hero_healing'].toString()),
                _buildDetailRow('Длительность', '${match['duration'] ~/ 60}:${(match['duration'] % 60).toString().padLeft(2, '0')}'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 16,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
} 