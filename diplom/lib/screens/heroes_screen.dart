import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../services/steam_service.dart';
import '../providers/steam_api_provider.dart';
import '../providers/theme_provider.dart';

enum SortType {
  games,
  winRate,
  alphabetical,
}

enum SortDirection {
  ascending,
  descending,
}

class HeroesScreen extends StatefulWidget {
  final String steamId;

  const HeroesScreen({super.key, required this.steamId});

  @override
  State<HeroesScreen> createState() => _HeroesScreenState();
}

class _HeroesScreenState extends State<HeroesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _playerHeroes = [];
  List<Map<String, dynamic>> _filteredHeroes = [];
  String? _errorMessage;
  SteamService? _steamService;
  
  // Фильтры
  SortType _currentSortType = SortType.games;
  SortDirection _currentSortDirection = SortDirection.descending;
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _loadPlayerHeroes();
  }

  Future<void> _loadPlayerHeroes() async {
    try {
      print('🦸 Loading player heroes stats...');
      
      final apiProvider = context.read<SteamApiProvider>();
      if (apiProvider.apiKey == null) {
        throw Exception('API ключ не установлен');
      }
      
      final prefs = await SharedPreferences.getInstance();
      _steamService = SteamService(apiProvider.apiKey!, prefs);
      
      final playerHeroes = await _steamService!.getPlayerHeroes(widget.steamId);
      print('📊 Player heroes data received: ${playerHeroes.length} heroes');
      
      setState(() {
        _playerHeroes = playerHeroes;
        _filteredHeroes = List.from(playerHeroes);
        _isLoading = false;
        _errorMessage = null;
      });
      
      _applySorting();
      print('✅ Successfully loaded player heroes stats');
      
    } catch (e) {
      print('❌ Error loading player heroes: $e');
      setState(() {
        _playerHeroes = [];
        _filteredHeroes = [];
        _isLoading = false;
        _errorMessage = e.toString();
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки статистики героев: $e'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Повторить',
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
                _loadPlayerHeroes();
              },
            ),
          ),
        );
      }
    }
  }

  void _applySorting() {
    setState(() {
      _filteredHeroes = List.from(_playerHeroes);
      
      switch (_currentSortType) {
        case SortType.games:
          _filteredHeroes.sort((a, b) {
            final compare = (a['games'] as int).compareTo(b['games'] as int);
            return _currentSortDirection == SortDirection.descending ? -compare : compare;
          });
          break;
          
        case SortType.winRate:
          _filteredHeroes.sort((a, b) {
            final compare = (a['win_rate'] as double).compareTo(b['win_rate'] as double);
            return _currentSortDirection == SortDirection.descending ? -compare : compare;
          });
          break;
          
        case SortType.alphabetical:
          _filteredHeroes.sort((a, b) {
            final compare = (a['hero_name'] as String).compareTo(b['hero_name'] as String);
            return _currentSortDirection == SortDirection.descending ? -compare : compare;
          });
          break;
      }
    });
  }

  void _changeSortType(SortType newType) {
    setState(() {
      if (_currentSortType == newType) {
        // Если тот же тип сортировки, меняем направление
        _currentSortDirection = _currentSortDirection == SortDirection.descending 
            ? SortDirection.ascending 
            : SortDirection.descending;
      } else {
        // Новый тип сортировки
        _currentSortType = newType;
        // Устанавливаем логичное направление по умолчанию
        switch (newType) {
          case SortType.games:
          case SortType.winRate:
            _currentSortDirection = SortDirection.descending;
            break;
          case SortType.alphabetical:
            _currentSortDirection = SortDirection.ascending;
            break;
        }
      }
    });
    _applySorting();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Статистика по героям'),
        actions: [
          IconButton(
            icon: Icon(_showFilters ? Icons.filter_list_off : Icons.filter_list),
            onPressed: () {
              setState(() {
                _showFilters = !_showFilters;
              });
            },
            tooltip: _showFilters ? 'Скрыть фильтры' : 'Показать фильтры',
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
          ? const Center(child: CircularProgressIndicator())
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
                          });
                          _loadPlayerHeroes();
                        },
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                )
              : _playerHeroes.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.casino_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Нет статистики по героям',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Возможно, профиль приватный или игрок не играл в Dota 2',
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
                        // Заголовок с общей статистикой
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16.0),
                          color: Theme.of(context).cardColor,
                          child: Column(
                            children: [
                              Text(
                                'Сыграно на ${_playerHeroes.length} героях',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_playerHeroes.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Всего игр: ${_playerHeroes.fold<int>(0, (sum, hero) => sum + (hero['games'] as int))}',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        
                        // Панель фильтров
                        if (_showFilters) _buildFiltersPanel(),
                        
                        // Список героев
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(8.0),
                            itemCount: _filteredHeroes.length,
                            itemBuilder: (context, index) {
                              final heroStats = _filteredHeroes[index];
                              return _buildHeroCard(heroStats);
                            },
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildFiltersPanel() {
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
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              _buildSortChip(
                'По играм',
                SortType.games,
                Icons.gamepad,
              ),
              _buildSortChip(
                'По винрейту',
                SortType.winRate,
                Icons.percent,
              ),
              _buildSortChip(
                'По алфавиту',
                SortType.alphabetical,
                Icons.sort_by_alpha,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSortChip(String label, SortType sortType, IconData icon) {
    final isSelected = _currentSortType == sortType;
    final isDescending = _currentSortDirection == SortDirection.descending;
    
    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: isSelected ? Colors.white : Colors.grey[600],
          ),
          const SizedBox(width: 4),
          Text(label),
          if (isSelected) ...[
            const SizedBox(width: 4),
            Icon(
              isDescending ? Icons.arrow_downward : Icons.arrow_upward,
              size: 16,
              color: Colors.white,
            ),
          ],
        ],
      ),
      onSelected: (_) => _changeSortType(sortType),
      selectedColor: Theme.of(context).primaryColor,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildHeroCard(Map<String, dynamic> heroStats) {
    final heroName = heroStats['hero_name'] ?? 'Неизвестный герой';
    final games = heroStats['games'] as int;
    final wins = heroStats['wins'] as int;
    final losses = heroStats['losses'] as int;
    final winRate = heroStats['win_rate'] as double;
    final lastPlayed = heroStats['last_played'] as int;
    
    // Формируем URL для изображения героя
    String imageUrl = 'https://cdn.dota2.com/apps/dota2/images/heroes/default_hero.png';
    if (heroStats['hero_internal_name'] != null && heroStats['hero_internal_name'].isNotEmpty) {
      final heroImageName = (heroStats['hero_internal_name'] as String).replaceAll('npc_dota_hero_', '');
      imageUrl = 'https://cdn.dota2.com/apps/dota2/images/heroes/${heroImageName}_full.png';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundImage: NetworkImage(imageUrl),
          onBackgroundImageError: (exception, stackTrace) {
            print('❌ Failed to load hero image: $imageUrl');
          },
          child: Container(),
        ),
        title: Text(
          heroName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Игр: $games • Винрейт: ${winRate.toStringAsFixed(1)}%',
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Винрейт',
                        '${winRate.toStringAsFixed(1)}%',
                        winRate >= 50 ? Colors.green : Colors.orange,
                        Icons.percent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatCard(
                        'Последняя игра',
                        _formatLastPlayed(lastPlayed),
                        Colors.blue,
                        Icons.access_time,
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
} 