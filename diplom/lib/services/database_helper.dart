import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static const String _databaseName = 'dota_matches.db';
  static const int _databaseVersion = 2;
  
  static const String _tableMatches = 'matches';
  static const String _tableMatchDetails = 'match_details';
  
  Database? _database;
  
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }
  
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);
    
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }
  
  Future<void> _onCreate(Database db, int version) async {
    // Таблица для основных данных матчей
    await db.execute('''
      CREATE TABLE $_tableMatches (
        match_id INTEGER PRIMARY KEY,
        steam_id TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        duration INTEGER,
        radiant_win INTEGER,
        player_slot INTEGER,
        hero_id INTEGER,
        kills INTEGER,
        deaths INTEGER,
        assists INTEGER,
        gold_per_min INTEGER,
        xp_per_min INTEGER,
        hero_damage INTEGER,
        hero_healing INTEGER,
        tower_damage INTEGER,
        last_hits INTEGER,
        denies INTEGER,
        gpm INTEGER,
        xpm INTEGER,
        net_worth INTEGER,
        lobby_type INTEGER,
        game_mode INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');
    
    // Создаем индексы отдельно
    await db.execute('CREATE INDEX idx_matches_steam_id ON $_tableMatches(steam_id)');
    await db.execute('CREATE INDEX idx_matches_start_time ON $_tableMatches(start_time)');
    
    // Таблица для детальных данных матчей (JSON)
    await db.execute('''
      CREATE TABLE $_tableMatchDetails (
        match_id INTEGER PRIMARY KEY,
        full_data TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (match_id) REFERENCES $_tableMatches (match_id)
      )
    ''');
  }
  
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Удаляем старые таблицы и создаем новые
    await db.execute('DROP TABLE IF EXISTS $_tableMatchDetails');
    await db.execute('DROP TABLE IF EXISTS $_tableMatches');
    await _onCreate(db, newVersion);
  }
  
  // Сохранение матчей
  Future<void> saveMatches(String steamId, List<Map<String, dynamic>> matches) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await db.transaction((txn) async {
      for (final match in matches) {
        final matchId = match['match_id'] as int;
        
        // Проверяем, существует ли матч
        final existing = await txn.query(
          _tableMatches,
          where: 'match_id = ? AND steam_id = ?',
          whereArgs: [matchId, steamId],
        );
        
        if (existing.isEmpty) {
          // Вставляем основные данные матча
          await txn.insert(
            _tableMatches,
            {
              'match_id': matchId,
              'steam_id': steamId,
              'start_time': match['start_time'] ?? 0,
              'duration': match['duration'] ?? 0,
              'radiant_win': (match['radiant_win'] == true) ? 1 : 0,
              'player_slot': match['player_slot'] ?? 0,
              'hero_id': match['hero_id'] ?? 0,
              'kills': match['kills'] ?? 0,
              'deaths': match['deaths'] ?? 0,
              'assists': match['assists'] ?? 0,
              'gold_per_min': match['gold_per_min'] ?? 0,
              'xp_per_min': match['xp_per_min'] ?? 0,
              'hero_damage': match['hero_damage'] ?? 0,
              'hero_healing': match['hero_healing'] ?? 0,
              'tower_damage': match['tower_damage'] ?? 0,
              'last_hits': match['last_hits'] ?? 0,
              'denies': match['denies'] ?? 0,
              'gpm': match['gold_per_min'] ?? 0,
              'xpm': match['xp_per_min'] ?? 0,
              'net_worth': match['net_worth'] ?? 0,
              'lobby_type': match['lobby_type'] ?? 0,
              'game_mode': match['game_mode'] ?? 0,
              'created_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          
          // Вставляем полные данные матча
          await txn.insert(
            _tableMatchDetails,
            {
              'match_id': matchId,
              'full_data': json.encode(match),
              'created_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
    
    print('💾 Saved ${matches.length} matches to local database');
  }
  
  // Получение матчей с пагинацией
  Future<List<Map<String, dynamic>>> getMatches(
    String steamId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await database;
    
    final results = await db.query(
      _tableMatches,
      where: 'steam_id = ?',
      whereArgs: [steamId],
      orderBy: 'start_time DESC',
      limit: limit,
      offset: offset,
    );
    
    // Преобразуем результаты обратно в формат API
    final matches = <Map<String, dynamic>>[];
    for (final row in results) {
      final match = Map<String, dynamic>.from(row);
      match['radiant_win'] = match['radiant_win'] == 1;
      match.remove('steam_id');
      match.remove('created_at');
      matches.add(match);
    }
    
    return matches;
  }
  
  // Получение полных данных матча
  Future<Map<String, dynamic>?> getMatchDetails(int matchId) async {
    final db = await database;
    
    final results = await db.query(
      _tableMatchDetails,
      where: 'match_id = ?',
      whereArgs: [matchId],
    );
    
    if (results.isEmpty) return null;
    
    try {
      return json.decode(results.first['full_data'] as String);
    } catch (e) {
      print('❌ Error parsing match details: $e');
      return null;
    }
  }
  
  // Подсчет общего количества матчей
  Future<int> getMatchesCount(String steamId) async {
    final db = await database;
    
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableMatches WHERE steam_id = ?',
      [steamId],
    );
    
    return result.first['count'] as int;
  }
  
  // Получение последнего времени матча
  Future<int?> getLastMatchTime(String steamId) async {
    final db = await database;
    
    final results = await db.query(
      _tableMatches,
      columns: ['start_time'],
      where: 'steam_id = ?',
      whereArgs: [steamId],
      orderBy: 'start_time DESC',
      limit: 1,
    );
    
    if (results.isEmpty) return null;
    return results.first['start_time'] as int;
  }
  
  // Проверка существования матча
  Future<bool> matchExists(String steamId, int matchId) async {
    final db = await database;
    
    final results = await db.query(
      _tableMatches,
      where: 'steam_id = ? AND match_id = ?',
      whereArgs: [steamId, matchId],
    );
    
    return results.isNotEmpty;
  }
  
  // Удаление старых матчей (старше определенного времени)
  Future<void> cleanOldMatches(String steamId, {Duration? olderThan}) async {
    olderThan ??= const Duration(days: 90);
    final db = await database;
    final cutoffTime = DateTime.now().subtract(olderThan).millisecondsSinceEpoch ~/ 1000;
    
    final deletedCount = await db.delete(
      _tableMatches,
      where: 'steam_id = ? AND start_time < ?',
      whereArgs: [steamId, cutoffTime],
    );
    
    print('🗑️ Cleaned $deletedCount old matches');
  }
  
  // Получение статистики базы данных
  Future<Map<String, dynamic>> getDatabaseStats(String steamId) async {
    final db = await database;
    
    final matchesCount = await getMatchesCount(steamId);
    final lastMatchTime = await getLastMatchTime(steamId);
    
    final sizeResult = await db.rawQuery(
      'SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()',
    );
    
    return {
      'matches_count': matchesCount,
      'last_match_time': lastMatchTime,
      'database_size_bytes': sizeResult.first['size'] ?? 0,
    };
  }
  
  // Получение пути к базе данных
  Future<String> getDatabasePath() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);
    print('📍 Database path: $path');
    return path;
  }
  
  // Закрытие базы данных
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
  
  // Обновление длительности матча
  Future<void> updateMatchDuration(int matchId, int duration) async {
    final db = await database;
    
    await db.update(
      _tableMatches,
      {'duration': duration},
      where: 'match_id = ?',
      whereArgs: [matchId],
    );
    
    print('💾 Updated duration for match $matchId: $duration seconds');
  }
} 