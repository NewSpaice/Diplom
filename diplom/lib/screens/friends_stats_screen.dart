import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../services/steam_service.dart';
import '../services/cache_manager.dart';
import '../providers/steam_api_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/friends_provider.dart';

enum SortType {
  games,
  winRate,
}

enum SortDirection {
  ascending,
  descending,
}

class FriendsStatsScreen extends StatefulWidget {
  final String steamId;

  const FriendsStatsScreen({super.key, required this.steamId});

  @override
  State<FriendsStatsScreen> createState() => _FriendsStatsScreenState();
}

class _FriendsStatsScreenState extends State<FriendsStatsScreen> {
  bool _isLoading = true;
  FriendsProvider? _friendsProvider;
  bool _showSorting = false;

  @override
  void initState() {
    super.initState();
    _initializeFriends();
  }

  Future<void> _initializeFriends() async {
    try {
      final apiProvider = context.read<SteamApiProvider>();
      final apiKey = apiProvider.apiKey;
      
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('API ключ не установлен');
      }
      
      final prefs = await SharedPreferences.getInstance();
      final cacheManager = CacheManager(prefs);
      final steamService = SteamService(apiKey, prefs);
      
      _friendsProvider = FriendsProvider(
        steamId: widget.steamId,
        cacheManager: cacheManager,
        steamService: steamService,
      );
      
      // Добавляем слушатель для обновления UI
      _friendsProvider!.addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
      
      await _friendsProvider!.initialize();
      
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
            content: Text('Ошибка инициализации друзей: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _friendsProvider?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Статистика с друзьями'),
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
            icon: const Icon(Icons.sort),
            onPressed: () {
              setState(() {
                _showSorting = !_showSorting;
              });
            },
            tooltip: 'Сортировка',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _friendsProvider?.forceRefresh(),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Загружаем статистику с друзьями...'),
                ],
              ),
            )
          : _friendsProvider?.friendsWithGames.isEmpty == true
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Нет совместных игр',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'У вас нет друзей, с которыми играли в Dota 2',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Заголовок с общей информацией
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16.0),
                      color: Theme.of(context).cardColor,
                      child: Column(
                        children: [
                          Text(
                            'Друзей с совместными играми: ${_friendsProvider?.friendsWithGames.length}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Панель сортировки
                    if (_showSorting && _friendsProvider?.friendsWithGames.isNotEmpty == true) _buildSortingPanel(),
                    
                    // Список друзей с совместной статистикой
                    Expanded(
                      child: _friendsProvider?.friendsWithGames.isEmpty == true
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.sort,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Нет друзей для сортировки',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Попробуйте добавить друзей',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(8.0),
                              itemCount: _friendsProvider?.friendsWithGames.length,
                              itemBuilder: (context, index) {
                                final friend = _friendsProvider?.friendsWithGames[index];
                                return friend != null ? _buildFriendCard(friend) : const SizedBox.shrink();
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSortingPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey[300]!,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.sort,
                size: 20,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 8),
              Text(
                'Сортировка',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    _friendsProvider?.resetSorting();
                  });
                },
                child: const Text('Сбросить'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Сортировка по количеству игр
          Text(
            'Количество совместных игр',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _friendsProvider?.sortByGames();
                });
              },
              icon: Icon(
                Icons.sort,
                size: 18,
                color: Colors.white,
              ),
              label: Text(
                'Сортировать по играм',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Сортировка по винрейту
          Text(
            'Винрейт в совместных играх',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _friendsProvider?.sortByWinRate();
                });
              },
              icon: Icon(
                Icons.sort,
                size: 18,
                color: Colors.white,
              ),
              label: Text(
                'Сортировать по винрейту',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Информация о сортировке
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Colors.blue[600],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _friendsProvider?.currentSortType != null
                        ? 'Сортировка: ${_getSortDescription()} • Показано: ${_friendsProvider?.friendsWithGames.length} друзей'
                        : 'Показано: ${_friendsProvider?.friendsWithGames.length} друзей',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[600],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendCard(Map<String, dynamic> friend) {
    final friendName = friend['personaname'] ?? 'Неизвестный игрок';
    final avatarUrl = friend['avatar'] ?? 
        'https://steamcdn-a.akamaihd.net/steamcommunity/public/images/avatars/fe/fef49e7fa7e1997310d705b2a6158ff8dc1cdfeb_full.jpg';
    
    final totalGames = friend['total_games'] as int;
    final wins = friend['wins'] as int;
    final losses = friend['losses'] as int;
    final winRate = friend['win_rate'] as double;
    final avgKda = friend['avg_kda'] as double;
    final lastPlayed = friend['last_played'] as int;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundImage: NetworkImage(avatarUrl),
          onBackgroundImageError: (exception, stackTrace) {
            print('❌ Failed to load friend avatar: $avatarUrl');
          },
          child: Container(),
        ),
        title: Text(
          friendName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Совместных игр: $totalGames • Винрейт: ${winRate.toStringAsFixed(1)}%',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Совместных игр',
                        totalGames.toString(),
                        Colors.blue,
                        Icons.gamepad,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatCard(
                        'Винрейт',
                        '${winRate.toStringAsFixed(1)}%',
                        winRate >= 50 ? Colors.green : Colors.orange,
                        Icons.percent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Средний KDA',
                        avgKda.toStringAsFixed(2),
                        Colors.purple,
                        Icons.trending_up,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatCard(
                        'Последняя игра',
                        _formatLastPlayed(lastPlayed),
                        Colors.cyan,
                        Icons.access_time,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Победы',
                        wins.toString(),
                        Colors.green,
                        Icons.check_circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatCard(
                        'Поражения',
                        losses.toString(),
                        Colors.red,
                        Icons.cancel,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _formatLastPlayed(int timestamp) {
    if (timestamp == 0) return 'Неизвестно';
    
    final lastPlayed = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    final difference = now.difference(lastPlayed);
    
    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()} г. назад';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} мес. назад';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} дн. назад';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ч. назад';
    } else {
      return 'Недавно';
    }
  }

  String _getSortDescription() {
    if (_friendsProvider?.currentSortType == SortType.games) {
      return _friendsProvider?.currentSortDirection == SortDirection.ascending ? 'По возрастанию количества игр' : 'По убыванию количества игр';
    } else if (_friendsProvider?.currentSortType == SortType.winRate) {
      return _friendsProvider?.currentSortDirection == SortDirection.ascending ? 'По возрастанию винрейта' : 'По убыванию винрейта';
    }
    return 'Неизвестная сортировка';
  }
} 