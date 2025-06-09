import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CacheManager {
  static const String _profileKey = 'cached_profile_data';
  static const String _matchesKey = 'cached_matches_data';
  static const String _heroesKey = 'cached_heroes_data';
  static const String _friendsKey = 'cached_friends_data';
  static const String _timestampKey = 'cache_timestamps';
  
  static const Duration _cacheValidDuration = Duration(minutes: 30);
  
  final SharedPreferences _prefs;
  
  CacheManager(this._prefs);
  
  // Общие методы для работы с кэшем
  Future<void> saveData(String key, Map<String, dynamic> data) async {
    final cacheData = {
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await _prefs.setString(key, json.encode(cacheData));
    await _updateTimestamp(key);
  }
  
  Future<Map<String, dynamic>?> getData(String key) async {
    final cachedString = _prefs.getString(key);
    if (cachedString == null) return null;
    
    try {
      final cacheData = json.decode(cachedString);
      final timestamp = DateTime.fromMillisecondsSinceEpoch(cacheData['timestamp']);
      
      // Проверяем валидность кэша
      if (DateTime.now().difference(timestamp) > _cacheValidDuration) {
        print('🗑️ Cache expired for key: $key');
        return null;
      }
      
      return Map<String, dynamic>.from(cacheData['data']);
    } catch (e) {
      print('❌ Error reading cache for key $key: $e');
      return null;
    }
  }
  
  Future<bool> isCacheValid(String key) async {
    final cachedString = _prefs.getString(key);
    if (cachedString == null) return false;
    
    try {
      final cacheData = json.decode(cachedString);
      final timestamp = DateTime.fromMillisecondsSinceEpoch(cacheData['timestamp']);
      return DateTime.now().difference(timestamp) <= _cacheValidDuration;
    } catch (e) {
      return false;
    }
  }
  
  Future<void> clearCache(String key) async {
    await _prefs.remove(key);
    await _removeTimestamp(key);
  }
  
  Future<void> clearAllCache() async {
    await _prefs.remove(_profileKey);
    await _prefs.remove(_matchesKey);
    await _prefs.remove(_heroesKey);
    await _prefs.remove(_friendsKey);
    await _prefs.remove(_timestampKey);
  }
  
  // Специфичные методы для каждой вкладки
  Future<void> saveProfileData(Map<String, dynamic> profileData) async {
    await saveData(_profileKey, profileData);
  }
  
  Future<Map<String, dynamic>?> getProfileData() async {
    return await getData(_profileKey);
  }
  
  Future<void> saveMatchesData(List<Map<String, dynamic>> matches) async {
    await saveData(_matchesKey, {'matches': matches});
  }
  
  Future<List<Map<String, dynamic>>?> getMatchesData() async {
    final data = await getData(_matchesKey);
    if (data == null) return null;
    return List<Map<String, dynamic>>.from(data['matches'] ?? []);
  }
  
  Future<void> saveHeroesData(List<Map<String, dynamic>> heroes) async {
    await saveData(_heroesKey, {'heroes': heroes});
  }
  
  Future<List<Map<String, dynamic>>?> getHeroesData() async {
    final data = await getData(_heroesKey);
    if (data == null) return null;
    return List<Map<String, dynamic>>.from(data['heroes'] ?? []);
  }
  
  Future<void> saveFriendsData(List<Map<String, dynamic>> friends) async {
    await saveData(_friendsKey, {'friends': friends});
  }
  
  Future<List<Map<String, dynamic>>?> getFriendsData() async {
    final data = await getData(_friendsKey);
    if (data == null) return null;
    return List<Map<String, dynamic>>.from(data['friends'] ?? []);
  }
  
  // Управление временными метками
  Future<void> _updateTimestamp(String key) async {
    final timestamps = _getTimestamps();
    timestamps[key] = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setString(_timestampKey, json.encode(timestamps));
  }
  
  Future<void> _removeTimestamp(String key) async {
    final timestamps = _getTimestamps();
    timestamps.remove(key);
    await _prefs.setString(_timestampKey, json.encode(timestamps));
  }
  
  Map<String, int> _getTimestamps() {
    final timestampsString = _prefs.getString(_timestampKey);
    if (timestampsString == null) return {};
    
    try {
      final timestampsData = json.decode(timestampsString);
      return Map<String, int>.from(timestampsData);
    } catch (e) {
      return {};
    }
  }
  
  // Проверка необходимости обновления
  Future<bool> needsRefresh(String key) async {
    return !(await isCacheValid(key));
  }
  
  // Статистика кэша
  Future<Map<String, dynamic>> getCacheStats() async {
    final timestamps = _getTimestamps();
    final stats = <String, dynamic>{};
    
    for (final key in [_profileKey, _matchesKey, _heroesKey, _friendsKey]) {
      final timestamp = timestamps[key];
      if (timestamp != null) {
        final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
        stats[key] = {
          'last_updated': date.toIso8601String(),
          'is_valid': await isCacheValid(key),
        };
      } else {
        stats[key] = {
          'last_updated': null,
          'is_valid': false,
        };
      }
    }
    
    return stats;
  }
} 