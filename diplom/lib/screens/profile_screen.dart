import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/steam_service.dart';
import '../providers/steam_api_provider.dart';
import '../providers/theme_provider.dart';
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
  SteamService? _steamService;

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
    _steamService = SteamService(apiProvider.apiKey!, prefs);
    
    // Загружаем константы рангов
    await _steamService!.getRankConstants();

    // Сначала загружаем профиль
    final profileData = await _steamService!.getPlayerProfile(widget.steamId);
    
    // Загружаем статистику отдельно, чтобы при ошибке основной профиль все равно показался
    Map<String, dynamic>? statsData;
    try {
      statsData = await _steamService!.getPlayerStats(widget.steamId);
    } catch (e) {
      print('Error loading player stats: $e');
      // Статистика не загрузилась, но это не критично
    }

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
        SnackBar(
          content: Text('Ошибка загрузки профиля: $e'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () {
              setState(() {
                _isLoading = true;
              });
              _loadProfile();
            },
          ),
        ),
      );
    }
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль игрока'),
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _profileData == null
              ? const Center(child: Text('Не удалось загрузить профиль'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Профиль игрока
                      _buildPlayerCard(),
                      const SizedBox(height: 16),
                      
                      // Основная информация
                      _buildInfoCard(
                        'Основная информация',
                        [
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
                      
                      // Статистика Dota 2
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
                              '${_statsData!['wins']} (${_statsData!['win_rate']?.toStringAsFixed(1) ?? '0.0'}%)',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ] else ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 48,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Статистика недоступна',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Попробуйте обновить страницу',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      
                      // Ранг
                      if (_statsData != null && _statsData!['rank_tier'] != null && _statsData!['rank_tier'] > 0) ...[
                        _buildRankCard(),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildPlayerCard() {
    final player = _profileData!['response']['players'][0];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            // Аватар
            ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: Image.network(
                player['avatarfull'] ??
                    'https://steamcdn-a.akamaihd.net/steamcommunity/public/images/avatars/fe/fef49e7fa7e1997310d705b2a6158ff8dc1cdfeb_full.jpg',
                width: 80,
                height: 80,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 16),
            
            // Информация об игроке
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player['personaname'] ?? 'Неизвестный игрок',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getOnlineStatus(player['personastate']),
                    style: TextStyle(
                      color: _getOnlineStatusColor(player['personastate']),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankCard() {
    final rankTier = _statsData!['rank_tier'];
    final leaderboardRank = _statsData!['leaderboard_rank'];
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ранг',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Настоящая медалька ранга из локальных ассетов
                Container(
                  width: 60,
                  height: 60,
                  child: Image.asset(
                    _getRankImageUrl(rankTier),
                    width: 60,
                    height: 60,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      print('❌ Local rank image failed: $error');
                      print('🎨 Using colored icon fallback for rank $rankTier');
                      
                      // Если локальное изображение не найдено, показываем цветную иконку
                      return Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: _getRankColor(rankTier),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.military_tech,
                          color: Colors.white,
                          size: 30,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getRankName(rankTier),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (leaderboardRank != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Позиция в таблице лидеров: #$leaderboardRank',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
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

  String _getRankName(int rankTier) {
    if (rankTier == 0) return 'Без ранга';
    
    final rankNumber = (rankTier / 10).floor();
    final rankStar = rankTier % 10;
    
    String rankName;
    switch (rankNumber) {
      case 1:
        rankName = 'Herald';
        break;
      case 2:
        rankName = 'Guardian';
        break;
      case 3:
        rankName = 'Crusader';
        break;
      case 4:
        rankName = 'Archon';
        break;
      case 5:
        rankName = 'Legend';
        break;
      case 6:
        rankName = 'Ancient';
        break;
      case 7:
        rankName = 'Divine';
        break;
      case 8:
        return 'Immortal';
      default:
        return 'Неизвестный ранг';
    }
    
    return '$rankName $rankStar';
  }

  String _getRankImageUrl(int rankTier) {
    String imagePath;
    
    if (_steamService != null) {
      imagePath = _steamService!.getRankImageUrl(rankTier);
    } else {
      // Fallback если steamService не инициализирован - используем локальные ассеты
      if (rankTier == 0) {
        imagePath = 'ranks/rank_icon_0.png';
      } else {
        imagePath = 'ranks/rank_icon_$rankTier.png';
      }
    }
    
    print('🏅 Rank $rankTier medal image path (WEBP): $imagePath');
    return imagePath;
  }

  String _getOnlineStatus(int? personastate) {
    switch (personastate) {
      case 0:
        return 'Не в сети';
      case 1:
        return 'В сети';
      case 2:
        return 'Занят';
      case 3:
        return 'Отошёл';
      case 4:
        return 'Дремлет';
      case 5:
        return 'Ищет игру';
      case 6:
        return 'Играет';
      default:
        return 'Неизвестно';
    }
  }

  Color _getOnlineStatusColor(int? personastate) {
    switch (personastate) {
      case 1:
        return Colors.green;
      case 6:
        return Colors.blue;
      case 2:
      case 3:
      case 4:
      case 5:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Color _getRankColor(int rankTier) {
    final rankNumber = (rankTier / 10).floor();
    switch (rankNumber) {
      case 1:
        return Colors.brown;
      case 2:
        return Colors.grey;
      case 3:
        return Colors.orange;
      case 4:
        return Colors.purple;
      case 5:
        return Colors.blue;
      case 6:
        return Colors.cyan;
      case 7:
        return Colors.yellow[700]!;
      case 8:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
} 