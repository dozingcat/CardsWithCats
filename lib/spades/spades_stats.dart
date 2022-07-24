import 'package:cards_with_cats/spades/spades.dart';

class SpadesStats {
  final int numMatches;
  final int matchesWon;
  final int matchesTied;
  final int totalMatchPoints;
  final int numBagPenalties;
  final int numRounds;
  final int totalRoundPoints;
  final int numBidsAttempted;
  final int numBidsMade;
  final int totalBids;
  final int totalBagsTaken;
  final int numNilBidsAttempted;
  final int numNilBidsMade;
  final int totalOpponentMatchPoints;
  final int totalOpponentRoundPoints;
  final int numOpponentBidsAttempted;
  final int numOpponentBidsMade;
  final int totalOpponentBids;
  final int totalOpponentBagsTaken;
  final int numOpponentNilBidsAttempted;
  final int numOpponentNilBidsMade;

  SpadesStats({
    required this.numMatches,
    required this.matchesWon,
    required this.matchesTied,
    required this.totalMatchPoints,
    required this.numBagPenalties,
    required this.numRounds,
    required this.totalRoundPoints,
    required this.numBidsAttempted,
    required this.numBidsMade,
    required this.totalBids,
    required this.totalBagsTaken,
    required this.numNilBidsAttempted,
    required this.numNilBidsMade,
    required this.totalOpponentMatchPoints,
    required this.totalOpponentRoundPoints,
    required this.numOpponentBidsAttempted,
    required this.numOpponentBidsMade,
    required this.totalOpponentBids,
    required this.totalOpponentBagsTaken,
    required this.numOpponentNilBidsAttempted,
    required this.numOpponentNilBidsMade,
  });

  static SpadesStats empty() {
    return SpadesStats(
        numMatches: 0,
        matchesWon: 0,
        matchesTied: 0,
        totalMatchPoints: 0,
        numBagPenalties: 0,
        numRounds: 0,
        totalRoundPoints: 0,
        numBidsAttempted: 0,
        numBidsMade: 0,
        totalBids: 0,
        totalBagsTaken: 0,
        numNilBidsAttempted: 0,
        numNilBidsMade: 0,
        totalOpponentMatchPoints: 0,
        totalOpponentRoundPoints: 0,
        numOpponentBidsAttempted: 0,
        numOpponentBidsMade: 0,
        totalOpponentBids: 0,
        totalOpponentBagsTaken: 0,
        numOpponentNilBidsAttempted: 0,
        numOpponentNilBidsMade: 0,
    );
  }

  SpadesStats updateFromRound(SpadesRound round) {
    if (!round.isOver()) {
      throw Exception("Spades round is not over");
    }
    final scores = round.pointsTaken();
    final playerScore = scores[0];
    final oppScore = scores[1];
    final playerBid = round.players[0].bid! + round.players[2].bid!;
    final oppBid = round.players[1].bid! + round.players[3].bid!;
    final playerNil = round.players[0].bid == 0 || round.players[2].bid == 0;
    final oppNil = round.players[1].bid == 0 || round.players[3].bid == 0;
    return SpadesStats(
      numMatches: numMatches,
      matchesWon: matchesWon,
      matchesTied: matchesTied,
      totalMatchPoints: totalMatchPoints,
      numBagPenalties: numBagPenalties + (playerScore.overtrickPenalty < 0 ? 1 : 0),
      numRounds: numRounds + 1,
      totalRoundPoints: totalRoundPoints + playerScore.totalRoundPoints,
      numBidsAttempted: numBidsAttempted + (playerBid > 0 ? 1 : 0),
      numBidsMade: numBidsMade + (playerScore.successfulBidPoints > 0 ? 1 : 0),
      totalBids: totalBids + playerBid,
      totalBagsTaken: playerScore.overtricks,
      numNilBidsAttempted: numNilBidsAttempted + (playerNil ? 1 : 0),
      numNilBidsMade: numNilBidsMade + (playerScore.successfulNilPoints > 0 ? 1 : 0),
      totalOpponentMatchPoints: totalOpponentMatchPoints,
      totalOpponentRoundPoints: totalOpponentRoundPoints + oppScore.totalRoundPoints,
      numOpponentBidsAttempted: numOpponentBidsAttempted + (oppBid > 0 ? 1 : 0),
      numOpponentBidsMade: numOpponentBidsMade + (oppScore.successfulBidPoints > 0 ? 1 : 0),
      totalOpponentBids: totalOpponentBids + oppBid,
      totalOpponentBagsTaken: totalOpponentBagsTaken + oppScore.overtricks,
      numOpponentNilBidsAttempted: numOpponentNilBidsAttempted + (oppNil ? 1 : 0),
      numOpponentNilBidsMade: numOpponentNilBidsMade + (oppScore.successfulNilPoints > 0 ? 1 : 0),
    );
  }

