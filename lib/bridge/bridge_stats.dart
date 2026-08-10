import 'package:cards_with_cats/bridge/bridge.dart';

/// Cumulative bridge statistics for the human player (seat 0, always
/// North-South). "Contracts" count rounds where the player's side
/// declared; "opposing" contracts were declared by East-West. "Made"
/// means the declaring side took enough tricks. Game and slam counts are
/// disjoint: a slam is not also counted as a game contract. Passed-out
/// rounds count toward numRounds but no contract category. IMP fields
/// are running totals of the duplicate comparison against the AI replay.
class BridgeStats {
  final int numMatches;
  final int numMatchesWon;
  final int numMatchesTied;
  final int netMatchImps;
  final int numRounds;
  final int netRoundImps;
  final int numContracts;
  final int numContractsMade;
  final int numOpposingContracts;
  final int numOpposingContractsMade;
  final int numGameContracts;
  final int numGameContractsMade;
  final int numOpposingGameContracts;
  final int numOpposingGameContractsMade;
  final int numSlamContracts;
  final int numSlamContractsMade;
  final int numOpposingSlamContracts;
  final int numOpposingSlamContractsMade;

  BridgeStats({
    required this.numMatches,
    required this.numMatchesWon,
    required this.numMatchesTied,
    required this.netMatchImps,
    required this.numRounds,
    required this.netRoundImps,
    required this.numContracts,
    required this.numContractsMade,
    required this.numOpposingContracts,
    required this.numOpposingContractsMade,
    required this.numGameContracts,
    required this.numGameContractsMade,
    required this.numOpposingGameContracts,
    required this.numOpposingGameContractsMade,
    required this.numSlamContracts,
    required this.numSlamContractsMade,
    required this.numOpposingSlamContracts,
    required this.numOpposingSlamContractsMade,
  });

  static BridgeStats empty() {
    return BridgeStats(
      numMatches: 0,
      numMatchesWon: 0,
      numMatchesTied: 0,
      netMatchImps: 0,
      numRounds: 0,
      netRoundImps: 0,
      numContracts: 0,
      numContractsMade: 0,
      numOpposingContracts: 0,
      numOpposingContractsMade: 0,
      numGameContracts: 0,
      numGameContractsMade: 0,
      numOpposingGameContracts: 0,
      numOpposingGameContractsMade: 0,
      numSlamContracts: 0,
      numSlamContractsMade: 0,
      numOpposingSlamContracts: 0,
      numOpposingSlamContractsMade: 0,
    );
  }

  BridgeStats copyWith({
    int? numMatches,
    int? numMatchesWon,
    int? numMatchesTied,
    int? netMatchImps,
    int? numRounds,
    int? netRoundImps,
    int? numContracts,
    int? numContractsMade,
    int? numOpposingContracts,
    int? numOpposingContractsMade,
    int? numGameContracts,
    int? numGameContractsMade,
    int? numOpposingGameContracts,
    int? numOpposingGameContractsMade,
    int? numSlamContracts,
    int? numSlamContractsMade,
    int? numOpposingSlamContracts,
    int? numOpposingSlamContractsMade,
  }) {
    return BridgeStats(
      numMatches: numMatches ?? this.numMatches,
      numMatchesWon: numMatchesWon ?? this.numMatchesWon,
      numMatchesTied: numMatchesTied ?? this.numMatchesTied,
      netMatchImps: netMatchImps ?? this.netMatchImps,
      numRounds: numRounds ?? this.numRounds,
      netRoundImps: netRoundImps ?? this.netRoundImps,
      numContracts: numContracts ?? this.numContracts,
      numContractsMade: numContractsMade ?? this.numContractsMade,
      numOpposingContracts: numOpposingContracts ?? this.numOpposingContracts,
      numOpposingContractsMade:
          numOpposingContractsMade ?? this.numOpposingContractsMade,
      numGameContracts: numGameContracts ?? this.numGameContracts,
      numGameContractsMade: numGameContractsMade ?? this.numGameContractsMade,
      numOpposingGameContracts:
          numOpposingGameContracts ?? this.numOpposingGameContracts,
      numOpposingGameContractsMade:
          numOpposingGameContractsMade ?? this.numOpposingGameContractsMade,
      numSlamContracts: numSlamContracts ?? this.numSlamContracts,
      numSlamContractsMade: numSlamContractsMade ?? this.numSlamContractsMade,
      numOpposingSlamContracts:
          numOpposingSlamContracts ?? this.numOpposingSlamContracts,
      numOpposingSlamContractsMade:
          numOpposingSlamContractsMade ?? this.numOpposingSlamContractsMade,
    );
  }

  /// True if the contracted tricks alone score 100+ points, i.e. the
  /// scoring definition of game (a doubled 2S counts, matching
  /// [Contract.scoreForTricksTaken]).
  static bool isGameContract(Contract contract) {
    final bid = contract.bid;
    final doubleFactor = switch (contract.doubled) {
      DoubledType.none => 1,
      DoubledType.doubled => 2,
      DoubledType.redoubled => 4,
    };
    final bidTrickPoints = doubleFactor *
        (bid.count * (isMinorSuit(bid.trump) ? 20 : 30) +
            (bid.trump == null ? 10 : 0));
    return bidTrickPoints >= 100;
  }

