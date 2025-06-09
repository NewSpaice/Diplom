import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class SteamService {
  static const String _baseUrl = 'https://api.steampowered.com';
  static const String _dota2Api = '/IDOTA2Match_570';
  static const String _steamApi = '/ISteamUser';
  
  final String apiKey;
  final SharedPreferences prefs;
  final _client = http.Client();
  final _cache = <String, dynamic>{};
  final _cacheDuration = const Duration(minutes: 5);
  
  // Добавляем контроль задержек
  DateTime? _lastRequestTime;
  static const Duration _requestDelay = Duration(milliseconds: 3000);
  
  SteamService(this.apiKey, this.prefs);
  
  // Конвертация Steam ID в account ID
  String _convertToAccountId(String steamId) {
    // Steam ID имеет формат "7656119XXXXXXXXXX"
    // Account ID - это последние 8 цифр минус 76561197960265728
    final steamIdNum = BigInt.parse(steamId);
    final accountId = (steamIdNum - BigInt.from(76561197960265728)).toString();
    return accountId;
  }
  
  Future<Map<String, dynamic>> getPlayerProfile(String steamId) async {
    try {
      print('Getting player profile for steamId: $steamId');
      
      // Проверяем кэш с увеличенным временем жизни
      final cacheKey = 'profile_$steamId';
      final cachedData = _cache[cacheKey];
      if (cachedData != null) {
        final cacheTime = cachedData['timestamp'] as DateTime;
        if (DateTime.now().difference(cacheTime) < const Duration(hours: 4)) {
          print('✅ Returning cached profile data');
          return cachedData['data'] as Map<String, dynamic>;
        }
      }
      
      // Ждем, чтобы не превысить лимит
      await _waitForRateLimit();
      
      final url = '$_baseUrl$_steamApi/GetPlayerSummaries/v0002/?key=$apiKey&steamids=$steamId';
      print('Profile URL: $url');
      
      final response = await http.get(Uri.parse(url));
      print('Profile response status: ${response.statusCode}');
      
      if (response.statusCode == 429) {
        print('⚠️ Rate limit exceeded for profile, using exponential backoff...');
        
        // Экспоненциальная задержка для профиля
        for (int attempt = 1; attempt <= 3; attempt++) {
          final delay = Duration(seconds: 10 * attempt); // 10, 20, 30 секунд
          print('🕐 Waiting ${delay.inSeconds} seconds before profile retry attempt $attempt');
          await Future.delayed(delay);
          
          final retryResponse = await http.get(Uri.parse(url));
          print('Profile retry $attempt response status: ${retryResponse.statusCode}');
          
          if (retryResponse.statusCode == 200) {
            final data = json.decode(retryResponse.body);
            
            // Проверяем, что в ответе есть игроки
            if (data['response']?['players'] == null || (data['response']['players'] as List).isEmpty) {
              throw Exception('Игрок не найден или профиль приватный');
            }
            
            // Сохраняем в кэш с длительным временем жизни
            _cache[cacheKey] = {
              'data': data,
              'timestamp': DateTime.now(),
            };
            
            print('✅ Profile loaded after retry $attempt');
            return data;
            
          } else if (retryResponse.statusCode == 429) {
            print('⚠️ Still rate limited for profile after attempt $attempt');
            continue;
          } else {
            print('❌ Different error for profile after retry $attempt: ${retryResponse.statusCode}');
            break;
          }
        }
        
        throw Exception('Превышен лимит запросов к API. Попробуйте позже.');
      }
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Проверяем, что в ответе есть игроки
        if (data['response']?['players'] == null || (data['response']['players'] as List).isEmpty) {
          throw Exception('Игрок не найден или профиль приватный');
        }
        
        // Сохраняем в кэш с длительным временем жизни
        _cache[cacheKey] = {
          'data': data,
          'timestamp': DateTime.now(),
        };
        
        return data;
      } else {
        throw Exception(_getErrorMessage(response.statusCode, response.body));
      }
    } catch (e) {
      print('Error in getPlayerProfile: $e');
      rethrow;
    }
  }
  
  Future<Map<String, dynamic>> getPlayerStats(String steamId) async {
    final accountId = _convertToAccountId(steamId);
    
    try {
      // Проверяем кэш
      final cacheKey = 'stats_$accountId';
      final cachedData = _cache[cacheKey];
      if (cachedData != null) {
        final cacheTime = cachedData['timestamp'] as DateTime;
        if (DateTime.now().difference(cacheTime) < _cacheDuration) {
          print('Returning cached stats data');
          return cachedData['data'] as Map<String, dynamic>;
        }
      }
      
      // Ждем, чтобы не превысить лимит
      await _waitForRateLimit();
      
      // Используем OpenDota API вместо Steam API
      final url = 'https://api.opendota.com/api/players/$accountId';
      print('Getting player stats from OpenDota: $url');
      
      final response = await _client.get(Uri.parse(url));
      print('Player stats response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Player data: ${data.toString()}');
        
        // Также получаем общую статистику матчей (с задержкой)
        await _waitForRateLimit();
        final winLossUrl = 'https://api.opendota.com/api/players/$accountId/wl';
        final winLossResponse = await _client.get(Uri.parse(winLossUrl));
        
        int wins = 0;
        int total = 0;
        
        if (winLossResponse.statusCode == 200) {
          final winLossData = json.decode(winLossResponse.body);
          wins = (winLossData['win'] ?? 0) as int;
          final losses = (winLossData['lose'] ?? 0) as int;
          total = wins + losses;
        }
        
        final result = {
          'total_matches': total,
          'wins': wins,
          'losses': total - wins,
          'win_rate': total > 0 ? (wins / total * 100) : 0,
          'rank_tier': data['rank_tier'] ?? 0,
          'leaderboard_rank': data['leaderboard_rank'],
          'profile': {
            'account_id': data['profile']?['account_id'],
            'personaname': data['profile']?['personaname'],
            'avatar': data['profile']?['avatar'],
            'steamid': data['profile']?['steamid'],
          },
        };
        
        // Сохраняем в кэш
        _cache[cacheKey] = {
          'data': result,
          'timestamp': DateTime.now(),
        };
        
        return result;
      } else {
        throw Exception('Failed to load player stats from OpenDota API: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in getPlayerStats: $e');
      // Возвращаем базовую структуру данных в случае ошибки
      return {
        'total_matches': 0,
        'wins': 0,
        'losses': 0,
        'win_rate': 0,
        'rank_tier': 0,
        'leaderboard_rank': null,
      };
    }
  }
  
  Future<Map<String, dynamic>> getFriendsList(String steamId) async {
    try {
      print('👥 Getting friends list for steamId: $steamId');
      
      // Проверяем кэш
      final cacheKey = 'friends_list_$steamId';
      final cachedData = _cache[cacheKey];
      if (cachedData != null) {
        final cacheTime = cachedData['timestamp'] as DateTime;
        if (DateTime.now().difference(cacheTime) < const Duration(hours: 6)) {
          print('✅ Returning cached friends list');
          return cachedData['data'] as Map<String, dynamic>;
        }
      }
      
      // Ждем, чтобы не превысить лимит
      await _waitForRateLimit();
      
      final response = await http.get(
        Uri.parse('$_baseUrl$_steamApi/GetFriendList/v1/?key=$apiKey&steamid=$steamId&relationship=friend'),
      );
      
      print('Friends list response status: ${response.statusCode}');
      
      if (response.statusCode == 429) {
        print('⚠️ Rate limit exceeded, waiting 10 seconds...');
        await Future.delayed(const Duration(seconds: 10));
        return getFriendsList(steamId); // Рекурсивный вызов после задержки
      }
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final friendsListData = data['friendslist'];
        
        if (friendsListData == null || friendsListData['friends'] == null) {
          print('⚠️ No friends list found');
          return {
            'friendslist': {
              'friends': <Map<String, dynamic>>[]
            }
          };
        }
        
        final friends = friendsListData['friends'] as List;
        print('Found ${friends.length} friends');
        
        if (friends.isEmpty) {
          return {
            'friendslist': {
              'friends': <Map<String, dynamic>>[]
            }
          };
        }
        
        // Преобразуем список друзей к правильному типу
        final List<Map<String, dynamic>> typedFriends = [];
        final List<String> steamIds = [];
        
        for (var friend in friends) {
          if (friend is Map) {
            final typedFriend = Map<String, dynamic>.from(friend);
            typedFriends.add(typedFriend);
            
            final steamId = typedFriend['steamid'];
            if (steamId != null) {
              steamIds.add(steamId.toString());
            }
          }
        }
        
        // Получаем профили друзей порциями по 50 человек
        if (steamIds.isNotEmpty) {
          const int batchSize = 50;
          final List<List<String>> batches = [];
          
          for (int i = 0; i < steamIds.length; i += batchSize) {
            final end = (i + batchSize < steamIds.length) ? i + batchSize : steamIds.length;
            batches.add(steamIds.sublist(i, end));
          }
          
          print('📦 Loading friend profiles in ${batches.length} batches');
          
          for (int batchIndex = 0; batchIndex < batches.length; batchIndex++) {
            final batch = batches[batchIndex];
            final steamIdsString = batch.join(',');
            
            // Ждем между батчами
            if (batchIndex > 0) {
              await _waitForRateLimit();
            }
            
            try {
              final profilesResponse = await http.get(
                Uri.parse('$_baseUrl$_steamApi/GetPlayerSummaries/v0002/?key=$apiKey&steamids=$steamIdsString'),
              );
              
              if (profilesResponse.statusCode == 429) {
                print('⚠️ Rate limit exceeded in batch $batchIndex, using exponential backoff...');
                
                // Экспоненциальная задержка для батча профилей: 10, 20, 30 секунд
                for (int attempt = 1; attempt <= 3; attempt++) {
                  final delay = Duration(seconds: 10 * attempt);
                  print('🕐 Waiting ${delay.inSeconds} seconds before batch retry attempt $attempt');
                  await Future.delayed(delay);
                  
                  final retryResponse = await http.get(
                    Uri.parse('$_baseUrl$_steamApi/GetPlayerSummaries/v0002/?key=$apiKey&steamids=$steamIdsString'),
                  );
                  
                  if (retryResponse.statusCode == 200) {
                    final profilesData = json.decode(retryResponse.body) as Map<String, dynamic>;
                    final profiles = profilesData['response']?['players'] as List? ?? [];
                    
                    // Объединяем данные друзей с их профилями
                    for (var friend in typedFriends) {
                      final friendSteamId = friend['steamid'];
                      
                      for (var profile in profiles) {
                        if (profile is Map && profile['steamid'] == friendSteamId) {
                          final typedProfile = Map<String, dynamic>.from(profile);
                          friend.addAll(typedProfile);
                          break;
                        }
                      }
                    }
                    
                    print('✅ Loaded batch ${batchIndex + 1}/${batches.length} (${profiles.length} profiles) after retry $attempt');
                    break; // Выходим из цикла retry если успешно
                    
                  } else if (retryResponse.statusCode == 429) {
                    print('⚠️ Still rate limited for batch $batchIndex after attempt $attempt');
                    if (attempt == 3) {
                      print('❌ Skipping batch $batchIndex after all retry attempts failed');
                    }
                    continue;
                  } else {
                    print('❌ Different error for batch $batchIndex after retry $attempt: ${retryResponse.statusCode}');
                    break;
                  }
                }
              } else if (profilesResponse.statusCode == 200) {
                final profilesData = json.decode(profilesResponse.body) as Map<String, dynamic>;
                final profiles = profilesData['response']?['players'] as List? ?? [];
                
                // Объединяем данные друзей с их профилями
                for (var friend in typedFriends) {
                  final friendSteamId = friend['steamid'];
                  
                  for (var profile in profiles) {
                    if (profile is Map && profile['steamid'] == friendSteamId) {
                      final typedProfile = Map<String, dynamic>.from(profile);
                      friend.addAll(typedProfile);
                      break;
                    }
                  }
                }
                
                print('✅ Loaded batch ${batchIndex + 1}/${batches.length} (${profiles.length} profiles)');
              } else {
                print('❌ Error loading batch $batchIndex: ${profilesResponse.statusCode}');
              }
            } catch (e) {
              print('❌ Error in batch $batchIndex: $e');
            }
          }
        }
        
        final result = {
          'friendslist': {
            'friends': typedFriends
          }
        };
        
        // Сохраняем в кэш
        _cache[cacheKey] = {
          'data': result,
          'timestamp': DateTime.now(),
        };
        
        print('✅ Successfully loaded ${typedFriends.length} friends');
        return result;
        
      } else {
        throw Exception('Failed to load friends list: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error in getFriendsList: $e');
      return {
        'friendslist': {
          'friends': <Map<String, dynamic>>[]
        }
      };
    }
  }
  
  Future<bool> _checkInternetConnection() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }
  
  Future<Map<String, dynamic>> getMatchHistory(String steamId) async {
    try {
      final accountId = _convertToAccountId(steamId);
      final url = '$_baseUrl$_dota2Api/GetMatchHistory/v1/?key=$apiKey&account_id=$accountId';
      
      final response = await _client.get(Uri.parse(url));
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['result'] != null && data['result']['matches'] != null) {
          final matches = data['result']['matches'] as List;
          
          // Получаем детали для каждого матча
          for (var match in matches) {
            try {
              final matchId = match['match_id'].toString();
              final details = await _getMatchDetails(matchId);
              if (details != null) {
                // Добавляем информацию о победе
                match['radiant_win'] = details['radiant_win'];
                // Добавляем статистику игрока
                final player = (details['players'] as List).firstWhere(
                  (p) => p['account_id'].toString() == accountId,
                  orElse: () => {},
                );
                if (player.isNotEmpty) {
                  match['player_stats'] = {
                    'kills': player['kills'] ?? 0,
                    'deaths': player['deaths'] ?? 0,
                    'assists': player['assists'] ?? 0,
                    'gold_per_min': player['gold_per_min'] ?? 0,
                    'xp_per_min': player['xp_per_min'] ?? 0,
                    'hero_damage': player['hero_damage'] ?? 0,
                    'hero_healing': player['hero_healing'] ?? 0,
                  };
                }
              }
            } catch (e) {
              print('Error loading match details for ${match['match_id']}: $e');
            }
          }
          
          return data;
        }
      }
      throw Exception('Failed to load match history: ${response.statusCode}');
    } catch (e) {
      print('Error in getMatchHistory: $e');
      rethrow;
    }
  }
  
  Future<Map<String, dynamic>?> _getMatchDetails(String matchId) async {
    try {
      // Проверяем кэш
      final cacheKey = 'match_$matchId';
      final cachedData = _cache[cacheKey];
      if (cachedData != null) {
        final cacheTime = cachedData['timestamp'] as DateTime;
        if (DateTime.now().difference(cacheTime) < _cacheDuration) {
          return cachedData['data'] as Map<String, dynamic>;
        }
      }

      // Используем OpenDota API вместо Steam API
      final url = 'https://api.opendota.com/api/matches/$matchId';
      print('\n=== GetMatchDetails from OpenDota ===');
      print('URL: $url');
      
      final response = await _client.get(Uri.parse(url));
      print('Response Status: ${response.statusCode}');
      print('Response Body:');
      print(const JsonEncoder.withIndent('  ').convert(json.decode(response.body)));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Сохраняем в кэш
        _cache[cacheKey] = {
          'data': data,
          'timestamp': DateTime.now(),
        };
        return data;
      }
      return null;
    } catch (e) {
      print('Error in _getMatchDetails: $e');
      return null;
    }
  }
  
  Future<Map<String, dynamic>> getHeroes() async {
    try {
      // Проверяем кэш
      final cacheKey = 'heroes_data';
      final cachedData = _cache[cacheKey];
      if (cachedData != null) {
        final cacheTime = cachedData['timestamp'] as DateTime;
        if (DateTime.now().difference(cacheTime) < const Duration(hours: 24)) {
          print('✅ Returning cached heroes data');
          return cachedData['data'] as Map<String, dynamic>;
        }
      }
      
      // Ждем, чтобы не превысить лимит
      await _waitForRateLimit();
      
      final url = '$_baseUrl/IEconDOTA2_570/GetHeroes/v1/?key=$apiKey&language=ru_ru';
      print('🎮 Loading heroes from Steam API: $url');
      
      final response = await _client.get(Uri.parse(url));
      print('Heroes API Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        print('Heroes API Response data: ${data.toString()}');
        
        // Проверяем структуру ответа
        if (data['result'] != null && data['result']['heroes'] != null) {
          // Сохраняем в кэш
          _cache[cacheKey] = {
            'data': data,
            'timestamp': DateTime.now(),
          };
          
          final heroesCount = (data['result']['heroes'] as List).length;
          print('✅ Successfully loaded $heroesCount heroes');
          
          return data;
        } else {
          throw Exception('Неверная структура ответа API героев');
        }
      } else {
        throw Exception(_getErrorMessage(response.statusCode, response.body));
      }
    } catch (e) {
      print('❌ Error in getHeroes: $e');
      rethrow;
    }
  }
  
  // Получение статистики игрока по героям
  Future<List<Map<String, dynamic>>> getPlayerHeroes(String steamId) async {
    final accountId = _convertToAccountId(steamId);
    
    try {
      // Проверяем кэш
      final cacheKey = 'player_heroes_$accountId';
      final cachedData = _cache[cacheKey];
      if (cachedData != null) {
        final cacheTime = cachedData['timestamp'] as DateTime;
        if (DateTime.now().difference(cacheTime) < _cacheDuration) {
          print('✅ Returning cached player heroes data');
          return List<Map<String, dynamic>>.from(cachedData['data']);
        }
      }
      
      // Ждем, чтобы не превысить лимит
      await _waitForRateLimit();
      
      // Используем OpenDota API для получения статистики по героям
      final url = 'https://api.opendota.com/api/players/$accountId/heroes';
      print('🦸 Getting player heroes stats from OpenDota: $url');
      
      final response = await _client.get(Uri.parse(url));
      print('Player heroes response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        print('Player heroes data count: ${data.length}');
        
        // Получаем информацию о героях из Steam API для названий
        final heroesInfo = await getHeroes();
        final heroesMap = <String, Map<String, dynamic>>{};
        
        if (heroesInfo['result'] != null && heroesInfo['result']['heroes'] != null) {
          for (var hero in heroesInfo['result']['heroes']) {
            heroesMap[hero['id'].toString()] = hero;
          }
        }
        
        // Преобразуем данные и добавляем информацию о героях
        final List<Map<String, dynamic>> result = [];
        
        for (var heroStats in data) {
          if (heroStats is Map) {
            final typedHeroStats = Map<String, dynamic>.from(heroStats);
            final heroId = typedHeroStats['hero_id'].toString();
            final heroInfo = heroesMap[heroId] ?? <String, dynamic>{};
            
            result.add({
              'hero_id': typedHeroStats['hero_id'] ?? 0,
              'hero_name': heroInfo['localized_name'] ?? heroInfo['name'] ?? 'Unknown Hero',
              'hero_internal_name': heroInfo['name'] ?? '',
              'games': typedHeroStats['games'] ?? 0,
              'wins': typedHeroStats['win'] ?? 0,
              'losses': (typedHeroStats['games'] ?? 0) - (typedHeroStats['win'] ?? 0),
              'win_rate': (typedHeroStats['games'] ?? 0) > 0 
                  ? ((typedHeroStats['win'] ?? 0) / (typedHeroStats['games'] ?? 0) * 100) 
                  : 0.0,
              'with_games': typedHeroStats['with_games'] ?? 0,
              'with_win': typedHeroStats['with_win'] ?? 0,
              'against_games': typedHeroStats['against_games'] ?? 0,
              'against_win': typedHeroStats['against_win'] ?? 0,
              'last_played': typedHeroStats['last_played'] ?? 0,
            });
          }
        }
        
        // Сортируем по количеству игр (по убыванию)
        result.sort((a, b) => (b['games'] as int).compareTo(a['games'] as int));
        
        // Сохраняем в кэш
        _cache[cacheKey] = {
          'data': result,
          'timestamp': DateTime.now(),
        };
        
        print('✅ Successfully loaded ${result.length} player heroes');
        return result;
        
      } else if (response.statusCode == 404) {
        // Игрок не найден или данные недоступны
        print('⚠️ Player heroes data not found (404)');
        return <Map<String, dynamic>>[];
      } else {
        throw Exception('Failed to load player heroes from OpenDota API: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error in getPlayerHeroes: $e');
      // Возвращаем пустой список в случае ошибки
      return <Map<String, dynamic>>[];
    }
  }
  
  // Получение совместных матчей с друзьями
  Future<List<Map<String, dynamic>>> getPlayersMatches(String steamId, String friendSteamId) async {
    final accountId = _convertToAccountId(steamId);
    final friendAccountId = _convertToAccountId(friendSteamId);
    
    try {
      // Проверяем кэш
      final cacheKey = 'matches_with_${accountId}_$friendAccountId';
      final cachedData = _cache[cacheKey];
      if (cachedData != null) {
        final cacheTime = cachedData['timestamp'] as DateTime;
        if (DateTime.now().difference(cacheTime) < const Duration(hours: 6)) {
          print('✅ Returning cached matches with friend');
          return List<Map<String, dynamic>>.from(cachedData['data']);
        }
      }
      
      // Ждем, чтобы не превысить лимит
      await _waitForRateLimit();
      
      // Получаем матчи игрока с указанием игрока друга (без ограничения количества, все типы игр)
      final url = 'https://api.opendota.com/api/players/$accountId/matches?included_account_id=$friendAccountId&significant=1';
      print('🤝 Getting matches with friend from OpenDota: $url');
      
      final response = await _client.get(Uri.parse(url));
      print('Matches with friend response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        print('Matches with friend count: ${data.length}');
        
        // Преобразуем данные с правильной типизацией
        final List<Map<String, dynamic>> result = [];
        
        for (var match in data) {
          if (match is Map) {
            final typedMatch = Map<String, dynamic>.from(match);
            result.add({
              'match_id': typedMatch['match_id'] ?? 0,
              'start_time': typedMatch['start_time'] ?? 0,
              'duration': typedMatch['duration'] ?? 0,
              'radiant_win': typedMatch['radiant_win'] ?? false,
              'player_slot': typedMatch['player_slot'] ?? 0,
              'hero_id': typedMatch['hero_id'] ?? 0,
              'kills': typedMatch['kills'] ?? 0,
              'deaths': typedMatch['deaths'] ?? 0,
              'assists': typedMatch['assists'] ?? 0,
              'lobby_type': typedMatch['lobby_type'] ?? 0,
              'game_mode': typedMatch['game_mode'] ?? 0,
            });
          }
        }
        
        // Сохраняем в кэш с увеличенным временем жизни
        _cache[cacheKey] = {
          'data': result,
          'timestamp': DateTime.now(),
        };
        
        print('✅ Successfully loaded ${result.length} matches with friend');
        return result;
        
      } else if (response.statusCode == 429) {
        print('⚠️ Rate limit exceeded (429), using exponential backoff...');
        
        // Экспоненциальная задержка: 5, 10, 20 секунд
        for (int attempt = 1; attempt <= 3; attempt++) {
          final delay = Duration(seconds: 5 * attempt);
          print('🕐 Waiting ${delay.inSeconds} seconds before retry attempt $attempt');
          await Future.delayed(delay);
          
          final retryResponse = await _client.get(Uri.parse(url));
          if (retryResponse.statusCode == 200) {
            final data = json.decode(retryResponse.body) as List;
            print('Matches with friend count (retry $attempt): ${data.length}');
            
            final List<Map<String, dynamic>> result = [];
            
            for (var match in data) {
              if (match is Map) {
                final typedMatch = Map<String, dynamic>.from(match);
                result.add({
                  'match_id': typedMatch['match_id'] ?? 0,
                  'start_time': typedMatch['start_time'] ?? 0,
                  'duration': typedMatch['duration'] ?? 0,
                  'radiant_win': typedMatch['radiant_win'] ?? false,
                  'player_slot': typedMatch['player_slot'] ?? 0,
                  'hero_id': typedMatch['hero_id'] ?? 0,
                  'kills': typedMatch['kills'] ?? 0,
                  'deaths': typedMatch['deaths'] ?? 0,
                  'assists': typedMatch['assists'] ?? 0,
                  'lobby_type': typedMatch['lobby_type'] ?? 0,
                  'game_mode': typedMatch['game_mode'] ?? 0,
                });
              }
            }
            
            // Сохраняем в кэш
            _cache[cacheKey] = {
              'data': result,
              'timestamp': DateTime.now(),
            };
            
            print('✅ Successfully loaded ${result.length} matches with friend (after retry $attempt)');
            return result;
            
          } else if (retryResponse.statusCode == 429) {
            print('⚠️ Still rate limited after attempt $attempt');
            continue;
          } else {
            print('❌ Different error after retry $attempt: ${retryResponse.statusCode}');
            break;
          }
        }
        
        print('❌ All retry attempts failed, returning empty list');
        return <Map<String, dynamic>>[];
        
      } else if (response.statusCode == 404) {
        print('⚠️ No matches found with friend (404)');
        
        // Кэшируем пустой результат чтобы не запрашивать снова
        _cache[cacheKey] = {
          'data': <Map<String, dynamic>>[],
          'timestamp': DateTime.now(),
        };
        
        return <Map<String, dynamic>>[];
      } else {
        throw Exception('Failed to load matches with friend: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error in getPlayersMatches: $e');
      return <Map<String, dynamic>>[];
    }
  }
  
  // Получение статистики совместных игр с другом
  Future<Map<String, dynamic>> getFriendStats(String steamId, String friendSteamId) async {
    try {
      print('👫 Calculating friend stats for $steamId with $friendSteamId');
      
      // Проверяем кэш
      final cacheKey = 'friend_stats_${steamId}_$friendSteamId';
      final cachedData = _cache[cacheKey];
      if (cachedData != null) {
        final cacheTime = cachedData['timestamp'] as DateTime;
        if (DateTime.now().difference(cacheTime) < const Duration(hours: 2)) {
          print('✅ Returning cached friend stats');
          return cachedData['data'] as Map<String, dynamic>;
        }
      }
      
      // Получаем совместные матчи
      final matches = await getPlayersMatches(steamId, friendSteamId);
      
      if (matches.isEmpty) {
        final emptyStats = {
          'total_games': 0,
          'wins': 0,
          'losses': 0,
          'win_rate': 0.0,
          'avg_duration': 0,
          'last_played': 0,
          'total_kills': 0,
          'total_deaths': 0,
          'total_assists': 0,
          'avg_kda': 0.0,
        };
        
        // Кэшируем даже пустой результат
        _cache[cacheKey] = {
          'data': emptyStats,
          'timestamp': DateTime.now(),
        };
        
        return emptyStats;
      }
      
      int wins = 0;
      int totalKills = 0;
      int totalDeaths = 0;
      int totalAssists = 0;
      int totalDuration = 0;
      int lastPlayed = 0;
      
      for (var match in matches) {
        final playerSlot = match['player_slot'] as int;
        final radiantWin = match['radiant_win'] as bool;
        final isRadiant = playerSlot < 128;
        
        // Подсчитываем победы
        if ((isRadiant && radiantWin) || (!isRadiant && !radiantWin)) {
          wins++;
        }
        
        totalKills += (match['kills'] as int);
        totalDeaths += (match['deaths'] as int);
        totalAssists += (match['assists'] as int);
        totalDuration += (match['duration'] as int);
        
        final matchTime = match['start_time'] as int;
        if (matchTime > lastPlayed) {
          lastPlayed = matchTime;
        }
      }
      
      final totalGames = matches.length;
      final winRate = totalGames > 0 ? (wins / totalGames * 100) : 0.0;
      final avgDuration = totalGames > 0 ? (totalDuration / totalGames) : 0;
      final avgKda = totalDeaths > 0 ? ((totalKills + totalAssists) / totalDeaths) : 0.0;
      
      final result = {
        'total_games': totalGames,
        'wins': wins,
        'losses': totalGames - wins,
        'win_rate': winRate,
        'avg_duration': avgDuration,
        'last_played': lastPlayed,
        'total_kills': totalKills,
        'total_deaths': totalDeaths,
        'total_assists': totalAssists,
        'avg_kda': avgKda,
      };
      
      // Сохраняем в кэш
      _cache[cacheKey] = {
        'data': result,
        'timestamp': DateTime.now(),
      };
      
      print('✅ Calculated friend stats: $result');
      return result;
      
    } catch (e) {
      print('❌ Error in getFriendStats: $e');
      return {
        'total_games': 0,
        'wins': 0,
        'losses': 0,
        'win_rate': 0.0,
        'avg_duration': 0,
        'last_played': 0,
        'total_kills': 0,
        'total_deaths': 0,
        'total_assists': 0,
        'avg_kda': 0.0,
      };
    }
  }
  
  // Контроль скорости запросов
  Future<void> _waitForRateLimit() async {
    if (_lastRequestTime != null) {
      final timeSinceLastRequest = DateTime.now().difference(_lastRequestTime!);
      if (timeSinceLastRequest < _requestDelay) {
        await Future.delayed(_requestDelay - timeSinceLastRequest);
      }
    }
    _lastRequestTime = DateTime.now();
  }
  
  // Обработка HTTP ошибок
  String _getErrorMessage(int statusCode, String body) {
    switch (statusCode) {
      case 429:
        return 'Превышен лимит запросов к API. Попробуйте позже.';
      case 403:
        return 'Недостаточно прав доступа к API.';
      case 401:
        return 'Неверный API ключ.';
      case 500:
      case 502:
      case 503:
        return 'Ошибка сервера Steam. Попробуйте позже.';
      default:
        return 'Ошибка API ($statusCode)';
    }
  }
  
  // Получение констант из OpenDota API
  static const String _openDotaBaseUrl = 'https://api.opendota.com';
  
  Future<Map<String, dynamic>?> getRankConstants() async {
    try {
      // Проверяем кэш
      final cacheKey = 'rank_constants';
      final cachedData = _cache[cacheKey];
      if (cachedData != null) {
        final cacheTime = cachedData['timestamp'] as DateTime;
        if (DateTime.now().difference(cacheTime) < const Duration(hours: 24)) {
          return cachedData['data'] as Map<String, dynamic>;
        }
      }
      
      final url = '$_openDotaBaseUrl/api/constants/rank_tier';
      final response = await _client.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Сохраняем в кэш
        _cache[cacheKey] = {
          'data': data,
          'timestamp': DateTime.now(),
        };
        
        return data;
      }
      return null;
    } catch (e) {
      print('Error getting rank constants: $e');
      return null;
    }
  }
  
  // Получение пути к локальному изображению ранга
  String getRankImageUrl(int rankTier) {
    print('🔍 Getting local rank image for tier: $rankTier');
    
    if (rankTier == 0) {
      final path = 'ranks/rank_icon_0.webp';
      print('📄 No rank (0): $path');
      return path;
    }
    
    // Используем локальные изображения медалек из папки ranks (приоритет WEBP)
    final path = 'ranks/rank_icon_$rankTier.webp';
    print('🏆 Rank $rankTier: $path');
    return path;
  }
  
  // Получение fallback пути для PNG формата
  String getRankImageUrlPng(int rankTier) {
    if (rankTier == 0) {
      return 'ranks/rank_icon_0.png';
    }
    return 'ranks/rank_icon_$rankTier.png';
  }
  
  void dispose() {
    _client.close();
  }
} 