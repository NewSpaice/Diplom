import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';


class SteamApiProvider extends ChangeNotifier {
  static const String _apiKeyKey = 'steam_api_key';
  final SharedPreferences _prefs;
  String? _apiKey;

  SteamApiProvider(this._prefs) {
    _loadApiKey();
  }

  String? get apiKey => _apiKey;

  Future<void> _loadApiKey() async {
    _apiKey = _prefs.getString(_apiKeyKey);
    print('Loaded API Key: ${_apiKey != null ? 'Key exists' : 'No key found'}');
    notifyListeners();
  }

  Future<void> setApiKey(String key) async {
    print('Setting new API Key');
    await _prefs.setString(_apiKeyKey, key);
    _apiKey = key;
    notifyListeners();
  }

  Future<void> clearApiKey() async {
    await _prefs.remove(_apiKeyKey);
    _apiKey = null;
    notifyListeners();
  }
} 