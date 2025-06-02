import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../services/steam_service.dart';
import '../providers/steam_api_provider.dart';
import '../providers/theme_provider.dart';

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
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _friendsWithGames = []; // Только друзья с играми
  Map<String, Map<String, dynamic>> _friendsStats = {};
  String? _errorMessage;
  SteamService? _steamService;

  // Сортировка
  bool _showSorting = false;
  SortType? _currentSortType;
  SortDirection _currentSortDirection = SortDirection.descending;

  @override
  void initState() {
    super.initState();
    _loadFriendsAndStats();
  }

  Future<void> _loadFriendsAndStats() async {
    try {
      print('👥 Loading friends and shared stats...');
      
      final apiProvider = context.read<SteamApiProvider>();
      if (apiProvider.apiKey == null) {
        throw Exception('API ключ не установлен');
      }
      
      final prefs = await SharedPreferences.getInstance();
      _steamService = SteamService(apiProvider.apiKey!, prefs);
      
      // Загружаем список друзей
      final friendsData = await _steamService!.getFriendsList(widget.steamId);
      print('📊 Friends data received');
      
      if (friendsData['friendslist'] != null && friendsData['friendslist']['friends'] != null) {
        final friendsList = friendsData['friendslist']['friends'] as List;
        
        // Приводим к правильному типу
        final typedFriends = friendsList.map((friend) {
          if (friend is Map<String, dynamic>) {
            return friend;
          } else if (friend is Map) {
            return Map<String, dynamic>.from(friend);
          } else {
            throw Exception('Неверный тип данных друга');
          }
        }).toList();
        
        setState(() {
          _friends = typedFriends;
        });
        
        // Загружаем статистику для каждого друга
        final friendsToProcess = _friends;
        print('📈 Loading stats for ${friendsToProcess.length} friends...');
        
        for (int i = 0; i < friendsToProcess.length; i++) {
          final friend = friendsToProcess[i];
          final friendSteamId = friend['steamid'];
          
          if (friendSteamId != null) {
            try {
              print('Loading stats for friend ${i + 1}/${friendsToProcess.length}: $friendSteamId');
              final stats = await _steamService!.getFriendStats(widget.steamId, friendSteamId);
              
              setState(() {
                _friendsStats[friendSteamId] = stats;
                
                // Добавляем друга в список только если есть совместные игры в Dota 2
                if ((stats['total_games'] as int) > 0) {
                  final friendWithStats = Map<String, dynamic>.from(friend);
                  friendWithStats.addAll(stats);
                  _friendsWithGames.add(friendWithStats);
                }
              });
              
              // Небольшая задержка между запросами
              if (i < friendsToProcess.length - 1) {
                await Future.delayed(const Duration(milliseconds: 500));
              }
            } catch (e) {
              print('❌ Error loading stats for friend $friendSteamId: $e');
              // Продолжаем с другими друзьями
            }
          }
        }
        
        // Применяем начальную сортировку
        _applySorting();
      }
      
      setState(() {
        _isLoading = false;
        _errorMessage = null;
      });
      
      print('✅ Successfully loaded friends and stats');
      
    } catch (e) {
      print('❌ Error loading friends: $e');
      setState(() {
        _friends = [];
        _friendsWithGames = [];
        _friendsStats = {};
        _isLoading = false;
        _errorMessage = e.toString();
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки друзей: $e'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Повторить',
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                  _friendsStats.clear();
                  _friendsWithGames.clear();
                });
                _loadFriendsAndStats();
              },
            ),
          ),
        );
      }
    }
  }

  void _applySorting() {
    setState(() {
      if (_currentSortType == SortType.games) {
        _friendsWithGames.sort((a, b) => _compareFriends(a, b, SortType.games));
      } else if (_currentSortType == SortType.winRate) {
        _friendsWithGames.sort((a, b) => _compareFriends(a, b, SortType.winRate));
      }
    });
  }

  int _compareFriends(Map<String, dynamic> a, Map<String, dynamic> b, SortType type) {
    int comparison = 0;
    
    if (type == SortType.games) {
      comparison = (a['total_games'] as int).compareTo(b['total_games'] as int);
    } else if (type == SortType.winRate) {
      final winRateA = a['win_rate'] as double;
      final winRateB = b['win_rate'] as double;
      comparison = winRateA.compareTo(winRateB);
    }
    
    // Применяем направление сортировки
    if (_currentSortDirection == SortDirection.descending) {
      return -comparison;
    }
    return comparison;
  }

  void _toggleSort(SortType type) {
    setState(() {
      if (_currentSortType == type) {
        // Если уже сортируем по этому типу, меняем направление
        _currentSortDirection = _currentSortDirection == SortDirection.descending 
            ? SortDirection.ascending 
            : SortDirection.descending;
      } else {
        // Если новый тип сортировки, устанавливаем по убыванию по умолчанию
        _currentSortType = type;
        _currentSortDirection = SortDirection.descending;
      }
    });
    _applySorting();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Статистика с друзьями'),
        actions: [
          IconButton(
            icon: Icon(_showSorting ? Icons.sort : Icons.sort),
            onPressed: () {
              setState(() {
                _showSorting = !_showSorting;
              });
            },
            tooltip: _showSorting ? 'Скрыть сортировку' : 'Показать сортировку',
          ),
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
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Ошибка загрузки',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.red[300],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _errorMessage = null;
                            _friendsStats.clear();
                            _friendsWithGames.clear();
                          });
                          _loadFriendsAndStats();
                        },
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                )
              : _friendsWithGames.isEmpty
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
                                'Друзей с совместными играми: ${_friendsWithGames.length}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // Панель сортировки
                        if (_showSorting && _friendsWithGames.isNotEmpty) _buildSortingPanel(),
                        
                        // Список друзей с совместной статистикой
                        Expanded(
                          child: _friendsWithGames.isEmpty
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
                                  itemCount: _friendsWithGames.length,
                                  itemBuilder: (context, index) {
                                    final friend = _friendsWithGames[index];
                                    return _buildFriendCard(friend);
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
                    _currentSortType = SortType.games;
                    _currentSortDirection = SortDirection.descending;
                  });
                  _applySorting();
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
              onPressed: () => _toggleSort(SortType.games),
              icon: Icon(
                _currentSortType == SortType.games
                    ? (_currentSortDirection == SortDirection.descending ? Icons.arrow_downward : Icons.arrow_upward)
                    : Icons.sort,
                size: 18,
                color: _currentSortType == SortType.games ? Colors.white : null,
              ),
              label: Text(
                _currentSortType == SortType.games
                    ? (_currentSortDirection == SortDirection.descending ? 'Больше → Меньше' : 'Меньше → Больше')
                    : 'Сортировать по играм',
                style: TextStyle(
                  fontSize: 14,
                  color: _currentSortType == SortType.games ? Colors.white : null,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _currentSortType == SortType.games ? Colors.blue : null,
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
              onPressed: () => _toggleSort(SortType.winRate),
              icon: Icon(
                _currentSortType == SortType.winRate
                    ? (_currentSortDirection == SortDirection.descending ? Icons.arrow_downward : Icons.arrow_upward)
                    : Icons.sort,
                size: 18,
                color: _currentSortType == SortType.winRate ? Colors.white : null,
              ),
              label: Text(
                _currentSortType == SortType.winRate
                    ? (_currentSortDirection == SortDirection.descending ? 'Высокий → Низкий' : 'Низкий → Высокий')
                    : 'Сортировать по винрейту',
                style: TextStyle(
                  fontSize: 14,
                  color: _currentSortType == SortType.winRate ? Colors.white : null,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _currentSortType == SortType.winRate ? Colors.green : null,
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
                    _currentSortType != null
                        ? 'Сортировка: ${_getSortDescription()} • Показано: ${_friendsWithGames.length} друзей'
                        : 'Показано: ${_friendsWithGames.length} друзей',
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
    if (_currentSortType == SortType.games) {
      return _currentSortDirection == SortDirection.ascending ? 'По возрастанию количества игр' : 'По убыванию количества игр';
    } else if (_currentSortType == SortType.winRate) {
      return _currentSortDirection == SortDirection.ascending ? 'По возрастанию винрейта' : 'По убыванию винрейта';
    }
    return 'Неизвестная сортировка';
  }
} 