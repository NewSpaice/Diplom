import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/cache_manager.dart';
import '../services/steam_service.dart';

enum SortType {
  games,
  winRate,
}

enum SortDirection {
  ascending,
  descending,
}

class FriendsProvider extends ChangeNotifier {
  final String steamId;
  final CacheManager _cacheManager;
  final SteamService _steamService;
  
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _friendsWithGames = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _errorMessage;
  DateTime? _lastUpdated;
  
  // Сортировка
  SortType? _currentSortType = SortType.games;
  SortDirection _currentSortDirection = SortDirection.descending;
  
  // Геттеры
  List<Map<String, dynamic>> get friends => _friendsWithGames;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdated => _lastUpdated;
  bool get hasData => _friendsWithGames.isNotEmpty;
  SortType? get currentSortType => _currentSortType;
  SortDirection get currentSortDirection => _currentSortDirection;
  
  FriendsProvider({
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
      final needsRefresh = await _cacheManager.needsRefresh('friends_$steamId');
      
      if (needsRefresh || _friendsWithGames.isEmpty) {
        // 3. Загружаем новые данные в фоне
        await _loadFromAPI(isBackground: _friendsWithGames.isNotEmpty);
      }
      
      // 4. Применяем сортировку
      _applySorting();
      
    } catch (e) {
      print('❌ Error initializing friends: $e');
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Загрузка из кэша
  Future<void> _loadFromCache() async {
    try {
      // Используем правильный ключ кэша с steamId
      final cachedData = await _cacheManager.getData('friends_$steamId');
      
      if (cachedData != null && cachedData['friends'] != null) {
        final friendsList = List<Map<String, dynamic>>.from(cachedData['friends']);
        if (friendsList.isNotEmpty) {
          _friendsWithGames = friendsList;
          _lastUpdated = DateTime.fromMillisecondsSinceEpoch(
            cachedData['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
          );
          
          print('📱 Loaded ${friendsList.length} friends from cache');
          notifyListeners();
        }
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
      
      // Загружаем список друзей
      final friendsData = await _steamService.getFriendsList(steamId);
      
      if (friendsData != null && friendsData['friendslist'] != null) {
        _friends = List<Map<String, dynamic>>.from(friendsData['friendslist']['friends'] ?? []);
        print('📈 Loading stats for ${_friends.length} friends...');
        
        _friendsWithGames.clear();
        
        // Загружаем статистику для каждого друга
        for (int i = 0; i < _friends.length; i++) {
          final friend = _friends[i];
          final friendSteamId = friend['steamid'];
          
          if (friendSteamId != null) {
            try {
              final stats = await _steamService.getFriendStats(steamId, friendSteamId);
              
              // Добавляем друга только если есть совместные игры в Dota 2
              if ((stats['total_games'] as int) > 0) {
                final friendWithStats = Map<String, dynamic>.from(friend);
                friendWithStats.addAll(stats);
                friendWithStats['cached_at'] = DateTime.now().millisecondsSinceEpoch;
                _friendsWithGames.add(friendWithStats);
              }
              
              // Обновляем UI периодически
              if (i % 3 == 0) {
                notifyListeners();
              }
              
              // Увеличенная задержка между запросами для избежания rate limit
              if (i < _friends.length - 1) {
                await Future.delayed(const Duration(milliseconds: 3000));
              }
              
            } catch (e) {
              print('❌ Error loading stats for friend $friendSteamId: $e');
              // Если это rate limit, делаем дополнительную паузу
              if (e.toString().contains('429')) {
                print('🕐 Rate limit detected, waiting 15 seconds...');
                await Future.delayed(const Duration(seconds: 15));
              }
            }
          }
        }
        
        // Сохраняем в кэш
        await _cacheManager.saveData('friends_$steamId', {
          'friends': _friendsWithGames,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        
        _lastUpdated = DateTime.now();
        _errorMessage = null;
        
        print('🌐 Loaded ${_friendsWithGames.length} friends with games from API');
      } else {
        throw Exception('Не удалось загрузить список друзей');
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
  
  // Переключение сортировки
  void toggleSort(SortType type) {
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
    
    _applySorting();
    notifyListeners();
  }
  
  // Применение сортировки
  void _applySorting() {
    if (_currentSortType == null) return;
    
    _friendsWithGames.sort((a, b) => _compareFriends(a, b, _currentSortType!));
  }
  
  // Сравнение друзей для сортировки
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
  
  // Получение описания сортировки
  String getSortDescription() {
    if (_currentSortType == null) return '';
    
    final direction = _currentSortDirection == SortDirection.descending ? 'по убыванию' : 'по возрастанию';
    final type = _currentSortType == SortType.games ? 'по играм' : 'по винрейту';
    
    return '$type $direction';
  }
  
  // Принудительное обновление
  Future<void> forceRefresh() async {
    await _cacheManager.clearCache('friends_$steamId');
    _friendsWithGames.clear();
    _lastUpdated = null;
    await initialize();
  }
  
  // Фоновое обновление
  Future<void> backgroundRefresh() async {
    if (_isLoading || _isRefreshing) return;
    
    try {
      await _loadFromAPI(isBackground: true);
      _applySorting();
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