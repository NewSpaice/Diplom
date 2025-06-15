import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../services/steam_service.dart';
import '../services/cache_manager.dart';
import '../services/database_helper.dart';
import '../providers/steam_api_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/matches_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class MatchesScreen extends StatefulWidget {
  final String steamId;

  const MatchesScreen({super.key, required this.steamId});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  bool _isLoading = true;
  String _selectedHero = 'Все герои';
  String _selectedResult = 'Все результаты';
  List<String> _heroes = ['Все герои'];
  MatchesProvider? _matchesProvider;

  @override
  void initState() {
    super.initState();
    _initializeMatches();
  }

  Future<void> _initializeMatches() async {
    try {
      final apiProvider = context.read<SteamApiProvider>();
      final apiKey = apiProvider.apiKey;
      
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('API ключ не установлен');
      }
      
      final prefs = await SharedPreferences.getInstance();
      final cacheManager = CacheManager(prefs);
      final databaseHelper = DatabaseHelper();
      final steamService = SteamService(apiKey, prefs);
      
      _matchesProvider = MatchesProvider(
        steamId: widget.steamId,
        cacheManager: cacheManager,
        steamService: steamService,
        databaseHelper: databaseHelper,
      );
      
      _matchesProvider!.addListener(() {
        if (mounted) {
          setState(() {
            _heroes = _matchesProvider!.heroes;
          });
        }
      });
      
      await _matchesProvider!.initialize();
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _heroes = _matchesProvider!.heroes;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка инициализации: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  List<dynamic> get _filteredMatches {
    if (_matchesProvider == null) return [];
    
    return _matchesProvider!.matches.where((match) {
      final heroName = match['hero_name'] ?? '';
      final heroMatch = _selectedHero == 'Все герои' || 
          heroName == _selectedHero;
      
      final player = match['players'].firstWhere(
        (p) => p['account_id'].toString() == _convertToAccountId(widget.steamId),
        orElse: () => {'player_slot': 0},
      );
      
      final playerSlot = player['player_slot'] ?? 0;
      final isRadiant = playerSlot < 128;
      final radiantWin = match['radiant_win'] ?? false;
      final isWin = (isRadiant && radiantWin) || (!isRadiant && !radiantWin);
      
      final resultMatch = _selectedResult == 'Все результаты' ||
          (_selectedResult == 'Победа' && isWin) ||
          (_selectedResult == 'Поражение' && !isWin);
      
      return heroMatch && resultMatch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('История матчей'),
        actions: [
          IconButton(
            icon: Icon(
              context.watch<ThemeProvider>().isDarkMode
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            onPressed: () {
              context.read<ThemeProvider>().toggleTheme();
            },
            tooltip: context.watch<ThemeProvider>().isDarkMode
                ? 'Светлая тема'
                : 'Темная тема',
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _matchesProvider?.forceRefresh(),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading || (_matchesProvider?.isLoading ?? false)
          ? const Center(child: CircularProgressIndicator())
          : (_matchesProvider?.matches.isEmpty ?? true)
              ? const Center(child: Text('Нет доступных матчей'))
              : Column(
                  children: [
                    if (_matchesProvider?.loadAllState == LoadAllMatchesState.loading)
                      LinearProgressIndicator(
                        value: _matchesProvider?.getLoadAllProgress() ?? 0.0,
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _filteredMatches.length,
                        itemBuilder: (context, index) {
                          final match = _filteredMatches[index];
                          return _buildMatchCard(match);
                        },
                      ),
                    ),
                  ],
                ),
      floatingActionButton: (_matchesProvider?.loadAllState != LoadAllMatchesState.loading && _matchesProvider != null)
          ? FloatingActionButton.extended(
              onPressed: () => _matchesProvider!.loadAllMatches(),
              label: const Text('Загрузить все матчи'),
              icon: const Icon(Icons.download),
            )
          : null,
    );
  }

  Widget _buildMatchCard(Map<String, dynamic> match) {
    final player = match['players'].firstWhere(
      (p) => p['account_id'].toString() == _convertToAccountId(widget.steamId),
      orElse: () => {
        'player_slot': 0,
        'kills': 0,
        'deaths': 0,
        'assists': 0,
        'gold_per_min': 0,
        'xp_per_min': 0,
        'hero_damage': 0,
        'hero_healing': 0,
        'net_worth': 0,
      },
    );

    final playerSlot = player['player_slot'] ?? 0;
    final isRadiant = playerSlot < 128;
    final radiantWin = match['radiant_win'] ?? false;
    final isWin = (isRadiant && radiantWin) || (!isRadiant && !radiantWin);

    final playerStats = match['player_stats'] ?? {};
    final kills = playerStats['kills'] ?? player['kills'] ?? 0;
    final deaths = playerStats['deaths'] ?? player['deaths'] ?? 0;
    final assists = playerStats['assists'] ?? player['assists'] ?? 0;
    final gpm = playerStats['gold_per_min'] ?? player['gold_per_min'] ?? 0;
    
    // Улучшенная обработка длительности
    final duration = match['duration'] ?? 0;
    print('Match duration raw: ${match['duration']}, processed: $duration'); // Отладочный вывод
    
    final startTime = DateTime.fromMillisecondsSinceEpoch((match['start_time'] ?? 0) * 1000);
    final heroId = player['hero_id'] ?? 0;

    // Форматируем длительность
    String formatDuration(int durationInSeconds) {
      if (durationInSeconds <= 0) return 'Неизвестно';
      final minutes = durationInSeconds ~/ 60;
      final seconds = durationInSeconds % 60;
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => _showMatchDetails(match),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  'https://cdn.dota2.com/apps/dota2/images/heroes/${_getHeroName(heroId)}_sb.png',
                  width: 64,
                  height: 64,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 64,
                      height: 64,
                      color: Colors.grey[300],
                      child: const Icon(Icons.error),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          match['hero_name'] ?? 'Неизвестный герой',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          isWin ? 'Победа' : 'Поражение',
                          style: TextStyle(
                            color: isWin ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${startTime.day}.${startTime.month}.${startTime.year} ${startTime.hour}:${startTime.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Команда: ${isRadiant ? 'Radiant' : 'Dire'}',
                            style: TextStyle(color: Colors.grey[600]),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Время: ${formatDuration(duration)}',
                            style: TextStyle(color: Colors.grey[600]),
                            textAlign: TextAlign.end,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'KDA: $kills/$deaths/$assists',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'GPM: $gpm',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getHeroName(int heroId) {
    // Используем только fallback маппинг с правильными именами
    final heroNames = {
      1: 'antimage',
      2: 'axe',
      3: 'bane',
      4: 'bloodseeker',
      5: 'crystal_maiden',
      6: 'drow_ranger',
      7: 'earthshaker',
      8: 'juggernaut',
      9: 'mirana',
      10: 'morphling',
      11: 'nevermore',
      12: 'phantom_lancer',
      13: 'puck',
      14: 'pudge',
      15: 'razor',
      16: 'sand_king',
      17: 'storm_spirit',
      18: 'sven',
      19: 'tiny',
      20: 'vengefulspirit',
      21: 'windrunner',
      22: 'zuus',
      23: 'kunkka',
      25: 'lina',
      26: 'lion',
      27: 'shadow_shaman',
      28: 'slardar',
      29: 'tidehunter',
      30: 'witch_doctor',
      31: 'lich',
      32: 'riki',
      33: 'enigma',
      34: 'tinker',
      35: 'sniper',
      36: 'necrolyte',
      37: 'warlock',
      38: 'beastmaster',
      39: 'queenofpain',
      40: 'venomancer',
      41: 'faceless_void',
      42: 'skeleton_king',
      43: 'death_prophet',
      44: 'phantom_assassin',
      45: 'pugna',
      46: 'templar_assassin',
      47: 'viper',
      48: 'luna',
      49: 'dragon_knight',
      50: 'dazzle',
      51: 'rattletrap',
      52: 'leshrac',
      53: 'furion',
      54: 'life_stealer',
      55: 'dark_seer',
      56: 'clinkz',
      57: 'omniknight',
      58: 'enchantress',
      59: 'huskar',
      60: 'night_stalker',
      61: 'broodmother',
      62: 'bounty_hunter',
      63: 'weaver',
      64: 'jakiro',
      65: 'batrider',
      66: 'chen',
      67: 'spectre',
      68: 'ancient_apparition',
      69: 'doom_bringer',
      70: 'ursa',
      71: 'spirit_breaker',
      72: 'gyrocopter',
      73: 'alchemist',
      74: 'invoker',
      75: 'silencer',
      76: 'obsidian_destroyer',
      77: 'lycan',
      78: 'brewmaster',
      79: 'shadow_demon',
      80: 'lone_druid',
      81: 'chaos_knight',
      82: 'meepo',
      83: 'treant',
      84: 'ogre_magi',
      85: 'undying',
      86: 'rubick',
      87: 'disruptor',
      88: 'nyx_assassin',
      89: 'naga_siren',
      90: 'keeper_of_the_light',
      91: 'wisp',
      92: 'visage',
      93: 'slark',
      94: 'medusa',
      95: 'troll_warlord',
      96: 'centaur',
      97: 'magnus',
      98: 'shredder',
      99: 'bristleback',
      100: 'tusk',
      101: 'skywrath_mage',
      102: 'abaddon',
      103: 'elder_titan',
      104: 'legion_commander',
      105: 'techies',
      106: 'ember_spirit',
      107: 'earth_spirit',
      108: 'abyssal_underlord',
      109: 'terrorblade',
      110: 'phoenix',
      111: 'oracle',
      112: 'winter_wyvern',
      113: 'arc_warden',
      114: 'monkey_king',
      119: 'dark_willow',
      120: 'pangolier',
      121: 'grimstroke',
      123: 'hoodwink',
      126: 'void_spirit',
      128: 'snapfire',
      129: 'mars',
      135: 'dawnbreaker',
      136: 'marci',
      137: 'primal_beast',
      138: 'muerta',
    };
    return heroNames[heroId] ?? 'unknown';
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Фильтры'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedHero,
              decoration: const InputDecoration(labelText: 'Герой'),
              items: _heroes.map((hero) {
                return DropdownMenuItem(
                  value: hero,
                  child: Text(hero),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedHero = value!;
                });
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedResult,
              decoration: const InputDecoration(labelText: 'Результат'),
              items: ['Все результаты', 'Победа', 'Поражение'].map((result) {
                return DropdownMenuItem(
                  value: result,
                  child: Text(result),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedResult = value!;
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _selectedHero = 'Все герои';
                _selectedResult = 'Все результаты';
              });
              Navigator.pop(context);
            },
            child: const Text('Сбросить'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  void _showMatchDetails(Map<String, dynamic> match) async {
    try {
      final matchId = match['match_id'];
      final response = await http.get(Uri.parse('https://api.opendota.com/api/matches/$matchId'));
      
      if (response.statusCode == 200) {
        final matchDetails = json.decode(response.body);
        print('Match details from OpenDota: $matchDetails');
        
        if (!mounted) return;
        
        showDialog(
          context: context,
          builder: (context) => Dialog(
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
                maxWidth: MediaQuery.of(context).size.width * 0.9,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Детали матча',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text('ID матча: ${matchDetails['match_id']}'),
                      Text('Режим игры: ${_getGameMode(matchDetails['game_mode'])}'),
                      Text('Тип лобби: ${_getLobbyType(matchDetails['lobby_type'])}'),
                      if (matchDetails['duration'] != null)
                        Text('Длительность: ${_formatDurationFromSeconds(matchDetails['duration'])}'),
                      const SizedBox(height: 16),
                      Text(
                        'Статистика игрока',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _buildPlayerStats(matchDetails),
                      const SizedBox(height: 16),
                      Text(
                        'Предметы',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _buildItems(matchDetails),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        throw Exception('Failed to load match details');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки деталей матча: $e')),
      );
    }
  }

  String _formatDurationFromSeconds(int durationInSeconds) {
    if (durationInSeconds <= 0) return 'Неизвестно';
    final minutes = durationInSeconds ~/ 60;
    final seconds = durationInSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _getGameMode(int? modeId) {
    final modes = {
      0: 'Неизвестный',
      1: 'Все выбирают',
      2: 'Случайный выбор',
      3: 'Одиночный выбор',
      4: 'Случайный выбор из пула',
      5: 'Все выбирают из пула',
      6: 'Случайный выбор из пула',
      7: 'Случайный выбор из пула',
      8: 'Случайный выбор из пула',
      9: 'Случайный выбор из пула',
      10: 'Случайный выбор из пула',
      11: 'Случайный выбор из пула',
      12: 'Случайный выбор из пула',
      13: 'Случайный выбор из пула',
      14: 'Случайный выбор из пула',
      15: 'Случайный выбор из пула',
      16: 'Случайный выбор из пула',
      17: 'Случайный выбор из пула',
      18: 'Случайный выбор из пула',
      19: 'Случайный выбор из пула',
      20: 'Случайный выбор из пула',
      21: 'Случайный выбор из пула',
      22: 'Случайный выбор из пула',
      23: 'Случайный выбор из пула',
    };
    return modes[modeId] ?? 'Неизвестный режим';
  }

  String _getLobbyType(int? lobbyId) {
    final lobbies = {
      -1: 'Неизвестный',
      0: 'Публичный',
      1: 'Практика',
      2: 'Турнир',
      3: 'Тренировка',
      4: 'Кооператив с ботами',
      5: 'Командный матчмейкинг',
      6: 'Соло матчмейкинг',
      7: 'Рейтинговая игра',
      8: 'Соло рейтинговая игра',
      9: 'Случайный выбор',
      10: 'Турнир',
      11: 'Турнир',
      12: 'Турнир',
      13: 'Турнир',
      14: 'Турнир',
      15: 'Турнир',
    };
    return lobbies[lobbyId] ?? 'Неизвестный тип лобби';
  }

  Widget _buildPlayerStats(Map<String, dynamic> match) {
    print('Match data: $match'); // Отладочный вывод
    
    final player = match['players'].firstWhere(
      (p) => p['account_id'].toString() == _convertToAccountId(widget.steamId),
      orElse: () => {
        'kills': 0,
        'deaths': 0,
        'assists': 0,
        'gold_per_min': 0,
        'xp_per_min': 0,
        'hero_damage': 0,
        'hero_healing': 0,
        'tower_damage': 0,
        'last_hits': 0,
        'denies': 0,
        'net_worth': 0,
      },
    );
    
    print('Player data: $player'); // Отладочный вывод

    // Проверяем, есть ли данные в player_stats
    final playerStats = match['player_stats'] ?? {};
    print('Player stats: $playerStats');

    // Определяем, откуда брать данные
    final stats = [
      {'label': 'Убийства', 'value': player["kills"] ?? playerStats['kills'] ?? 0},
      {'label': 'Смерти', 'value': player['deaths'] ?? playerStats['deaths'] ?? 0},
      {'label': 'Помощи', 'value': player['assists'] ?? playerStats['assists'] ?? 0},
      {'label': 'GPM', 'value': player['gold_per_min'] ?? playerStats['gold_per_min'] ?? 0},
      {'label': 'XPM', 'value': player['xp_per_min'] ?? playerStats['xp_per_min'] ?? 0},
      {'label': 'Урон героям', 'value': player['hero_damage'] ?? playerStats['hero_damage'] ?? 0},
      {'label': 'Лечение героев', 'value': player['hero_healing'] ?? playerStats['hero_healing'] ?? 0},
      {'label': 'Урон башням', 'value': player['tower_damage'] ?? playerStats['tower_damage'] ?? 0},
      {'label': 'Последние удары', 'value': player['last_hits'] ?? playerStats['last_hits'] ?? 0},
      {'label': 'Денай', 'value': player['denies'] ?? playerStats['denies'] ?? 0},
      {'label': 'Общая ценность', 'value': player['net_worth'] ?? playerStats['net_worth'] ?? 0}
    ];

    print('Final stats to display: $stats');

    return Column(
      children: stats.map((stat) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
            Text(stat['label'] as String),
            Text(stat['value'].toString()),
          ],
        ),
      )).toList(),
    );
  }

  Widget _buildItems(Map<String, dynamic> match) {
    print('Building items for match: $match'); // Отладочный вывод
    
    final player = match['players'].firstWhere(
      (p) => p['account_id'].toString() == _convertToAccountId(widget.steamId),
      orElse: () => {
        'item_0': 0,
        'item_1': 0,
        'item_2': 0,
        'item_3': 0,
        'item_4': 0,
        'item_5': 0,
        'backpack_0': 0,
        'backpack_1': 0,
        'backpack_2': 0,
        'item_neutral': 0,
        'aghanims_scepter': 0,
        'aghanims_shard': 0,
        'moonshard': 0,
      },
    );
    
    print('Player items: $player'); // Отладочный вывод

    // Проверяем, есть ли данные в player_stats
    final playerStats = match['player_stats'] ?? {};
    print('Player stats items: $playerStats');

    // Основные предметы (6 слотов)
    final mainItems = [
      player['item_0'] ?? playerStats['item_0'] ?? 0,
      player['item_1'] ?? playerStats['item_1'] ?? 0,
      player['item_2'] ?? playerStats['item_2'] ?? 0,
      player['item_3'] ?? playerStats['item_3'] ?? 0,
      player['item_4'] ?? playerStats['item_4'] ?? 0,
      player['item_5'] ?? playerStats['item_5'] ?? 0,
    ];

    print('Main items to display: $mainItems');

    // Дополнительные предметы - обрабатываем специально
    final neutralItem = player['item_neutral'] ?? playerStats['item_neutral'] ?? 0;
    final aghanimsScepter = player['aghanims_scepter'] ?? playerStats['aghanims_scepter'] ?? 0;
    final aghanimsShard = player['aghanims_shard'] ?? playerStats['aghanims_shard'] ?? 0;
    final moonshard = player['moonshard'] ?? playerStats['moonshard'] ?? 0;

    print('Special items - neutral: $neutralItem, scepter: $aghanimsScepter, shard: $aghanimsShard, moonshard: $moonshard');

    Widget _buildItemSlot(int? itemId, {String? specialItemName}) {
      // Для специальных предметов используем особую логику
      if (specialItemName != null) {
        if (itemId == 1) {
          // Отображаем специальный предмет
          return Container(
            width: 64,
            height: 48,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Image.network(
              'https://cdn.dota2.com/apps/dota2/images/items/${specialItemName}_lg.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                print('Ошибка загрузки специального предмета $specialItemName: $error');
                return Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.error),
                );
              },
            ),
          );
        } else {
          // Пустой слот для специального предмета
          return Container(
            width: 64,
            height: 48,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
              color: Colors.grey[200],
            ),
          );
        }
      }

      // Обычная логика для основных предметов
      if (itemId == null || itemId == 0) {
        return Container(
          width: 64,
          height: 48,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(4),
            color: Colors.grey[200],
          ),
        );
      }

      final itemName = _getItemName(itemId);
      print('Loading item: $itemId -> $itemName'); // Отладочный вывод
      
      return Container(
        width: 64,
        height: 48,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Image.network(
          'https://cdn.dota2.com/apps/dota2/images/items/${itemName}_lg.png',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            print('Ошибка загрузки предмета $itemId ($itemName): $error');
            return Container(
              color: Colors.grey[300],
              child: const Icon(Icons.error),
            );
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Основные предметы', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: mainItems.map((itemId) => _buildItemSlot(itemId)).toList(),
        ),
        const SizedBox(height: 16),
        const Text('Дополнительные предметы', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildItemSlot(neutralItem), // Нейтральный предмет (обычный ID)
            _buildItemSlot(aghanimsScepter, specialItemName: 'ultimate_scepter'), // Съеденный аганим
            _buildItemSlot(aghanimsShard, specialItemName: 'aghanims_shard'), // Аганим шард  
            _buildItemSlot(moonshard, specialItemName: 'moon_shard'), // Съеденный муншард
          ],
        ),
      ],
    );
  }

  String _getItemName(int itemId) {
    // Логируем каждый запрос предмета для создания правильного маппинга
    print('Requesting item name for ID: $itemId');
    
    // Актуальный маппинг на основе OpenDota API
    final itemNames = {
      // Основные предметы
      1: 'blink',
      2: 'blades_of_attack',
      3: 'broadsword',
      4: 'chainmail',
      5: 'claymore',
      6: 'helm_of_iron_will',
      7: 'javelin',
      8: 'mithril_hammer',
      9: 'platemail',
      10: 'quarterstaff',
      11: 'quelling_blade',
      12: 'ring_of_protection',
      13: 'gauntlets',
      14: 'slippers',
      15: 'mantle',
      16: 'branches',
      17: 'belt_of_strength',
      18: 'boots_of_elves',
      19: 'robe',
      20: 'circlet',
      21: 'ogre_axe',
      22: 'blade_of_alacrity',
      23: 'staff_of_wizardry',
      24: 'ultimate_orb',
      25: 'gloves',
      26: 'lifesteal',
      27: 'ring_of_regen',
      28: 'sobi_mask',
      29: 'boots',
      30: 'gem',
      31: 'cloak',
      32: 'talisman_of_evasion',
      33: 'cheese',
      34: 'magic_stick',
      35: 'recipe_magic_wand',
      36: 'magic_wand',
      37: 'ghost',
      38: 'clarity',
      39: 'flask',
      40: 'dust',
      41: 'bottle',
      42: 'ward_observer',
      43: 'ward_sentry',
      44: 'tango',
      45: 'courier',
      46: 'tpscroll',
      47: 'recipe_travel_boots',
      48: 'travel_boots',
      49: 'recipe', //phase_boots  сру
      50: 'phase_boots',
      51: 'demon_edge',
      52: 'eagle',
      53: 'reaver',
      54: 'relic',
      55: 'hyperstone',
      56: 'ring_of_health',
      57: 'void_stone',
      58: 'mystic_staff',
      59: 'energy_booster',
      60: 'point_booster',
      61: 'vitality_booster',
      62: 'recipe_power_treads',
      63: 'power_treads',
      64: 'recipe_hand_of_midas',
      65: 'hand_of_midas',
      66: 'recipe_oblivion_staff',
      67: 'oblivion_staff',
      68: 'recipe_pers', //pusto
      69: 'pers',
      70: 'recipe_poor_mans_shield', //pusto
      71: 'poor_mans_shield',
      72: 'recipe_bracer',
      73: 'bracer',
      74: 'recipe_wraith_band',
      75: 'wraith_band',
      76: 'recipe_null_talisman',
      77: 'null_talisman',
      78: 'recipe_mekansm',
      79: 'mekansm',
      80: 'recipe_vladmir',
      81: 'vladmir',
      84: 'flying_courier',
      86: 'buckler',
      87: 'recipe_ring_of_basilius',
      88: 'ring_of_basilius',
      89: 'recipe_pipe',
      90: 'pipe',
      91: 'recipe_urn_of_shadows',
      92: 'urn_of_shadows',
      93: 'recipe_headdress',
      94: 'headdress',
      95: 'recipe_sheepstick',
      96: 'sheepstick',
      97: 'recipe_orchid',
      98: 'orchid',
      99: 'recipe_cyclone',
      100: 'cyclone',
      101: 'recipe_force_staff',
      102: 'force_staff',
      103: 'recipe_dagon',
      104: 'dagon',
      105: 'recipe_necronomicon',
      106: 'necronomicon',
      107: 'necronomicon_1',
      108: 'ultimate_scepter',
      109: 'recipe_refresher',
      110: 'refresher',
      111: 'recipe_assault',
      112: 'assault', //recipe_black_king_bar
      113: 'recipe_heart',
      114: 'heart',
      115: 'recipe_black_king_bar', //recipe_shivas_guard
      116: 'black_king_bar',
      117: 'aegis',
      118: 'recipe_shivas_guard', //bloodstone
      119: 'shivas_guard', //receipe_sphere
      120: 'sphere', //pusto
      121: 'bloodstone',
      122: 'recipe_sphere',
      123: 'sphere',
      124: 'blade_mail', //pusto
      125: 'vanguard',
      126: 'recipe_blade_mail',
      127: 'blade_mail',
      128: 'hood_of_defiance', //pusto
      129: 'soul_booster',
      130: 'rapier',
      131: 'hood_of_defiance',
      132: 'monkey_king_bar',//pusto
      133: 'rapier',
      134: 'recipe_monkey_king_bar',
      135: 'monkey_king_bar',
      136: 'butterfly',//pusto
      137: 'radiance',
      138: 'greater_crit',///pusto
      139: 'butterfly',
      140: 'recipe_greater_crit',
      141: 'greater_crit',
      142: 'recipe_basher',
      143: 'basher',
      144: 'recipe_bfury',
      145: 'bfury',
      146: 'recipe_manta',
      147: 'manta',
      148: 'recipe_lesser_crit',
      149: 'lesser_crit',
      150: 'recipe_armlet',
      151: 'armlet',
      152: 'invis_sword',
      153: 'satanic',//pusto
      154: 'sange_and_yasha',
      155: 'mjollnir', //pusto
      156: 'satanic',
      157: 'recipe_mjollnir',
      158: 'mjollnir',
      159: 'sange',//pusto
      160: 'skadi',
      161: 'recipe_sange',
      162: 'sange',
      163: 'recipe_helm_of_the_dominator',
      164: 'helm_of_the_dominator',
      165: 'desolator',//pusto
      166: 'maelstrom',
      167: 'yasha', //pusto
      168: 'desolator',
      169: 'recipe_yasha',
      170: 'yasha',
      171: 'diffusal_blade',//pusto
      172: 'mask_of_madness',
      173: 'recipe_diffusal_blade',
      174: 'diffusal_blade',
      175: 'recipe_ethereal_blade',
      176: 'ethereal_blade',
      177: 'recipe_soul_ring',
      178: 'soul_ring',
      179: 'recipe_arcane_boots',
      180: 'arcane_boots',
      181: 'orb_of_venom',
      182: 'stout_shield',
      183: 'recipe_medallion_of_courage',//pusto
      184: 'recipe',
      185: 'ancient_janggo',
      186: 'recipe_veil_of_discord',//pusto
      187: 'medallion_of_courage',
      188: 'smoke_of_deceit',
      189: 'recipe',
      190: 'veil_of_discord',
      191: 'necronomicon_3',//pusto
      192: 'recipe_dagon_2',//pusto
      193: 'necronomicon_2',
      194: 'necronomicon_3',
      195: 'dagon_3',//pusto
      196: 'diffusal_blade_2',
      197: 'recipe_dagon_4',//pusto
      198: 'dagon_4',//pusto
      199: 'recipe_dagon_5',//pusto
      200: 'dagon_5',//pusto
      201: 'dagon_2',
      202: 'dagon_3',
      203: 'dagon_4',
      204: 'dagon_5',
      205: 'recipe_rod_of_atos',
      206: 'rod_of_atos',
      207: 'recipe_abyssal_blade',
      208: 'abyssal_blade',
      209: 'recipe_heavens_halberd',
      210: 'heavens_halberd',
      211: 'shadow_amulet',//pusto
      212: 'ring_of_aquila',
      213: 'silver_edge',//pusto
      214: 'tranquil_boots',
      215: 'shadow_amulet',
      216: 'enchanted_mango',
      217: 'lotus_orb',//pusto
      218: 'ward_dispenser',
      219: 'meteor_hammer',//pusto
      220: 'travel_boots_2',
      221: 'recipe_lotus_orb',
      222: 'recipe_meteor_hammer',
      223: 'meteor_hammer',
      224: 'recipe_linken_sphere',//pusto
      225: 'nullifier',
      226: 'lotus_orb',
      227: 'recipe_solar_crest',
      228: 'recipe_kaya',//pusto
      229: 'solar_crest',
      230: 'recipe_guardian_greaves',
      231: 'guardian_greaves',
      232: 'aether_lens',
      233: 'recipe_aether_lens',
      234: 'recipe_dragon_lance',
      235: 'octarine_core',
      236: 'dragon_lance',
      237: 'faerie_fire',
      238: 'recipe_iron_talon',
      239: 'iron_talon',
      240: 'blight_stone',
      241: 'tango_single',
      242: 'crimson_guard',
      243: 'recipe_crimson_guard',
      244: 'wind_lace',
      245: 'recipe_bloodthorn',
      246: 'blight_stone',//pusto
      247: 'moon_shard',
      248: 'recipe_silver_edge',
      249: 'silver_edge',
      250: 'bloodthorn',
      251: 'recipe_bloodthorn',//pusto
      252: 'echo_sabre',
      253: 'recipe_glimmer_cape',
      254: 'glimmer_cape',
      255: 'recipe_aeon_disk',
      256: 'aeon_disk',
      257: 'tome_of_knowledge',
      258: 'recipe_kaya',
      259: 'kaya',
      260: 'refresher_shard',
      261: 'crown',
      262: 'recipe_hurricane_pike',
      263: 'hurricane_pike',
      264: 'river_painter',//pusto
      265: 'infused_raindrop',
      266: 'recipe_spirit_vessel',
      267: 'spirit_vessel',
      268: 'recipe_holy_locket',
      269: 'holy_locket',
      270: 'recipe_ultimate_scepter_2',
      271: 'ultimate_scepter_2',
      272: 'recipe_kaya_and_sange',//pusto
      273: 'kaya_and_sange',
      274: 'recipe_yasha_and_kaya',//pusto
      275: 'recipe_trident',
      276: 'combo_breaker',
      277: 'yasha_and_kaya',
      278: 'travel_boots_3',//pusto
      279: 'ring_of_tarrasque',
      286: 'flying_courier',
      287: 'keen_optic',
      288: 'grove_bow',
      289: 'quickening_charm',
      290: 'philosophers_stone',
      291: 'force_boots',
      292: 'desolator_2',
      293: 'phoenix_ash',
      294: 'seer_stone',
      295: 'greater_mango',
      297: 'vampire_fangs',
      298: 'craggy_coat',
      299: 'greater_faerie_fire',
      300: 'timeless_relic',
      301: 'mirror_shield',
      302: 'elixer',
      304: 'ironwood_tree',
      305: 'royal_jelly',
      306: 'pupils_gift',
      307: 'tome_of_aghanim',
      308: 'repair_kit',
      309: 'mind_breaker',
      310: 'third_eye',
      311: 'spell_prism',
      312: 'horizon',
      313: 'fusion_rune',
      314: 'recipe_fusion_rune',
      325: 'princes_knife',
      326: 'spider_legs',
      327: 'helm_of_the_undying',
      328: 'mango_tree',
      329: 'recipe_mango_tree',
      330: 'witless_shako',
      331: 'vambrace',
      334: 'imp_claw',
      335: 'flicker',
      336: 'spy_gadget',
      349: 'arcane_ring',
      354: 'ocean_heart',
      355: 'broom_handle',
      356: 'trusty_shovel',
      357: 'nether_shawl',
      358: 'dragon_scale',
      359: 'essence_ring',
      360: 'clumsy_net',
      361: 'enchanted_quiver',
      362: 'ninja_gear',
      363: 'illusionsts_cape',
      364: 'havoc_hammer',
      365: 'panic_button',
      366: 'apex',
      367: 'ballista',
      368: 'woodland_striders',
      369: 'firmament_horn',
      370: 'dagger_of_ristul',
      371: 'recipe_dagger_of_ristul',
      372: 'recipe_ballista',
      373: 'dimensional_doorway',
      374: 'ex_machina',
      375: 'faded_broach',
      376: 'paladin_sword',
      377: 'minotaur_horn',
      378: 'orb_of_destruction',
      379: 'the_leveller',
      381: 'titan_sliver',
      473: 'voodoo_mask',
      485: 'blitz_knuckles',
      533: 'recipe_witch_blade',
      534: 'witch_blade',
      565: 'chipped_vest',
      566: 'wizard_glass',
      569: 'orb_of_corrosion',
      570: 'gloves_of_travel',
      571: 'trickster_cloak',
      573: 'elven_tunic',
      574: 'cloak_of_flames',
      575: 'venom_gland',
      576: 'gladiator_helm',
      577: 'possessed_mask',
      578: 'ancient_perseverance',
      582: 'oakheart',
      585: 'stormcrafter',
      588: 'overflowing_elixir',
      589: 'mysterious_hat',
      593: 'fluffy_hat',
      596: 'falcon_blade',
      598: 'mage_slayer',
      599: 'recipe_falcon_blade',
      609: 'aghanims_shard',
      610: 'wind_waker',
      612: 'recipe_wind_waker',
      633: 'recipe',
      635: 'helm_of_the_overlord',
      637: 'star_mace',
      638: 'penta_edged_sword',
      655: 'grandmasters_glaive',
      674: 'warhammer',
      675: 'psychic_headband',
      676: 'ceremonial_robe',
      677: 'book_of_shadows',
      678: 'giants_ring',
      679: 'vengeances_shadow',
      680: 'bullwhip',
      686: 'quicksilver_amulet',
      691: 'recipe',
      692: 'eternal_shroud',
      725: 'aghanims_shard_roshan',
      731: 'satchel',
      824: 'assassins_dagger',
      825: 'ascetic_cap',
      826: 'sample_picker',
      827: 'icarus_wings',
      828: 'misericorde',
      829: 'force_field',
      830: 'recipe_force_field',
      834: 'black_powder_bag',
      835: 'paintball',
      836: 'light_robes',
      837: 'heavy_blade',
      838: 'unstable_wand',
      839: 'fortitude_ring',
      840: 'pogo_stick',
      849: 'mechanical_arm',
      907: 'recipe',
      908: 'wraith_pact',
      910: 'recipe',
      911: 'revenants_brooch',
      930: 'recipe',
      931: 'boots_of_bearing',
      938: 'slime_vial',
      939: 'harpoon',
      940: 'wand_of_the_brine',
      945: 'seeds_of_serenity',
      946: 'lance_of_pursuit',
      947: 'occult_bracelet',
      948: 'tome_of_omniscience',
      949: 'ogre_seal_totem',
      950: 'defiant_shell',
      968: 'arcane_scout',
      969: 'barricade',
      990: 'eye_of_the_vizier',
      998: 'manacles_of_power',
      1000: 'bottomless_chalice',
      1017: 'wand_of_sanctitude',
      1021: 'river_painter',
      1022: 'river_painter2',
      1023: 'river_painter3',
      1024: 'river_painter4',
      1025: 'river_painter5',
      1026: 'river_painter6',
      1027: 'river_painter7',
      1028: 'mutation_tombstone',
      1029: 'super_blink',
      1096: 'recipe',
      1097: 'disperser',
      1601: 'crippling_crossbow',
      1608: 'pyrrhic_cloak',	
      1605: 'serrated_shiv',	
      // Новые blink предметы
      600: 'overwhelming_blink',
      603: 'swift_blink',
      604: 'arcane_blink',
      606: 'recipe_arcane_blink',
      607: 'recipe_swift_blink',
      608: 'recipe_overwhelming_blink',
      
      // Нейтральные предметы (основные)
      1565: 'keen_optic',
      1566: 'grove_bow', 
      1567: 'quickening_charm',
      1568: 'philosophers_stone',
      1569: 'force_boots',
      1570: 'desolator_2',
      1571: 'phoenix_ash',
      1572: 'seer_stone',
      1573: 'greater_faerie_fire',
      1574: 'vampire_fangs',
      1575: 'craggy_coat',
      1576: 'greater_mango',
      1577: 'enchanted_quiver',
      1578: 'ninja_gear',
      1579: 'illusionsts_cape',
      1580: 'havoc_hammer',
      1581: 'panic_button',
      1582: 'apex',
      1583: 'ballista',
      1584: 'woodland_striders',
      1585: 'firmament_horn',
      1586: 'dagger_of_ristul',
      1635: 'faded_broach',
      1636: 'paladin_sword',
      1637: 'minotaur_horn',
      1638: 'orb_of_destruction',
      1639: 'the_leveller',
      1640: 'titan_sliver',
      1641: 'elven_tunic',
      1642: 'cloak_of_flames',
      1643: 'giant_maul',
      1644: 'divine_regalia',
      1645: 'divine_regalia_broken',
      1646: 'circlet_of_the_flayed_twins',
      1647: 'enhancement_fierce',
      1648: 'enhancement_dominant',
      1649: 'enhancement_restorative',
      1650: 'enhancement_thick',
      1651: 'enhancement_curious',
      1652: 'furion_gold_bag',
    };
    
    final itemName = itemNames[itemId] ?? 'unknown_item_$itemId';
    print('Item $itemId mapped to: $itemName');
    return itemName;
  }

  String _convertToAccountId(String steamId) {
    try {
      final steamIdNum = BigInt.parse(steamId);
      final accountId = (steamIdNum - BigInt.from(76561197960265728)).toString();
      print('Converted Steam ID $steamId to account ID $accountId'); // Отладочный вывод
      return accountId;
    } catch (e) {
      print('Error converting Steam ID: $e'); // Отладочный вывод
      return steamId;
    }
  }

  @override
  void dispose() {
    _matchesProvider?.dispose();
    super.dispose();
  }
} 