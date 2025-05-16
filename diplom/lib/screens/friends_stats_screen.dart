import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../services/steam_service.dart';
import '../providers/steam_api_provider.dart';

class FriendsStatsScreen extends StatefulWidget {
  final String steamId;

  const FriendsStatsScreen({super.key, required this.steamId});

  @override
  State<FriendsStatsScreen> createState() => _FriendsStatsScreenState();
}

class _FriendsStatsScreenState extends State<FriendsStatsScreen> {
  bool _isLoading = true;
  List<dynamic> _friends = [];
  Map<String, dynamic> _playerStats = {};

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    try {
      final apiProvider = context.read<SteamApiProvider>();
      final prefs = await SharedPreferences.getInstance();
      final steamService = SteamService(apiProvider.apiKey!, prefs);
      
      final friendsData = await steamService.getFriendsList(widget.steamId);
      final playerStats = await steamService.getPlayerStats(widget.steamId);
      
      setState(() {
        _friends = friendsData['friendslist']['friends'] ?? [];
        _playerStats = playerStats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки друзей: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Статистика с друзьями'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _friends.isEmpty
              ? const Center(child: Text('Нет доступных друзей'))
              : ListView.builder(
                  itemCount: _friends.length,
                  itemBuilder: (context, index) {
                    final friend = _friends[index];
                    return _buildFriendCard(friend);
                  },
                ),
    );
  }

  Widget _buildFriendCard(Map<String, dynamic> friend) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundImage: NetworkImage(
            friend['avatar'] ?? 'https://steamcdn-a.akamaihd.net/steamcommunity/public/images/avatars/fe/fef49e7fa7e1997310d705b2a6158ff8dc1cdfeb_full.jpg',
          ),
        ),
        title: Text(
          friend['personaname'] ?? 'Неизвестный игрок',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Последний онлайн: ${_formatDate(friend['lastlogoff'])}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _buildComparisonRow(
                  'Всего матчей',
                  _playerStats['total_matches'] ?? 0,
                  friend['total_matches'] ?? 0,
                ),
                _buildComparisonRow(
                  'Процент побед',
                  _playerStats['win_rate'] ?? 0,
                  friend['win_rate'] ?? 0,
                  isPercentage: true,
                ),
                _buildComparisonRow(
                  'Средний KDA',
                  _playerStats['kda'] ?? 0,
                  friend['kda'] ?? 0,
                  isDecimal: true,
                ),
                _buildComparisonRow(
                  'GPM',
                  _playerStats['gold_per_min'] ?? 0,
                  friend['gold_per_min'] ?? 0,
                ),
                _buildComparisonRow(
                  'XPM',
                  _playerStats['xp_per_min'] ?? 0,
                  friend['xp_per_min'] ?? 0,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(String label, dynamic playerValue, dynamic friendValue, {bool isPercentage = false, bool isDecimal = false}) {
    final playerFormatted = isPercentage
        ? '${playerValue.toStringAsFixed(1)}%'
        : isDecimal
            ? playerValue.toStringAsFixed(2)
            : playerValue.toString();
    
    final friendFormatted = isPercentage
        ? '${friendValue.toStringAsFixed(1)}%'
        : isDecimal
            ? friendValue.toStringAsFixed(2)
            : friendValue.toString();

    final difference = playerValue - friendValue;
    final isBetter = difference > 0;
    final differenceFormatted = isPercentage
        ? '${difference.toStringAsFixed(1)}%'
        : isDecimal
            ? difference.toStringAsFixed(2)
            : difference.toString();

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
          Row(
            children: [
              Text(
                playerFormatted,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isBetter ? Icons.arrow_upward : Icons.arrow_downward,
                color: isBetter ? Colors.green : Colors.red,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                differenceFormatted,
                style: TextStyle(
                  color: isBetter ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                friendFormatted,
                style: const TextStyle(
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${date.day}.${date.month}.${date.year}';
  }
} 