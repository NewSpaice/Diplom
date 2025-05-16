class Match {
  final String matchId;
  final DateTime startTime;
  final int duration;
  final String heroName;
  final List<String> items;
  final bool isWin;
  final int kills;
  final int deaths;
  final int assists;
  final int gpm;
  final int xpm;

  Match({
    required this.matchId,
    required this.startTime,
    required this.duration,
    required this.heroName,
    required this.items,
    required this.isWin,
    required this.kills,
    required this.deaths,
    required this.assists,
    required this.gpm,
    required this.xpm,
  });

  factory Match.fromJson(Map<String, dynamic> json) {
    return Match(
      matchId: json['match_id'].toString(),
      startTime: DateTime.fromMillisecondsSinceEpoch(json['start_time'] * 1000),
      duration: json['duration'],
      heroName: json['hero_name'],
      items: List<String>.from(json['items']),
      isWin: json['radiant_win'] == (json['player_slot'] < 128),
      kills: json['kills'],
      deaths: json['deaths'],
      assists: json['assists'],
      gpm: json['gold_per_min'],
      xpm: json['xp_per_min'],
    );
  }
} 