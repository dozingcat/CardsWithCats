import 'package:cards_with_cats/rook/rook.dart';

class RookStats {
  final int numMatches;
  final int matchesWon;
  final int totalMatchPoints;
  final int numContracts;
  final int numContractsMade;
  final int totalOpponentMatchPoints;
  final int numOpponentContracts;
  final int numOpponentContractsMade;

  RookStats({
    required this.numMatches,
    required this.matchesWon,
    required this.totalMatchPoints,
    required this.numContracts,
    required this.numContractsMade,
    required this.totalOpponentMatchPoints,
    required this.numOpponentContracts,
    required this.numOpponentContractsMade,
  });

  static RookStats empty() {
    return RookStats(
      numMatches: 0,
      matchesWon: 0,
      totalMatchPoints: 0,
      numContracts: 0,
      numContractsMade: 0,
      totalOpponentMatchPoints: 0,
      numOpponentContracts: 0,
      numOpponentContractsMade: 0,
    );
  }

  RookStats copyWith({
    int? numMatches,
    int? matchesWon,
    int? totalMatchPoints,
    int? numContracts,
    int? numContractsMade,
    int? totalOpponentMatchPoints,
    int? numOpponentContracts,
    int? numOpponentContractsMade,
  }) {
    return RookStats(
      numMatches: numMatches ?? this.numMatches,
      matchesWon: matchesWon ?? this.matchesWon,
      totalMatchPoints: totalMatchPoints ?? this.totalMatchPoints,
      numContracts: numContracts ?? this.numContracts,
      numContractsMade: numContractsMade ?? this.numContractsMade,
      totalOpponentMatchPoints: totalOpponentMatchPoints ?? this.totalOpponentMatchPoints,
      numOpponentContracts: numOpponentContracts ?? this.numOpponentContracts,
      numOpponentContractsMade: numOpponentContractsMade ?? this.numOpponentContractsMade,
    );
  }

  RookStats updateFromRound(RookRound round) {
    if (!round.isOver()) {
      throw Exception("Rook round is not over");
    }
    // A passed out round has no contract.
    final contract = round.contract;
    if (contract == null) {
      return this;
    }
    final declarerTeam = contract.declarer % numTeams;
    final made = round.teamPointsTaken()[declarerTeam] >= contract.bid;
    if (declarerTeam == 0) {
      return copyWith(
        numContracts: numContracts + 1,
        numContractsMade: numContractsMade + (made ? 1 : 0),
      );
    }
    return copyWith(
      numOpponentContracts: numOpponentContracts + 1,
      numOpponentContractsMade: numOpponentContractsMade + (made ? 1 : 0),
    );
  }

  RookStats updateFromMatch(RookMatch match) {
    if (!match.isMatchOver()) {
      throw Exception("Rook match is not over");
    }
    final scores = match.scores;
    return copyWith(
      numMatches: numMatches + 1,
      matchesWon: matchesWon + (match.winningTeam() == 0 ? 1 : 0),
      totalMatchPoints: totalMatchPoints + scores[0],
      totalOpponentMatchPoints: totalOpponentMatchPoints + scores[1],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "__version__": 1,
      "numMatches": numMatches,
      "matchesWon": matchesWon,
      "totalMatchPoints": totalMatchPoints,
      "numContracts": numContracts,
      "numContractsMade": numContractsMade,
      "totalOpponentMatchPoints": totalOpponentMatchPoints,
      "numOpponentContracts": numOpponentContracts,
      "numOpponentContractsMade": numOpponentContractsMade,
    };
  }

  static RookStats fromJson(final Map<String, dynamic> json) {
    return RookStats(
      numMatches: json["numMatches"],
      matchesWon: json["matchesWon"],
      totalMatchPoints: json["totalMatchPoints"],
      numContracts: json["numContracts"],
      numContractsMade: json["numContractsMade"],
      totalOpponentMatchPoints: json["totalOpponentMatchPoints"],
      numOpponentContracts: json["numOpponentContracts"],
      numOpponentContractsMade: json["numOpponentContractsMade"],
    );
  }
}
