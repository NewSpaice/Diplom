import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/cache_manager.dart';
import '../services/database_helper.dart';
import '../services/steam_service.dart';
import 'matches_provider.dart';
import 'profile_provider.dart';
import 'friends_provider.dart';
import 'heroes_provider.dart';
import 'steam_api_provider.dart';

class AppStateProvider extends ChangeNotifier {
  final String steamId;
  final SteamApiProvider _apiProvider;
  
  // Сервисы
  CacheManager? _cacheManager;
  DatabaseHelper? _databaseHelper;
  SteamService? _steamService;
  
  // Provider'ы
  MatchesProvider? _matchesProvider;
  ProfileProvider? _profileProvider;
  FriendsProvider? _friendsProvider;
  HeroesProvider? _heroesProvider;
  
  // Состояние инициализации
  bool _isInitialized = false;
  bool _isInitializing = false;
  String? _initializationError;
  
  // Фоновое обновление
  bool _backgroundRefreshEnabled = true;
  DateTime? _lastBackgroundRefresh;
  
  // Геттеры
  bool get isInitialized => _isInitialized;
  bool get isInitializing => _isInitializing;
  String? get initializationError => _initializationError;
  
  MatchesProvider? get matchesProvider => _matchesProvider;
  ProfileProvider? get profileProvider => _profileProvider;
  FriendsProvider? get friendsProvider => _friendsProvider;
  HeroesProvider? get heroesProvider => _heroesProvider;
  
  bool get backgroundRefreshEnabled => _backgroundRefreshEnabled;
  DateTime? get lastBackgroundRefresh => _lastBackgroundRefresh;
  
  // Геттеры для сервисов
  CacheManager? get cacheManager => _cacheManager;
  DatabaseHelper? get databaseHelper => _databaseHelper;
  SteamService? get steamService => _steamService;
  
  AppStateProvider({
    required this.steamId,
    required SteamApiProvider apiProvider,
  }) : _apiProvider = apiProvider;
  
  // Инициализация всех сервисов и провайдеров
  Future<void> initialize() async {
    if (_isInitializing || _isInitialized) return;
    
    _isInitializing = true;
    _initializationError = null;
    notifyListeners();
    
    try {
      print('🚀 Initializing AppStateProvider for user $steamId');
      
      // 1. Инициализируем базовые сервисы
      await _initializeServices();
      
      // 2. Инициализируем провайдеры
      await _initializeProviders();
      
      // 3. Запускаем фоновые процессы
      _startBackgroundProcesses();
      
      _isInitialized = true;
      print('✅ AppStateProvider initialized successfully');
      
    } catch (e) {
      print('❌ Error initializing AppStateProvider: $e');
      _initializationError = e.toString();
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }
  
  // Инициализация базовых сервисов
  Future<void> _initializeServices() async {
    final prefs = await SharedPreferences.getInstance();
    
    _cacheManager = CacheManager(prefs);
    _databaseHelper = DatabaseHelper();
    
    final apiKey = _apiProvider.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('API ключ не установлен');
    }
    
    _steamService = SteamService(apiKey, prefs);
    
    print('✅ Services initialized');
  }
  
  // Инициализация провайдеров
  Future<void> _initializeProviders() async {
    if (_cacheManager == null || _databaseHelper == null || _steamService == null) {
      throw Exception('Services not initialized');
    }
    
    // Создаем провайдеры
    _matchesProvider = MatchesProvider(
      steamId: steamId,
      cacheManager: _cacheManager!,
      databaseHelper: _databaseHelper!,
      steamService: _steamService!,
    );
    
    _profileProvider = ProfileProvider(
      steamId: steamId,
      cacheManager: _cacheManager!,
      steamService: _steamService!,
    );
    
    _friendsProvider = FriendsProvider(
      steamId: steamId,
      cacheManager: _cacheManager!,
      steamService: _steamService!,
    );
    
    _heroesProvider = HeroesProvider(
      steamId: steamId,
      cacheManager: _cacheManager!,
      steamService: _steamService!,
    );
    
    // Инициализируем их параллельно
    await Future.wait([
      _profileProvider!.initialize(),
      _matchesProvider!.initialize(),
      _heroesProvider!.initialize(),
      _friendsProvider!.initialize(),
    ]);
    
    print('✅ Providers initialized');
  }
  
  // Запуск фоновых процессов
  void _startBackgroundProcesses() {
    if (!_backgroundRefreshEnabled) return;
    
    // Запускаем периодическое обновление каждые 5 минут
    Future.delayed(const Duration(minutes: 5), () {
      if (_isInitialized && _backgroundRefreshEnabled) {
        _performBackgroundRefresh();
        _startBackgroundProcesses(); // Рекурсивно перезапускаем
      }
    });
  }
  
