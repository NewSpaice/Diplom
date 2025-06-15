import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/steam_service.dart';
import '../services/cache_manager.dart';
import '../providers/steam_api_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/profile_provider.dart';
import 'package:provider/provider.dart';
import '../services/database_helper.dart';

class ProfileScreen extends StatefulWidget {
  final String steamId;

  const ProfileScreen({super.key, required this.steamId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  ProfileProvider? _profileProvider;
  bool _isInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_isInitialized) {
      _initializeProfile();
      _isInitialized = true;
    }
  }

  Future<void> _initializeProfile() async {
    try {
      final apiProvider = context.read<SteamApiProvider>();
      final apiKey = apiProvider.apiKey;
      
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('API ключ не установлен');
      }
      
      final prefs = await SharedPreferences.getInstance();
      final cacheManager = CacheManager(prefs);
      final steamService = SteamService(apiKey, prefs);
      
      _profileProvider = ProfileProvider(
        steamId: widget.steamId,
        cacheManager: cacheManager,
        steamService: steamService,
      );
      
      // Добавляем слушатель для обновления UI
      _profileProvider!.addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
      
      await _profileProvider!.initialize();
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка инициализации профиля: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _profileProvider?.dispose();
    super.dispose();
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
          IconButton(
            icon: const Icon(Icons.storage),
            onPressed: () async {
              try {
                final prefs = await SharedPreferences.getInstance();
                final apiProvider = context.read<SteamApiProvider>();
                final steamService = SteamService(apiProvider.apiKey!, prefs);
                final databaseHelper = DatabaseHelper();
                final dbPath = await databaseHelper.getDatabasePath();
                
                if (mounted) {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Путь к базе данных'),
                      content: SelectableText(dbPath),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Закрыть'),
                        ),
                      ],
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка: $e')),
                  );
                }
              }
            },
            tooltip: 'Показать путь к БД',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _profileProvider == null
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
                            _formatDate(_profileProvider!.profileData!['response']['players'][0]['timecreated']),
                          ),
                          _buildInfoRow(
                            'Последний онлайн',
                            _formatDate(_profileProvider!.profileData!['response']['players'][0]['lastlogoff']),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Статистика Dota 2
                      if (_profileProvider!.statsData != null) ...[
                        _buildInfoCard(
                          'Статистика Dota 2',
                          [
                            _buildInfoRow(
                              'Всего матчей',
                              _profileProvider!.statsData!['total_matches'].toString(),
                            ),
                            _buildInfoRow(
                              'Победы',
                              '${_profileProvider!.statsData!['wins']} (${_profileProvider!.statsData!['win_rate']?.toStringAsFixed(1) ?? '0.0'}%)',
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
                      if (_profileProvider!.statsData != null && _profileProvider!.statsData!['rank_tier'] != null && _profileProvider!.statsData!['rank_tier'] > 0) ...[
                        _buildRankCard(),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildPlayerCard() {
    final player = _profileProvider!.profileData!['response']['players'][0];
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
    final rankTier = _profileProvider!.statsData!['rank_tier'];
    final leaderboardRank = _profileProvider!.statsData!['leaderboard_rank'];
    
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
    if (_profileProvider != null) {
      final imagePath = _profileProvider!.getRankImageUrl(rankTier);
      print('🏅 Rank $rankTier medal image path: $imagePath');
      return imagePath;
    } else {
      // Fallback логика
      if (rankTier == 0) return 'ranks/rank_icon_0.png';
      if (rankTier >= 80) return 'ranks/rank_icon_${rankTier}.webp';
      if (rankTier == 11) return 'ranks/rank-icon-11.png';
      if (rankTier == 12) return 'ranks/rank_icon_12.png';
      return 'ranks/rank_icon_${rankTier}.webp';
    }
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
      case 0:
        return Colors.grey;
      case 1:
        return Colors.brown;
      case 2:
        return Colors.green;
      case 3:
        return Colors.blue;
      case 4:
        return Colors.purple;
      case 5:
        return Colors.orange;
      case 6:
        return Colors.cyan;
      case 7:
        return Colors.yellow;
      case 8:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
} 