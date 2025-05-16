import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SteamService {
  static const String _baseUrl = 'https://api.steampowered.com';
  static const String _dota2Api = '/IDOTA2Match_570';
  static const String _steamApi = '/ISteamUser';
  
  final String _apiKey;
  final SharedPreferences _prefs;
  
  SteamService(this._apiKey, this._prefs);
  
  // Конвертация Steam ID в account ID
  String _convertToAccountId(String steamId) {
    // Steam ID имеет формат "7656119XXXXXXXXXX"
    // Account ID - это последние 8 цифр минус 76561197960265728
    final steamIdNum = BigInt.parse(steamId);
    final accountId = (steamIdNum - BigInt.from(76561197960265728)).toString();
    return accountId;
  }
  
  Future<Map<String, dynamic>> getPlayerProfile(String steamId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl$_steamApi/GetPlayerSummaries/v0002/?key=$_apiKey&steamids=$steamId'),
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load profile');
    }
  }
  
  Future<Map<String, dynamic>> getPlayerStats(String steamId) async {
    final accountId = _convertToAccountId(steamId);
    final response = await http.get(
      Uri.parse('$_baseUrl$_dota2Api/GetPlayerStats/v1/?key=$_apiKey&account_id=$accountId'),
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return {
        'total_matches': data['result']['total_matches'] ?? 0,
        'wins': data['result']['wins'] ?? 0,
        'kills': data['result']['kills'] ?? 0,
        'deaths': data['result']['deaths'] ?? 0,
        'assists': data['result']['assists'] ?? 0,
        'win_rate': data['result']['wins'] != null && data['result']['total_matches'] != null
            ? (data['result']['wins'] / data['result']['total_matches'] * 100)
            : 0,
        'kda': data['result']['deaths'] != null && data['result']['deaths'] > 0
            ? ((data['result']['kills'] ?? 0) + (data['result']['assists'] ?? 0)) / data['result']['deaths']
            : 0,
        'gold_per_min': data['result']['gold_per_min'] ?? 0,
        'xp_per_min': data['result']['xp_per_min'] ?? 0,
      };
    } else {
      throw Exception('Failed to load player stats');
    }
  }
  
  Future<Map<String, dynamic>> getFriendsList(String steamId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl$_steamApi/GetFriendList/v1/?key=$_apiKey&steamid=$steamId&relationship=friend'),
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final friends = data['friendslist']['friends'] ?? [];
      
      // Получаем профили всех друзей
      final steamIds = friends.map((f) => f['steamid']).join(',');
      final profilesResponse = await http.get(
        Uri.parse('$_baseUrl$_steamApi/GetPlayerSummaries/v0002/?key=$_apiKey&steamids=$steamIds'),
      );
      
      if (profilesResponse.statusCode == 200) {
        final profilesData = json.decode(profilesResponse.body);
        final profiles = profilesData['response']['players'] ?? [];
        
        // Объединяем данные друзей с их профилями
        for (var friend in friends) {
          final profile = profiles.firstWhere(
            (p) => p['steamid'] == friend['steamid'],
            orElse: () => {},
          );
          friend.addAll(profile);
        }
      }
      
      return data;
    } else {
      throw Exception('Failed to load friends list');
    }
  }
  
  Future<Map<String, dynamic>> getMatchHistory(String steamId) async {
    final accountId = _convertToAccountId(steamId);
    final response = await http.get(
      Uri.parse('$_baseUrl$_dota2Api/GetMatchHistory/v1/?key=$_apiKey&account_id=$accountId'),
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load match history');
    }
  }
  
  Future<Map<String, dynamic>> getHeroes() async {
    final response = await http.get(
      Uri.parse('$_baseUrl$_dota2Api/GetHeroes/v1/?key=$_apiKey'),
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load heroes');
    }
  }
  
  Future<Map<String, dynamic>> getMatchDetails(String matchId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl$_dota2Api/GetMatchDetails/v1/?key=$_apiKey&match_id=$matchId'),
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load match details');
    }
  }
} 