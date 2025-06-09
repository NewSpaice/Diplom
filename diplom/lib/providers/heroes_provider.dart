import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/cache_manager.dart';
import '../services/steam_service.dart';

enum HeroSortType {
  games,
  winRate,
  alphabetical,
  lastPlayed,
}

enum SortDirection {
  ascending,
  descending,
}

class HeroesProvider extends ChangeNotifier {
  final String steamId;
  final CacheManager _cacheManager;
  final SteamService _steamService;
  
  List<Map<String, dynamic>> _heroes = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _errorMessage;
  DateTime? _lastUpdated;
  
  // Фильтрация и сортировка
  HeroSortType _currentSortType = HeroSortType.games;
  SortDirection _currentSortDirection = SortDirection.descending;
  String _searchQuery = '';
  
  // Геттеры
  List<Map<String, dynamic>> get heroes => _getFilteredAndSortedHeroes();
  List<Map<String, dynamic>> get allHeroes => _heroes;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdated => _lastUpdated;
  bool get hasData => _heroes.isNotEmpty;
  HeroSortType get currentSortType => _currentSortType;
  SortDirection get currentSortDirection => _currentSortDirection;
  String get searchQuery => _searchQuery;
  
  HeroesProvider({
    required this.steamId,
    required CacheManager cacheManager,
    required SteamService steamService,
  }) : _cacheManager = cacheManager,
       _steamService = steamService;
  
  // Инициализация - загружаем кэш, потом обновляем в фоне
  Future<void> initialize() async {
    if (_isLoading) return;
    
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      // 1. Сначала загружаем из кэша
      await _loadFromCache();
      
      // 2. Проверяем нужно ли обновление
      final needsRefresh = await _cacheManager.needsRefresh('heroes_$steamId');
      
      if (needsRefresh || _heroes.isEmpty) {
        // 3. Загружаем новые данные в фоне
        await _loadFromAPI(isBackground: _heroes.isNotEmpty);
      }
      
    } catch (e) {
      print('❌ Error initializing heroes: $e');
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Загрузка из кэша
  Future<void> _loadFromCache() async {
    try {
      final cachedData = await _cacheManager.getHeroesData();
      
      if (cachedData != null && cachedData.isNotEmpty) {
        _heroes = cachedData;
        _lastUpdated = DateTime.fromMillisecondsSinceEpoch(
          cachedData.first['cached_at'] ?? DateTime.now().millisecondsSinceEpoch,
        );
        
        print('📱 Loaded ${cachedData.length} heroes from cache');
        notifyListeners();
      }
    } catch (e) {
      print('❌ Error loading from cache: $e');
    }
  }
  
  // Загрузка из API
  Future<void> _loadFromAPI({bool isBackground = false}) async {
    try {
      if (isBackground) {
        _isRefreshing = true;
      } else {
        _isLoading = true;
      }
      notifyListeners();
      
      // Загружаем героев игрока
      final heroesData = await _steamService.getPlayerHeroes(steamId);
      
      if (heroesData != null && heroesData.isNotEmpty) {
        // Добавляем timestamp к каждому герою
        for (final hero in heroesData) {
          hero['cached_at'] = DateTime.now().millisecondsSinceEpoch;
        }
        
        _heroes = heroesData;
        
        // Сохраняем в кэш
        await _cacheManager.saveHeroesData(_heroes);
        
        _lastUpdated = DateTime.now();
        _errorMessage = null;
        
        print('🌐 Loaded ${_heroes.length} heroes from API');
      } else {
        throw Exception('Не удалось загрузить героев');
      }
      
    } catch (e) {
      print('❌ Error loading from API: $e');
      if (!isBackground) {
        _errorMessage = e.toString();
      }
    } finally {
      _isLoading = false;
      _isRefreshing = false;
      notifyListeners();
    }
  }
  
  // Получение отфильтрованного и отсортированного списка героев
  List<Map<String, dynamic>> _getFilteredAndSortedHeroes() {
    var filteredHeroes = _heroes;
    
    // Применяем поиск
    if (_searchQuery.isNotEmpty) {
      filteredHeroes = _heroes.where((hero) {
        final heroName = (hero['localized_name'] ?? '').toString().toLowerCase();
        return heroName.contains(_searchQuery.toLowerCase());
      }).toList();
    }
    
    // Применяем сортировку
    filteredHeroes.sort((a, b) => _compareHeroes(a, b, _currentSortType));
    
    return filteredHeroes;
  }
  
  // Сравнение героев для сортировки
  int _compareHeroes(Map<String, dynamic> a, Map<String, dynamic> b, HeroSortType type) {
    int comparison = 0;
    
    switch (type) {
      case HeroSortType.games:
        comparison = (a['games'] ?? 0).compareTo(b['games'] ?? 0);
        break;
      case HeroSortType.winRate:
        final winRateA = a['win_rate'] ?? 0.0;
        final winRateB = b['win_rate'] ?? 0.0;
        comparison = winRateA.compareTo(winRateB);
        break;
      case HeroSortType.alphabetical:
        final nameA = a['localized_name'] ?? '';
        final nameB = b['localized_name'] ?? '';
        comparison = nameA.compareTo(nameB);
        break;
      case HeroSortType.lastPlayed:
        final lastPlayedA = a['last_played'] ?? 0;
        final lastPlayedB = b['last_played'] ?? 0;
        comparison = lastPlayedA.compareTo(lastPlayedB);
        break;
    }
    
    // Применяем направление сортировки
    if (_currentSortDirection == SortDirection.descending) {
      return -comparison;
    }
    return comparison;
  }
  
  // Изменение сортировки
  void setSorting(HeroSortType type, SortDirection direction) {
    _currentSortType = type;
    _currentSortDirection = direction;
    notifyListeners();
  }
  
  // Переключение направления сортировки
  void toggleSortDirection() {
    _currentSortDirection = _currentSortDirection == SortDirection.descending
        ? SortDirection.ascending
        : SortDirection.descending;
    notifyListeners();
  }
  
  // Изменение поискового запроса
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }
  
