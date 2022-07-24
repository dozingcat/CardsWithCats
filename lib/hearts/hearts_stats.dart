import 'package:cards_with_cats/hearts/hearts.dart';

class HeartsStats {
  final int numMatches;
  final int matchesWon;
  final int matchesTied;
  final int totalMatchPointsTaken;
  final int numRounds;
  final int numRoundsWithJdRule;
  final int totalRoundPointsTakenWithoutJdRule;
  final int totalRoundPointsTakenWithJdRule;
  final int numQsTaken;
  final int numJdTaken;
  final int numMoonShoots;
  final int numOpponentMoonShoots;

  HeartsStats({
    required this.numMatches,
    required this.matchesWon,
    required this.matchesTied,
    required this.totalMatchPointsTaken,
    required this.numRounds,
    required this.numRoundsWithJdRule,
    required this.totalRoundPointsTakenWithoutJdRule,
    required this.totalRoundPointsTakenWithJdRule,
    required this.numQsTaken,
    required this.numJdTaken,
    required this.numMoonShoots,
    required this.numOpponentMoonShoots,
  });

  static HeartsStats empty() {
    return HeartsStats(
        numMatches: 0,
        matchesWon: 0,
        matchesTied: 0,
        totalMatchPointsTaken: 0,
        numRounds: 0,
        numRoundsWithJdRule: 0,
        totalRoundPointsTakenWithoutJdRule: 0,
        totalRoundPointsTakenWithJdRule: 0,
        numQsTaken: 0,
        numJdTaken: 0,
        numMoonShoots: 0,
        numOpponentMoonShoots: 0,
    );
  }

  HeartsStats updateFromRound(HeartsRound round) {
    if (!round.isOver()) {
      throw Exception("Hearts round is not over");
    }
    bool usingJD = round.rules.jdMinus10;
    final scores = round.pointsTaken();
    int? shooter = moonShooter(round.previousTricks);
    bool tookQueen = round.previousTricks.any((t) => t.winner == 0 && t.cards.contains(queenOfSpades));
    bool tookJack = usingJD && round.previousTricks.any((t) => t.winner == 0 && t.cards.contains(jackOfDiamonds));

    return HeartsStats(
      numMatches: numMatches,
      matchesWon: matchesWon,
      matchesTied: matchesTied,
      totalMatchPointsTaken: totalMatchPointsTaken,
      numRounds: numRounds + 1,
      numRoundsWithJdRule: numRoundsWithJdRule + (usingJD ? 1 : 0),
      totalRoundPointsTakenWithoutJdRule: totalRoundPointsTakenWithoutJdRule + (usingJD ? 0 : scores[0]),
      totalRoundPointsTakenWithJdRule: totalRoundPointsTakenWithJdRule + (usingJD ? scores[0] : 0),
      numQsTaken: numQsTaken + (tookQueen ? 1 : 0),
      numJdTaken: numJdTaken + (tookJack ? 1 : 0),
      numMoonShoots: numMoonShoots + (shooter == 0 ? 1 : 0),
      numOpponentMoonShoots: numOpponentMoonShoots + (shooter != null && shooter != 0 ? 1 : 0),
    );
  }

  HeartsStats updateFromMatch(HeartsMatch match) {
    if (!match.isMatchOver()) {
      throw Exception("Hearts match is not over");
    }
    final winners = match.winningPlayers();
    bool won = (winners == [0]);
    bool tied = (winners.length > 1 && winners.contains(0));
    final scores = match.scores;

    return HeartsStats(
      numMatches: numMatches + 1,
      matchesWon: matchesWon + (won ? 1 : 0),
      matchesTied: matchesTied + (tied ? 1 : 0),
      totalMatchPointsTaken: totalMatchPointsTaken + scores[0],
      numRounds: numRounds,
      numRoundsWithJdRule: numRoundsWithJdRule,
      totalRoundPointsTakenWithoutJdRule: totalRoundPointsTakenWithoutJdRule,
      totalRoundPointsTakenWithJdRule: totalRoundPointsTakenWithJdRule,
      numQsTaken: numQsTaken,
      numJdTaken: numJdTaken,
      numMoonShoots: numMoonShoots,
      numOpponentMoonShoots: numOpponentMoonShoots,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "__version__": 1,
      "numMatches": numMatches,
      "matchesWon": matchesWon,
      "matchesTied": matchesTied,
      "totalMatchPointsTaken": totalMatchPointsTaken,
      "numRounds": numRounds,
      "numRoundsWithJdRule": numRoundsWithJdRule,
      "totalRoundPointsTakenWithoutJdRule": totalRoundPointsTakenWithoutJdRule,
      "totalRoundPointsTakenWithJdRule": totalRoundPointsTakenWithJdRule,
      "numQsTaken": numQsTaken,
      "numJdTaken": numJdTaken,
      "numMoonShoots": numMoonShoots,
      "numOpponentMoonShoots": numOpponentMoonShoots,
    };
  }

  static HeartsStats fromJson(final Map<String, dynamic> json) {
    return HeartsStats(
      numMatches: json["numMatches"],
      matchesWon: json["matchesWon"],
      matchesTied: json["matchesTied"],
      totalMatchPointsTaken: json["totalMatchPointsTaken"],
      numRounds: json["numRounds"],
      numRoundsWithJdRule: json["numRoundsWithJdRule"],
      totalRoundPointsTakenWithoutJdRule: json["totalRoundPointsTakenWithoutJdRule"],
      totalRoundPointsTakenWithJdRule: json["totalRoundPointsTakenWithJdRule"],
      numQsTaken: json["numQsTaken"],
      numJdTaken: json["numJdTaken"],
      numMoonShoots: json["numMoonShoots"],
      numOpponentMoonShoots: json["numOpponentMoonShoots"],
    );
  }
}
