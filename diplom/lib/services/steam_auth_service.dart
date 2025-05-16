import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class SteamAuthService {
  static const String _steamLoginUrl = 'https://steamcommunity.com/openid/login';
  static const String _returnUrl = 'http://localhost:8080/auth/steam/callback';
  static const String _realm = 'http://localhost:8080/';
  
  final SharedPreferences _prefs;
  
  SteamAuthService(this._prefs);
  
  Future<String> getSteamLoginUrl() async {
    final params = {
      'openid.ns': 'http://specs.openid.net/auth/2.0',
      'openid.mode': 'checkid_setup',
      'openid.return_to': _returnUrl,
      'openid.realm': _realm,
      'openid.identity': 'http://specs.openid.net/auth/2.0/identifier_select',
      'openid.claimed_id': 'http://specs.openid.net/auth/2.0/identifier_select',
    };
    
    final queryString = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    
    return '$_steamLoginUrl?$queryString';
  }
  
  Future<String?> extractSteamId(String responseUrl) async {
    final uri = Uri.parse(responseUrl);
    final params = uri.queryParameters;
    
    if (params['openid.mode'] == 'id_res') {
      final claimedId = params['openid.claimed_id'];
      if (claimedId != null) {
        final steamId = claimedId.split('/').last;
        await _prefs.setString('steam_id', steamId);
        return steamId;
      }
    }
    return null;
  }
  
  Future<bool> isAuthenticated() async {
    return _prefs.containsKey('steam_id');
  }
  
  Future<String?> getSteamId() async {
    return _prefs.getString('steam_id');
  }
  
  Future<void> logout() async {
    await _prefs.remove('steam_id');
  }
} 