import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/cache_manager.dart';
import '../services/steam_service.dart';

class ProfileProvider extends ChangeNotifier {
  final String steamId;
  final CacheManager _cacheManager;
  final SteamService _steamService;
  
  Map<String, dynamic>? _profileData;
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _errorMessage;
  DateTime? _lastUpdated;
  
  // Геттеры
  Map<String, dynamic>? get profileData => _profileData;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdated => _lastUpdated;
  bool get hasData => _profileData != null;
  
  // Получение статистики из данных профиля
  Map<String, dynamic>? get statsData => _profileData?['stats'];
  
  // Получение URL изображения ранга
  String getRankImageUrl(int rankTier) {
    if (rankTier == 0) return 'ranks/rank_icon_0.png'; // Без ранга
    if (rankTier >= 80) return 'ranks/rank_icon_${rankTier}.webp'; // Immortal (webp)
    if (rankTier == 11) return 'ranks/rank-icon-11.png'; // Специальный случай
    if (rankTier == 12) return 'ranks/rank_icon_12.png'; // PNG формат
    return 'ranks/rank_icon_${rankTier}.webp'; // Остальные в webp
  }
  
  ProfileProvider({
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
      final needsRefresh = await _cacheManager.needsRefresh('profile_$steamId');
      
      if (needsRefresh || _profileData == null) {
        // 3. Загружаем новые данные в фоне
        await _loadFromAPI(isBackground: _profileData != null);
      }
      
    } catch (e) {
      print('❌ Error initializing profile: $e');
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Загрузка из кэша
  Future<void> _loadFromCache() async {
    try {
      final cachedData = await _cacheManager.getData('profile_$steamId');
      
      if (cachedData != null) {
        _profileData = cachedData;
        _lastUpdated = DateTime.fromMillisecondsSinceEpoch(
          cachedData['cached_at'] ?? DateTime.now().millisecondsSinceEpoch,
        );
        
        print('📱 Loaded profile from cache');
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
      
      // Загружаем базовые данные профиля
      final basicProfile = await _steamService.getPlayerProfile(steamId);
      
      if (basicProfile != null) {
        // Инициализируем объект данных профиля
        final profileData = Map<String, dynamic>.from(basicProfile);
        
        // Загружаем статистику отдельно, чтобы при ошибке основной профиль все равно показался
        Map<String, dynamic>? statsData;
        try {
          statsData = await _steamService.getPlayerStats(steamId);
          print('📊 Player stats loaded: $statsData');
        } catch (e) {
          print('⚠️ Could not load player stats: $e');
          // Статистика не загрузилась, но это не критично
        }
        
        // Добавляем статистику к данным профиля
        if (statsData != null) {
          profileData['stats'] = statsData;
        }
        
        // Добавляем timestamp
        profileData['cached_at'] = DateTime.now().millisecondsSinceEpoch;
        
        // Сохраняем в кэш
        await _cacheManager.saveData('profile_$steamId', profileData);
        
        _profileData = profileData;
        _lastUpdated = DateTime.now();
        _errorMessage = null;
        
        print('🌐 Loaded profile from API');
      } else {
        throw Exception('Профиль не найден');
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
  
  // Принудительное обновление
  Future<void> forceRefresh() async {
    await _cacheManager.clearCache('profile_$steamId');
    _profileData = null;
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
  
  // Проверка нужды в обновлении
  bool needsRefresh() {
    if (_lastUpdated == null) return true;
    
    final now = DateTime.now();
    final difference = now.difference(_lastUpdated!);
    
    return difference.inMinutes > 30; // Обновляем каждые 30 минут
  }
} 