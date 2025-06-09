import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/cache_manager.dart';
import '../services/steam_service.dart';
import '../services/database_helper.dart';

enum LoadAllMatchesState {
  notStarted,
  loading,
  completed,
  error,
}

class MatchesProvider extends ChangeNotifier {
  final String steamId;
  final CacheManager _cacheManager;
  final SteamService _steamService;
  final DatabaseHelper _databaseHelper;
  
  List<Map<String, dynamic>> _matches = [];
  List<String> _heroes = ['Все герои'];
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _errorMessage;
  DateTime? _lastUpdated;
  
  // Состояние загрузки всех матчей
  LoadAllMatchesState _loadAllState = LoadAllMatchesState.notStarted;
  int _totalMatchesToLoad = 0;
  int _loadedMatches = 0;
  String? _loadAllError;
  
  // Геттеры
  List<Map<String, dynamic>> get matches => _matches;
  List<String> get heroes => _heroes;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdated => _lastUpdated;
  bool get hasData => _matches.isNotEmpty;
  
  LoadAllMatchesState get loadAllState => _loadAllState;
  int get totalMatchesToLoad => _totalMatchesToLoad;
  int get loadedMatches => _loadedMatches;
  String? get loadAllError => _loadAllError;
  
  MatchesProvider({
    required this.steamId,
    required CacheManager cacheManager,
    required SteamService steamService,
    required DatabaseHelper databaseHelper,
  }) : _cacheManager = cacheManager,
       _steamService = steamService,
       _databaseHelper = databaseHelper;
  
