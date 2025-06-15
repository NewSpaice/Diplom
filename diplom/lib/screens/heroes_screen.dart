import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../services/steam_service.dart';
import '../services/cache_manager.dart';
import '../providers/steam_api_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/heroes_provider.dart';

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
  HeroesProvider? _heroesProvider;
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _initializeHeroes();
  }

  Future<void> _initializeHeroes() async {
    try {
      final apiProvider = context.read<SteamApiProvider>();
      final apiKey = apiProvider.apiKey;
      
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('API ключ не установлен');
      }
      
      final prefs = await SharedPreferences.getInstance();
      final cacheManager = CacheManager(prefs);
      final steamService = SteamService(apiKey, prefs);
      
      _heroesProvider = HeroesProvider(
        steamId: widget.steamId,
        cacheManager: cacheManager,
        steamService: steamService,
      );
      
      // Добавляем слушатель для обновления UI
      _heroesProvider!.addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
      
      await _heroesProvider!.initialize();
      
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
            content: Text('Ошибка инициализации героев: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _heroesProvider?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Статистика по героям'),
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
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              setState(() {
                _showFilters = !_showFilters;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _heroesProvider?.forceRefresh(),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading || (_heroesProvider?.isLoading ?? false)
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Загружаем статистику героев...'),
                ],
              ),
            )
          : (_heroesProvider?.errorMessage != null)
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
                          _heroesProvider!.errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _heroesProvider?.forceRefresh(),
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                )
              : (_heroesProvider?.heroes.isEmpty ?? true)
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.casino_outlined,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Нет статистики по героям',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Возможно, профиль приватный или игрок не играл в Dota 2',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey,
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
                                'Сыграно на ${_heroesProvider!.allHeroes.length} героях',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_heroesProvider!.allHeroes.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Всего игр: ${_heroesProvider!.getStats()['total_games']}',
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
                            itemCount: _heroesProvider!.heroes.length,
                            itemBuilder: (context, index) {
                              final heroStats = _heroesProvider!.heroes[index];
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
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _heroesProvider?.sort(HeroSortType.games),
                  icon: const Icon(Icons.gamepad, size: 16),
                  label: const Text('По играм'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _heroesProvider?.currentSortType == HeroSortType.games ? Colors.blue : null,
                    foregroundColor: _heroesProvider?.currentSortType == HeroSortType.games ? Colors.white : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _heroesProvider?.sort(HeroSortType.winRate),
                  icon: const Icon(Icons.percent, size: 16),
                  label: const Text('По винрейту'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _heroesProvider?.currentSortType == HeroSortType.winRate ? Colors.green : null,
                    foregroundColor: _heroesProvider?.currentSortType == HeroSortType.winRate ? Colors.white : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _heroesProvider?.sort(HeroSortType.alphabetical),
                  icon: const Icon(Icons.sort_by_alpha, size: 16),
                  label: const Text('По алфавиту'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _heroesProvider?.currentSortType == HeroSortType.alphabetical ? Colors.purple : null,
                    foregroundColor: _heroesProvider?.currentSortType == HeroSortType.alphabetical ? Colors.white : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _heroesProvider?.resetSorting(),
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Сброс'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[300],
                  ),
                ),
              ),
            ],
          ),
        ],
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