  SpadesStats updateFromMatch(SpadesMatch match) {
    if (!match.isMatchOver()) {
      throw Exception("Spades match is not over");
    }
    final winner = match.winningTeam();
    final scores = match.scores;
    return SpadesStats(
      numMatches: numMatches + 1,
      matchesWon: matchesWon + (winner == 0 ? 1 : 0),
      matchesTied: matchesTied,
      totalMatchPoints: totalMatchPoints + scores[0],
      numBagPenalties: numBagPenalties,
      numRounds: numRounds,
      totalRoundPoints: totalRoundPoints,
      numBidsAttempted: numBidsAttempted,
      numBidsMade: numBidsMade,
      totalBids: totalBids,
      totalBagsTaken: totalBagsTaken,
      numNilBidsAttempted: numNilBidsAttempted,
      numNilBidsMade: numNilBidsMade,
      totalOpponentMatchPoints: totalOpponentMatchPoints + scores[1],
      totalOpponentRoundPoints: totalOpponentRoundPoints,
      numOpponentBidsAttempted: numOpponentBidsAttempted,
      numOpponentBidsMade: numOpponentBidsMade,
      totalOpponentBids: totalOpponentBids,
      totalOpponentBagsTaken: totalOpponentBagsTaken,
      numOpponentNilBidsAttempted: numOpponentNilBidsAttempted,
      numOpponentNilBidsMade: numOpponentNilBidsMade,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "__version__": 1,
      "numMatches": numMatches,
      "matchesWon": matchesWon,
      "matchesTied": matchesTied,
      "totalMatchPoints": totalMatchPoints,
      "numBagPenalties": numBagPenalties,
      "numRounds": numRounds,
      "totalRoundPoints": totalRoundPoints,
      "numBidsAttempted": numBidsAttempted,
      "numBidsMade": numBidsMade,
      "totalBids": totalBids,
      "totalBagsTaken": totalBagsTaken,
      "numNilBidsAttempted": numNilBidsAttempted,
      "numNilBidsMade": numNilBidsMade,
      "totalOpponentRoundPoints": totalOpponentRoundPoints,
      "totalOpponentMatchPoints": totalOpponentMatchPoints,
      "numOpponentBidsAttempted": numOpponentBidsAttempted,
      "numOpponentBidsMade": numOpponentBidsMade,
      "totalOpponentBids": totalOpponentBids,
      "totalOpponentBagsTaken": totalOpponentBagsTaken,
      "numOpponentNilBidsAttempted": numOpponentNilBidsAttempted,
      "numOpponentNilBidsMade": numOpponentNilBidsMade,
    };
  }

  static SpadesStats fromJson(final Map<String, dynamic> json) {
    return SpadesStats(
      numMatches: json["numMatches"],
      matchesWon: json["matchesWon"],
      matchesTied: json["matchesTied"],
      totalMatchPoints: json["totalMatchPoints"],
      numBagPenalties: json["numBagPenalties"],
      numRounds: json["numRounds"],
      totalRoundPoints: json["totalRoundPoints"],
      numBidsAttempted: json["numBidsAttempted"],
      numBidsMade: json["numBidsMade"],
      totalBids: json["totalBids"],
      totalBagsTaken: json["totalBagsTaken"],
      numNilBidsAttempted: json["numNilBidsAttempted"],
      numNilBidsMade: json["numNilBidsMade"],
      totalOpponentRoundPoints: json["totalOpponentRoundPoints"],
      totalOpponentMatchPoints: json["totalOpponentMatchPoints"],
      numOpponentBidsAttempted: json["numOpponentBidsAttempted"],
      numOpponentBidsMade: json["numOpponentBidsMade"],
      totalOpponentBids: json["totalOpponentBids"],
      totalOpponentBagsTaken: json["totalOpponentBagsTaken"],
      numOpponentNilBidsAttempted: json["numOpponentNilBidsAttempted"],
      numOpponentNilBidsMade: json["numOpponentNilBidsMade"],
    );
  }
}