  // Очистка поиска
  void clearSearch() {
    _searchQuery = '';
    notifyListeners();
  }
  
  // Получение описания сортировки
  String getSortDescription() {
    final direction = _currentSortDirection == SortDirection.descending ? 'убыв.' : 'возр.';
    
    switch (_currentSortType) {
      case HeroSortType.games:
        return 'По играм ($direction)';
      case HeroSortType.winRate:
        return 'По винрейту ($direction)';
      case HeroSortType.alphabetical:
        return 'По алфавиту ($direction)';
      case HeroSortType.lastPlayed:
        return 'По дате ($direction)';
    }
  }
  
  // Получение топ героев
  List<Map<String, dynamic>> getTopHeroes({int limit = 5}) {
    final sortedByGames = List<Map<String, dynamic>>.from(_heroes);
    sortedByGames.sort((a, b) => (b['games'] ?? 0).compareTo(a['games'] ?? 0));
    
    return sortedByGames.take(limit).toList();
  }
  
  // Получение статистики
  Map<String, dynamic> getStats() {
    if (_heroes.isEmpty) {
      return {
        'total_heroes': 0,
        'total_games': 0,
        'average_win_rate': 0.0,
        'most_played_hero': null,
      };
    }
    
    final totalGames = _heroes.fold<int>(0, (sum, hero) => sum + ((hero['games'] ?? 0) as int));
    final totalWins = _heroes.fold<int>(0, (sum, hero) => sum + ((hero['wins'] ?? 0) as int));
    final averageWinRate = totalGames > 0 ? (totalWins / totalGames * 100) : 0.0;
    
    final mostPlayedHero = _heroes.reduce((a, b) => 
        (a['games'] ?? 0) > (b['games'] ?? 0) ? a : b);
    
    return {
      'total_heroes': _heroes.length,
      'total_games': totalGames,
      'average_win_rate': averageWinRate,
      'most_played_hero': mostPlayedHero,
    };
  }
  
  // Принудительное обновление
  Future<void> forceRefresh() async {
    await _cacheManager.clearCache('heroes_$steamId');
    _heroes.clear();
    _lastUpdated = null;
    await initialize();
  }
  
  // Фоновое обновление
  Future<void> backgroundRefresh() async {
    if (_isLoading || _isRefreshing) return;
    
    try {
      await _loadFromAPI(isBackground: true);
    } catch (e) {
      print('❌ Background refresh failed: $e');
    }
  }
  
  // Получение времени последнего обновления в читаемом формате
  String getLastUpdatedFormatted() {
    if (_lastUpdated == null) return 'Никогда';
    
    final now = DateTime.now();
    final difference = now.difference(_lastUpdated!);
    
    if (difference.inMinutes < 1) {
      return 'Только что';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} мин назад';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} ч назад';
    } else {
      return '${difference.inDays} дн назад';
    }
  }
} 