import 'package:cards_with_cats/five_hundred/five_hundred.dart';

class FiveHundredStats {
  final int numMatches;
  final int matchesWon;
  final int totalMatchPoints;
  final int numContracts;
  final int numContractsMade;
  // The declaring team taking all 10 tricks, whatever the bid was.
  final int numSlams;
  final int totalOpponentMatchPoints;
  final int numOpponentContracts;
  final int numOpponentContractsMade;
  final int numOpponentSlams;

  FiveHundredStats({
    required this.numMatches,
    required this.matchesWon,
    required this.totalMatchPoints,
    required this.numContracts,
    required this.numContractsMade,
    required this.numSlams,
    required this.totalOpponentMatchPoints,
    required this.numOpponentContracts,
    required this.numOpponentContractsMade,
    required this.numOpponentSlams,
  });

  static FiveHundredStats empty() {
    return FiveHundredStats(
      numMatches: 0,
      matchesWon: 0,
      totalMatchPoints: 0,
      numContracts: 0,
      numContractsMade: 0,
      numSlams: 0,
      totalOpponentMatchPoints: 0,
      numOpponentContracts: 0,
      numOpponentContractsMade: 0,
      numOpponentSlams: 0,
    );
  }

  FiveHundredStats copyWith({
    int? numMatches,
    int? matchesWon,
    int? totalMatchPoints,
    int? numContracts,
    int? numContractsMade,
    int? numSlams,
    int? totalOpponentMatchPoints,
    int? numOpponentContracts,
    int? numOpponentContractsMade,
    int? numOpponentSlams,
  }) {
    return FiveHundredStats(
      numMatches: numMatches ?? this.numMatches,
      matchesWon: matchesWon ?? this.matchesWon,
      totalMatchPoints: totalMatchPoints ?? this.totalMatchPoints,
      numContracts: numContracts ?? this.numContracts,
      numContractsMade: numContractsMade ?? this.numContractsMade,
      numSlams: numSlams ?? this.numSlams,
      totalOpponentMatchPoints: totalOpponentMatchPoints ?? this.totalOpponentMatchPoints,
      numOpponentContracts: numOpponentContracts ?? this.numOpponentContracts,
      numOpponentContractsMade: numOpponentContractsMade ?? this.numOpponentContractsMade,
      numOpponentSlams: numOpponentSlams ?? this.numOpponentSlams,
    );
  }

  FiveHundredStats updateFromRound(FiveHundredRound round) {
    if (!round.isOver()) {
      throw Exception("500 round is not over");
    }
    // A passed out round has no contract.
    final contract = round.contract;
    if (contract == null) {
      return this;
    }
    final declarerTeam = contract.declarer % numTeams;
    final made = round.didDeclarerMakeContract();
    final slam = round.tricksTakenByTeam()[declarerTeam] == numTricksPerRound;
    if (declarerTeam == 0) {
      return copyWith(
        numContracts: numContracts + 1,
        numContractsMade: numContractsMade + (made ? 1 : 0),
        numSlams: numSlams + (slam ? 1 : 0),
      );
    }
    return copyWith(
      numOpponentContracts: numOpponentContracts + 1,
      numOpponentContractsMade: numOpponentContractsMade + (made ? 1 : 0),
      numOpponentSlams: numOpponentSlams + (slam ? 1 : 0),
    );
  }

  FiveHundredStats updateFromMatch(FiveHundredMatch match) {
    if (!match.isMatchOver()) {
      throw Exception("500 match is not over");
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
      "numSlams": numSlams,
      "totalOpponentMatchPoints": totalOpponentMatchPoints,
      "numOpponentContracts": numOpponentContracts,
      "numOpponentContractsMade": numOpponentContractsMade,
      "numOpponentSlams": numOpponentSlams,
    };
  }

  static FiveHundredStats fromJson(final Map<String, dynamic> json) {
    return FiveHundredStats(
      numMatches: json["numMatches"],
      matchesWon: json["matchesWon"],
      totalMatchPoints: json["totalMatchPoints"],
      numContracts: json["numContracts"],
      numContractsMade: json["numContractsMade"],
      numSlams: json["numSlams"],
      totalOpponentMatchPoints: json["totalOpponentMatchPoints"],
      numOpponentContracts: json["numOpponentContracts"],
      numOpponentContractsMade: json["numOpponentContractsMade"],
      numOpponentSlams: json["numOpponentSlams"],
    );
  }
}