  // Выполнение фонового обновления
  Future<void> _performBackgroundRefresh() async {
    try {
      print('🔄 Starting background refresh...');
      
      final futures = <Future<void>>[];
      
      // Проверяем каждый провайдер на необходимость обновления
      if (_profileProvider != null && _profileProvider!.needsRefresh()) {
        futures.add(_profileProvider!.backgroundRefresh());
      }
      
      if (_heroesProvider != null) {
        futures.add(_heroesProvider!.backgroundRefresh());
      }
      
      if (_friendsProvider != null) {
        futures.add(_friendsProvider!.backgroundRefresh());
      }
      
      // Матчи обновляются реже (только если есть новые)
      // if (_matchesProvider != null) {
      //   futures.add(_matchesProvider!.backgroundRefresh());
      // }
      
      await Future.wait(futures);
      
      _lastBackgroundRefresh = DateTime.now();
      
      print('✅ Background refresh completed');
      notifyListeners();
      
    } catch (e) {
      print('❌ Background refresh failed: $e');
    }
  }
  
  // Принудительное обновление всех данных
  Future<void> forceRefreshAll() async {
    if (!_isInitialized) return;
    
    try {
      print('🔄 Force refreshing all data...');
      
      await Future.wait([
        if (_profileProvider != null) _profileProvider!.forceRefresh(),
        if (_matchesProvider != null) _matchesProvider!.forceRefresh(),
        if (_heroesProvider != null) _heroesProvider!.forceRefresh(),
        if (_friendsProvider != null) _friendsProvider!.forceRefresh(),
      ]);
      
      print('✅ Force refresh completed');
      
    } catch (e) {
      print('❌ Force refresh failed: $e');
    }
  }
  
  // Управление фоновым обновлением
  void setBackgroundRefreshEnabled(bool enabled) {
    _backgroundRefreshEnabled = enabled;
    
    if (enabled && _isInitialized) {
      _startBackgroundProcesses();
    }
    
    notifyListeners();
  }
  
  // Получение общей статистики кэша
  Future<Map<String, dynamic>> getCacheStats() async {
    if (_cacheManager == null) return {};
    
    return await _cacheManager!.getCacheStats();
  }
  
  // Получение статистики базы данных
  Future<Map<String, dynamic>> getDatabaseStats() async {
    if (_databaseHelper == null) return {};
    
    return await _databaseHelper!.getDatabaseStats(steamId);
  }
  
  // Очистка всего кэша
  Future<void> clearAllCache() async {
    if (_cacheManager == null) return;
    
    await _cacheManager!.clearAllCache();
    
    // Переинициализируем провайдеры
    if (_isInitialized) {
      await _initializeProviders();
    }
  }
  
  // Очистка базы данных
  Future<void> clearDatabase() async {
    if (_databaseHelper == null) return;
    
    await _databaseHelper!.cleanOldMatches(steamId, olderThan: const Duration(days: 0));
    
    // Переинициализируем провайдер матчей
    if (_matchesProvider != null) {
      await _matchesProvider!.forceRefresh();
    }
  }
  
  // Получение общего состояния загрузки
  bool get isAnyLoading {
    return (_profileProvider?.isLoading ?? false) ||
           (_matchesProvider?.isLoading ?? false) ||
           (_heroesProvider?.isLoading ?? false) ||
           (_friendsProvider?.isLoading ?? false);
  }
  
  // Получение общего состояния ошибок
  List<String> get allErrors {
    final errors = <String>[];
    
    if (_profileProvider?.errorMessage != null) {
      errors.add('Профиль: ${_profileProvider!.errorMessage}');
    }
    if (_matchesProvider?.errorMessage != null) {
      errors.add('Матчи: ${_matchesProvider!.errorMessage}');
    }
    if (_heroesProvider?.errorMessage != null) {
      errors.add('Герои: ${_heroesProvider!.errorMessage}');
    }
    if (_friendsProvider?.errorMessage != null) {
      errors.add('Друзья: ${_friendsProvider!.errorMessage}');
    }
    
    return errors;
  }
  
  // Получение времени последнего обновления
  String getLastRefreshFormatted() {
    if (_lastBackgroundRefresh == null) return 'Никогда';
    
    final now = DateTime.now();
    final difference = now.difference(_lastBackgroundRefresh!);
    
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
  
  @override
  void dispose() {
    _databaseHelper?.close();
    super.dispose();
  }
} 