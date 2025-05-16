import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/steam_service.dart';
import '../providers/steam_api_provider.dart';
import 'package:provider/provider.dart';

class ProfileScreen extends StatefulWidget {
  final String steamId;

  const ProfileScreen({super.key, required this.steamId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _profileData;
  Map<String, dynamic>? _statsData;

bool _isInitialized = false;

@override
void didChangeDependencies() {
  super.didChangeDependencies();

  if (!_isInitialized) {
    _loadProfile();
    _isInitialized = true;
  }
}

  Future<void> _loadProfile() async {
  try {
    final apiProvider = Provider.of<SteamApiProvider>(context, listen: false);
    if (apiProvider.apiKey == null) {
      throw Exception('API ключ не установлен');
    }

    final prefs = await SharedPreferences.getInstance();
    final steamService = SteamService(apiProvider.apiKey!, prefs);

    final profileData = await steamService.getPlayerProfile(widget.steamId);
    final statsData = await steamService.getPlayerStats(widget.steamId);

    setState(() {
      _profileData = profileData;
      _statsData = statsData;
      _isLoading = false;
    });
  } catch (e) {
    setState(() {
      _isLoading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки профиля: $e')),
      );
    }
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _profileData == null
              ? const Center(child: Text('Не удалось загрузить профиль'))
              : CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      expandedHeight: 200,
                      pinned: true,
                      flexibleSpace: FlexibleSpaceBar(
                        title: Text(_profileData!['response']['players'][0]['personaname'] ?? 'Профиль'),
                        background: Image.network(
                          _profileData!['response']['players'][0]['avatarfull'] ??
                              'https://steamcdn-a.akamaihd.net/steamcommunity/public/images/avatars/fe/fef49e7fa7e1997310d705b2a6158ff8dc1cdfeb_full.jpg',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInfoCard(
                              'Основная информация',
                              [
                                _buildInfoRow('Steam ID', widget.steamId),
                                _buildInfoRow(
                                  'Дата регистрации',
                                  _formatDate(_profileData!['response']['players'][0]['timecreated']),
                                ),
                                _buildInfoRow(
                                  'Последний онлайн',
                                  _formatDate(_profileData!['response']['players'][0]['lastlogoff']),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (_statsData != null) ...[
                              _buildInfoCard(
                                'Статистика Dota 2',
                                [
                                  _buildInfoRow(
                                    'Всего матчей',
                                    _statsData!['total_matches'].toString(),
                                  ),
                                  _buildInfoRow(
                                    'Победы',
                                    '${_statsData!['wins']} (${_calculateWinRate(_statsData!['wins'], _statsData!['total_matches'])}%)',
                                  ),
                                  _buildInfoRow(
                                    'Средний KDA',
                                    _calculateKDA(_statsData!['kills'], _statsData!['deaths'], _statsData!['assists']),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
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

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${date.day}.${date.month}.${date.year}';
  }

  String _calculateWinRate(int wins, int total) {
    if (total == 0) return '0';
    return ((wins / total) * 100).toStringAsFixed(1);
  }

  String _calculateKDA(int kills, int deaths, int assists) {
    if (deaths == 0) return '${kills + assists}';
    return ((kills + assists) / deaths).toStringAsFixed(2);
  }
} 