  /// Updates stats for a finished round and its finished AI replay.
  BridgeStats updateFromRound(BridgeRound round, BridgeRound duplicateRound) {
    if (!round.isOver() || !duplicateRound.isOver()) {
      throw Exception("Round or duplicate round is not over");
    }
    var stats = copyWith(
      numRounds: numRounds + 1,
      netRoundImps:
          netRoundImps + BridgeMatch.impsForRounds(round, duplicateRound),
    );
    final contract = round.contract;
    if (contract == null) {
      return stats; // passed out
    }
    final playerSideDeclared = contract.declarer % 2 == 0;
    final made = round.tricksTakenByDeclarerOverContract() >= 0;
    final slam = contract.bid.isSlam || contract.bid.isGrandSlam;
    final game = !slam && isGameContract(contract);
    if (playerSideDeclared) {
      stats = stats.copyWith(
        numContracts: stats.numContracts + 1,
        numContractsMade: stats.numContractsMade + (made ? 1 : 0),
        numGameContracts: stats.numGameContracts + (game ? 1 : 0),
        numGameContractsMade:
            stats.numGameContractsMade + (game && made ? 1 : 0),
        numSlamContracts: stats.numSlamContracts + (slam ? 1 : 0),
        numSlamContractsMade:
            stats.numSlamContractsMade + (slam && made ? 1 : 0),
      );
    } else {
      stats = stats.copyWith(
        numOpposingContracts: stats.numOpposingContracts + 1,
        numOpposingContractsMade:
            stats.numOpposingContractsMade + (made ? 1 : 0),
        numOpposingGameContracts:
            stats.numOpposingGameContracts + (game ? 1 : 0),
        numOpposingGameContractsMade:
            stats.numOpposingGameContractsMade + (game && made ? 1 : 0),
        numOpposingSlamContracts:
            stats.numOpposingSlamContracts + (slam ? 1 : 0),
        numOpposingSlamContractsMade:
            stats.numOpposingSlamContractsMade + (slam && made ? 1 : 0),
      );
    }
    return stats;
  }

  /// Updates stats for a finished match (all duplicate replays done).
  BridgeStats updateFromMatch(BridgeMatch match) {
    final imps = match.totalImpsForPlayer0();
    return copyWith(
      numMatches: numMatches + 1,
      numMatchesWon: numMatchesWon + (imps > 0 ? 1 : 0),
      numMatchesTied: numMatchesTied + (imps == 0 ? 1 : 0),
      netMatchImps: netMatchImps + imps,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "__version__": 1,
      "numMatches": numMatches,
      "numMatchesWon": numMatchesWon,
      "numMatchesTied": numMatchesTied,
      "netMatchImps": netMatchImps,
      "numRounds": numRounds,
      "netRoundImps": netRoundImps,
      "numContracts": numContracts,
      "numContractsMade": numContractsMade,
      "numOpposingContracts": numOpposingContracts,
      "numOpposingContractsMade": numOpposingContractsMade,
      "numGameContracts": numGameContracts,
      "numGameContractsMade": numGameContractsMade,
      "numOpposingGameContracts": numOpposingGameContracts,
      "numOpposingGameContractsMade": numOpposingGameContractsMade,
      "numSlamContracts": numSlamContracts,
      "numSlamContractsMade": numSlamContractsMade,
      "numOpposingSlamContracts": numOpposingSlamContracts,
      "numOpposingSlamContractsMade": numOpposingSlamContractsMade,
    };
  }

  static BridgeStats fromJson(final Map<String, dynamic> json) {
    return BridgeStats(
      numMatches: json["numMatches"] ?? 0,
      numMatchesWon: json["numMatchesWon"] ?? 0,
      numMatchesTied: json["numMatchesTied"] ?? 0,
      netMatchImps: json["netMatchImps"] ?? 0,
      numRounds: json["numRounds"] ?? 0,
      netRoundImps: json["netRoundImps"] ?? 0,
      numContracts: json["numContracts"] ?? 0,
      numContractsMade: json["numContractsMade"] ?? 0,
      numOpposingContracts: json["numOpposingContracts"] ?? 0,
      numOpposingContractsMade: json["numOpposingContractsMade"] ?? 0,
      numGameContracts: json["numGameContracts"] ?? 0,
      numGameContractsMade: json["numGameContractsMade"] ?? 0,
      numOpposingGameContracts: json["numOpposingGameContracts"] ?? 0,
      numOpposingGameContractsMade: json["numOpposingGameContractsMade"] ?? 0,
      numSlamContracts: json["numSlamContracts"] ?? 0,
      numSlamContractsMade: json["numSlamContractsMade"] ?? 0,
      numOpposingSlamContracts: json["numOpposingSlamContracts"] ?? 0,
      numOpposingSlamContractsMade: json["numOpposingSlamContractsMade"] ?? 0,
    );
  }
}
