import 'package:cards_with_cats/ohhell/ohhell.dart';

class OhHellStats {
  final int numMatches;
  final int matchesWon;
  final int matchesTied;
  final int numRounds;
  final int numBidsMade;

  OhHellStats({
    required this.numMatches,
    required this.matchesWon,
    required this.matchesTied,
    required this.numRounds,
    required this.numBidsMade,
  });

  static OhHellStats empty() {
    return OhHellStats(
      numMatches: 0,
      matchesWon: 0,
      matchesTied: 0,
      numRounds: 0,
      numBidsMade: 0,
    );
  }

  OhHellStats updateFromRound(OhHellRound round) {
    if (!round.isOver()) {
      throw Exception("Round is not over");
    }
    final scores = round.pointsTaken();
    final playerMadeBid = (scores[0].madeBidPoints > 0);
    return OhHellStats(
      numMatches: numMatches,
      matchesWon: matchesWon,
      matchesTied: matchesTied,
      numRounds: numRounds + 1,
      numBidsMade: numBidsMade + (playerMadeBid ? 1 : 0),
    );
  }

  OhHellStats updateFromMatch(OhHellMatch match) {
    final winners = match.winningPlayers();
    bool won = (winners.length == 1 && winners[0] == 0);
    bool tied = (winners.length > 1 && winners.contains(0));
    return OhHellStats(
      numMatches: numMatches + 1,
      matchesWon: matchesWon + (won ? 1 : 0),
      matchesTied: matchesTied + (tied ? 1 : 0),
      numRounds: numRounds,
      numBidsMade: numBidsMade,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "__version__": 1,
      "numMatches": numMatches,
      "matchesWon": matchesWon,
      "matchesTied": matchesTied,
      "numRounds": numRounds,
      "numBidsMade": numBidsMade,
    };
  }

  static OhHellStats fromJson(final Map<String, dynamic> json) {
    return OhHellStats(
      numMatches: json["numMatches"],
      matchesWon: json["matchesWon"],
      matchesTied: json["matchesTied"],
      numRounds: json["numRounds"],
      numBidsMade: json["numBidsMade"],
    );
  }
}