  // Инициализация
  Future<void> initialize() async {
    if (_isLoading) return;
    
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      // 1. Загружаем из кэша
      await _loadFromCache();
      
      // 2. Загружаем героев
      await _loadHeroes();
      
      // 3. Проверяем нужно ли обновление
      final needsRefresh = await _cacheManager.needsRefresh('matches_$steamId');
      
      if (needsRefresh || _matches.isEmpty) {
        // 4. Загружаем новые данные в фоне
        await _loadFromAPI(isBackground: _matches.isNotEmpty);
      }
      
    } catch (e) {
      print('❌ Error initializing matches: $e');
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Загрузка из кэша
  Future<void> _loadFromCache() async {
    try {
      // Сначала пробуем кэш
      final cachedData = await _cacheManager.getData('matches_$steamId');
      if (cachedData != null && cachedData['matches'] != null) {
        final cachedMatches = List<Map<String, dynamic>>.from(cachedData['matches']);
        if (cachedMatches.isNotEmpty) {
          _matches = cachedMatches;
          _lastUpdated = DateTime.fromMillisecondsSinceEpoch(
            cachedData['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
          );
          print('📱 Loaded ${cachedMatches.length} matches from cache');
          notifyListeners();
          return;
        }
      }
      
      // Если кэш пустой, пробуем базу данных
      final dbMatches = await _databaseHelper.getMatches(steamId, limit: 50);
      if (dbMatches.isNotEmpty) {
        _matches = dbMatches;
        print('💾 Loaded ${dbMatches.length} matches from database');
        notifyListeners();
      }
    } catch (e) {
      print('❌ Error loading from cache/database: $e');
    }
  }
  
  // Загрузка героев
  Future<void> _loadHeroes() async {
    try {
      final heroesData = await _steamService.getHeroes();
      if (heroesData != null && heroesData['result'] != null && heroesData['result']['heroes'] != null) {
        final heroes = heroesData['result']['heroes'] as List;
        _heroes = ['Все герои', ...heroes.map((h) => h['localized_name'] as String).toList()];
        print('🎮 Loaded ${heroes.length} heroes');
      }
    } catch (e) {
      print('❌ Error loading heroes: $e');
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
      
      final matchesData = await _steamService.getMatchHistory(steamId);
      final heroesData = await _steamService.getHeroes();
      
      if (matchesData != null && heroesData != null) {
        final matches = List<Map<String, dynamic>>.from(matchesData['result']['matches'] ?? []);
        final heroes = heroesData['result']['heroes'] as List;
        
        // Создаем Map для быстрого поиска героев по ID
        final heroesMap = Map.fromEntries(
          heroes.map((h) => MapEntry(h['id'], h['localized_name']))
        );
        
        // Добавляем имена героев к матчам
        for (var match in matches) {
          final player = match['players'].firstWhere(
            (p) => p['account_id'].toString() == _convertToAccountId(steamId),
            orElse: () => {'hero_id': 0},
          );
          match['hero_name'] = heroesMap[player['hero_id']] ?? 'Неизвестный герой';
        }
        
        // Загружаем длительность в фоне
        _loadMatchDurations(matches);
        
        // Сохраняем в кэш и базу данных
        await _cacheManager.saveData('matches_$steamId', {
          'matches': matches,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        await _databaseHelper.saveMatches(steamId, matches);
        
        _matches = matches;
        _lastUpdated = DateTime.now();
        _errorMessage = null;
        
        print('🌐 Loaded ${matches.length} matches from API');
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
  
  // Загрузка длительности матчей
  Future<void> _loadMatchDurations(List<Map<String, dynamic>> matches) async {
    final tasks = <Future<void>>[];
    
    for (int i = 0; i < matches.length; i++) {
      final match = matches[i];
      tasks.add(_loadSingleMatchDuration(match, i * 50));
    }
    
    try {
      await Future.wait(tasks);
      print('✅ Завершена загрузка длительности для ${matches.length} матчей');
    } catch (e) {
      print('❌ Ошибка загрузки длительности матчей: $e');
    }
  }
  
  // Загрузка длительности одного матча
  Future<void> _loadSingleMatchDuration(Map<String, dynamic> match, int delayMs) async {
    try {
      await Future.delayed(Duration(milliseconds: delayMs));
      
      final matchId = match['match_id'];
      final response = await http.get(
        Uri.parse('https://api.opendota.com/api/matches/$matchId'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final matchDetails = json.decode(response.body);
        if (matchDetails['duration'] != null) {
          match['duration'] = matchDetails['duration'];
          
          // Сохраняем обновленный матч
          await _databaseHelper.saveMatches(steamId, [match]);
          await _cacheManager.saveData('matches_$steamId', {
            'matches': _matches,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
          
          notifyListeners();
        }
      }
    } catch (e) {
      print('❌ Ошибка загрузки длительности для матча ${match['match_id']}: $e');
    }
  }
  
  // Загрузка всех матчей
  Future<void> loadAllMatches() async {
    if (_loadAllState == LoadAllMatchesState.loading) return;
    
    _loadAllState = LoadAllMatchesState.loading;
    _loadedMatches = 0;
    _totalMatchesToLoad = 0;
    _loadAllError = null;
    notifyListeners();
    
    try {
      // Получаем общее количество матчей
      final firstBatch = await _steamService.getMatchHistory(steamId);
      final totalMatches = firstBatch['result']['total_results'] ?? 0;
      
      _totalMatchesToLoad = totalMatches;
      notifyListeners();
      
      print('📊 Total matches to load: $totalMatches');
      
      // Загружаем все матчи по батчам
      const int batchSize = 100;
      int startMatchId = 0;
      List<Map<String, dynamic>> allMatches = [];
      int batchNumber = 0;
      
      while (true) {
        batchNumber++;
        print('📥 Loading batch $batchNumber starting from match ID: $startMatchId');
        
        final batchData = await _steamService.getMatchHistoryBatch(
          steamId,
          startAt: startMatchId,
          limit: batchSize,
        );
        
        final matches = List<Map<String, dynamic>>.from(
          batchData['result']['matches'] ?? []
        );
        
        if (matches.isEmpty) {
          print('✅ No more matches found, stopping');
          break;
        }
        
        // Добавляем героев к матчам
        final heroesData = await _steamService.getHeroes();
        if (heroesData != null && heroesData['result'] != null) {
          final heroes = heroesData['result']['heroes'] as List;
          final heroesMap = Map.fromEntries(
            heroes.map((h) => MapEntry(h['id'], h['localized_name']))
          );
          
          for (var match in matches) {
            final player = match['players'].firstWhere(
              (p) => p['account_id'].toString() == _convertToAccountId(steamId),
              orElse: () => {'hero_id': 0},
            );
            match['hero_name'] = heroesMap[player['hero_id']] ?? 'Неизвестный герой';
          }
        }
        
        allMatches.addAll(matches);
        
        // Обновляем прогресс
        _loadedMatches = allMatches.length;
        _matches = allMatches; // Обновляем список матчей в реальном времени
        notifyListeners();
        
        print('📈 Progress: ${_loadedMatches}/$_totalMatchesToLoad matches loaded (batch $batchNumber)');
        
        // Сохраняем батч в базу данных
        await _databaseHelper.saveMatches(steamId, matches);
        
        // Получаем ID последнего матча для следующего батча
        startMatchId = matches.last['match_id'] - 1;
        
        // Задержка между запросами
        await Future.delayed(const Duration(milliseconds: 1000));
        
        // Проверяем не отменил ли пользователь загрузку
        if (_loadAllState != LoadAllMatchesState.loading) {
          break;
        }
        
        // Ограничиваем количество батчей для безопасности
        if (batchNumber >= 50) {
          print('⚠️ Reached maximum batch limit (50), stopping');
          break;
        }
      }
      
      // Обновляем кэш со всеми матчами
      await _cacheManager.saveData('matches_$steamId', {
        'matches': allMatches,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      
      _matches = allMatches;
      _loadAllState = LoadAllMatchesState.completed;
      _lastUpdated = DateTime.now();
      
      print('🎉 Successfully loaded all ${allMatches.length} matches!');
      notifyListeners();
      
    } catch (e) {
      print('❌ Error loading all matches: $e');
      _loadAllState = LoadAllMatchesState.error;
      _loadAllError = e.toString();
      notifyListeners();
    }
  }
  
  // Конвертация Steam ID в account ID
  String _convertToAccountId(String steamId) {
    try {
      final steamIdNum = BigInt.parse(steamId);
      final accountId = (steamIdNum - BigInt.from(76561197960265728)).toString();
      return accountId;
    } catch (e) {
      print('Error converting Steam ID: $e');
      return steamId;
    }
  }
  
  // Принудительное обновление
  Future<void> forceRefresh() async {
    await _cacheManager.clearCache('matches_$steamId');
    _matches.clear();
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
  
  // Получение прогресса загрузки всех матчей
  double getLoadAllProgress() {
    return _totalMatchesToLoad > 0 ? _loadedMatches / _totalMatchesToLoad : 0.0;
  }
} 