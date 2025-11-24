import 'dart:collection';

import 'package:cards_with_cats/bridge/bridge_bidding_rules.dart';
import 'package:cards_with_cats/bridge/utils.dart';

import '../cards/card.dart';
import 'bridge.dart';
import 'bridge_ai.dart';
import 'hand_estimate.dart';

class BidRequest {
  final int playerIndex;
  final List<PlayingCard> hand;
  final List<PlayerBid> bidHistory;
  final Vulnerability vulnerability;

  BidRequest({
    required this.playerIndex,
    required this.hand,
    required this.bidHistory,
    this.vulnerability = Vulnerability.neither,
  });
}

PlayerBid chooseBid(BidRequest req) {
  final counts = suitCounts(req.hand);
  for (final rule in allBiddingRules()) {
    if (rule.matcher(req)) {
      print("Matched rule: ${rule.description}");
      final actions = rule.actions(req);
      for (final bidAction in actions.keys) {
        if (actions[bidAction]!.matches(req.hand, counts)) {
          print("${rule.description}: ${actions[bidAction]!.description}");
          return PlayerBid(req.playerIndex, bidAction);
        }
      }
      // We only match one rule.
      print("No action matched, passing");
      return PlayerBid(req.playerIndex, BidAction.pass());
    }
  }

  print("No rule matched, using hand estimates");
  final handEstimates = handEstimatesForBidSequence(req);
  print(handEstimates);
  return makeBidUsingHandEstimates(req, handEstimates, counts);
}

PlayerBid makeBidUsingHandEstimates(BidRequest req,
    List<HandEstimate> handEstimates, Map<Suit, int> suitCounts) {
  // Do we have a major fit?
  HandEstimate partnerEstimate = handEstimates[(req.playerIndex + 2) % 4];
  // TODO: adjust points for hand distribution?
  Range combinedPointRange =
      partnerEstimate.pointRange.plusConstant(highCardPoints(req.hand));
  print(
      "Partner point range: ${partnerEstimate.pointRange}, my points: ${highCardPoints(req.hand)}, combined point range: $combinedPointRange");
  Range combinedSuitRange(Suit s) =>
      partnerEstimate.suitLengthRanges[s]!.plusConstant(suitCounts[s]!);

  Suit? findBestSuitFit() {
    Range totalSpades = combinedSuitRange(Suit.spades);
    Range totalHearts = combinedSuitRange(Suit.hearts);
    if (totalHearts.low! >= 8 && totalHearts.low! > totalSpades.low!) {
      return Suit.hearts;
    } else if (totalSpades.low! >= 8) {
      return Suit.spades;
    }
    return null;
  }

  ContractBid? invitationalBidIfPossible(Suit? suit) {
    // e.g. after 1H-1S-2H-pass, 3H is invitational, but after
    // 1H-1S-2H-2S it's just competitive.
    final currentContract = contractFromBids(
      bids: req.bidHistory,
      vulnerability: req.vulnerability,
    );
    if (isMinorSuit(suit)) {
      throw Exception("Minor suits not supported yet");
    }
    ContractBid invitationalBid =
        (suit == null) ? ContractBid.noTrump(2) : ContractBid(3, suit);
    ContractBid lowerThanInvitationalBid =
        ContractBid(invitationalBid.count - 1, suit);
    if (lowerThanInvitationalBid.isHigherThan(currentContract.bid)) {
      return invitationalBid;
    }
    if (currentContract.declarer % 2 == req.playerIndex % 2 &&
        lowerThanInvitationalBid == currentContract.bid) {
      return invitationalBid;
    }
    return null;
  }

  int? minimumBidLevelIfPossible(Suit? suit) {
    ContractBid lastBid = lastContractBid(req.bidHistory)!.action.contractBid!;
    int level = isSuitHigherThan(suit, lastBid.trump)
        ? lastBid.count
        : lastBid.count + 1;
    return (level <= 7) ? level : null;
  }

  Suit? bestSuitFit = findBestSuitFit();
  if (bestSuitFit == null || isMajorSuit(bestSuitFit)) {
    // Heuristic is 25 points needed for game with 8 trumps,
    // 23 with 9 trumps, 21 with 10 trumps, etc.
    int trumpBonusPoints = (bestSuitFit != null)
        ? 2 * (combinedSuitRange(bestSuitFit).low! - 8)
        : 0;
    int pointsNeededForGame = 25 - trumpBonusPoints;
    int pointsNeededForGameInvite = 22 - trumpBonusPoints;
    // TODO: Look at the top of the range also.
    if (combinedPointRange.low! >= pointsNeededForGame) {
      final targetBid = bestSuitFit == null
          ? ContractBid.noTrump(3)
          : ContractBid(4, bestSuitFit);
      if (canCurrentBidderMakeContractBid(req.bidHistory, targetBid)) {
        return PlayerBid(req.playerIndex, BidAction.withBid(targetBid));
      }
    }

    bool shouldInviteIfPossible =
        combinedPointRange.low! >= pointsNeededForGameInvite &&
            (combinedPointRange.high == null ||
                combinedPointRange.high! >= pointsNeededForGame);
    if (shouldInviteIfPossible) {
      print("Inviting with min ${combinedPointRange.low} points");
      ContractBid? invitationalBid = invitationalBidIfPossible(bestSuitFit);
      if (invitationalBid != null) {
        return PlayerBid(req.playerIndex, BidAction.withBid(invitationalBid));
      }
    }

    int? minBidLevel = minimumBidLevelIfPossible(bestSuitFit);
    if (minBidLevel != null) {
      final pointsNeededForMinimumBid = bestSuitFit != null
          ? switch (minBidLevel) {
              1 => 18,
              2 => 18,
              3 => 21,
              4 => 24,
              _ => 99,
            }
          : switch (minBidLevel) {
              1 => 18,
              2 => 21,
              3 => 24,
              _ => 99,
            };
      if (combinedPointRange.low! >= pointsNeededForMinimumBid) {
        return PlayerBid(req.playerIndex,
            BidAction.withBid(ContractBid(minBidLevel, bestSuitFit)));
      }
    }
  } else {
    // HERE: No suit fit, can bid an unshown suit if sufficient length and points.
    Suit? bestSuitNotAlreadyShown() {

    }
    final suitToMaybeBid = bestSuitNotAlreadyShown();
    if (suitToMaybeBid != null) {

    }
  }

  return PlayerBid(req.playerIndex, BidAction.pass());
}

LinkedHashMap<BidAction, BidAnalysis>? getActionsForNextBid(BidRequest req) {
  for (final rule in allBiddingRules()) {
    if (rule.matcher(req)) {
      // print("Matched rule: ${rule.description}");
      return rule.actions(req);
    }
  }
  return null;
}

enum RaiseStrength {
  minimum,
  gameInvite,
  game,
  // TODO: slam invite, slam
}

RaiseStrength? raiseStrengthForBid({
  required List<PlayerBid> partialBidHistory,
  required List<HandEstimate> estimates,
  required BidAction currentBid,
}) {
  if (currentBid.bidType != BidType.contract) {
    return null;
  }
  final contractBid = currentBid.contractBid!;
  final trump = contractBid.trump;
  if (trump != null) {
    // Check that a trump fit is established or that partner has shown 4+ cards.
    int partnerIndex = (partialBidHistory.last.player + 3) % 4;
    int partnerMinTrumps =
        estimates[partnerIndex].suitLengthRanges[trump]!.low ?? 0;
    int selfIndex = (partnerIndex + 2) % 4;
    int selfMinTrumps = estimates[selfIndex].suitLengthRanges[trump]!.low ?? 0;
    bool partnerHas4Plus = partnerMinTrumps >= 4;
    bool combined8Plus = partnerMinTrumps + selfMinTrumps >= 8;
    if (!partnerHas4Plus && !combined8Plus) {
      return null;
    }
    if (contractBid.count >= 5 ||
        (isMajorSuit(trump) && contractBid.count == 4)) {
      return RaiseStrength.game;
    }
    // Could be 4C or 4D at this point which is still invitational.
    if (contractBid.count >= 3) {
      // Could we have bid lower?
      final lowerBid = ContractBid(contractBid.count - 1, trump);
      if (canCurrentBidderMakeContractBid(partialBidHistory, lowerBid)) {
        return RaiseStrength.gameInvite;
      }
      // Or did partner bid lower and we raised?
      final partnerBid = partialBidHistory[partialBidHistory.length - 2].action;
      final lastOpponentBid = partialBidHistory.last.action;
      if (lastOpponentBid.bidType == BidType.pass &&
          partnerBid.contractBid == lowerBid) {
        return RaiseStrength.gameInvite;
      }
    }
    return RaiseStrength.minimum;
  } else {
    // NT, 2 is invitational if could have bid 1.
    if (contractBid.count >= 3) {
      return RaiseStrength.game;
    }
    if (contractBid.count == 2) {
      // Check if we could have bid 1NT, or if partner did. This is probably
      // not completely accurate.
      final lowerBid = ContractBid(1, null);
      if (canCurrentBidderMakeContractBid(partialBidHistory, lowerBid)) {
        return RaiseStrength.gameInvite;
      }
      final partnerBid = partialBidHistory[partialBidHistory.length - 2].action;
      final lastOpponentBid = partialBidHistory.last.action;
      if (lastOpponentBid.bidType == BidType.pass &&
          partnerBid.contractBid == lowerBid) {
        return RaiseStrength.gameInvite;
      }
    }
    return RaiseStrength.minimum;
  }
}

List<HandEstimate> handEstimatesForBidSequence(BidRequest req) {
  final estimates = List.generate(4, (i) => HandEstimate.create());
  List<PlayerBid> partialBidHistory = [];
  for (int i = 0; i < req.bidHistory.length; i++) {
    final currentBid = req.bidHistory[i];
    int currentPlayer = currentBid.player;
    final bidRequestForPartialHistory = BidRequest(
      playerIndex: 0, // FIXME: this is wrong
      hand: req.hand,
      bidHistory: partialBidHistory,
      vulnerability: req.vulnerability,
    );
    final possibleActions = getActionsForNextBid(bidRequestForPartialHistory);
    if (possibleActions != null) {
      final selectedAnalysis = possibleActions[currentBid.action];
      if (selectedAnalysis != null) {
        final previousEstimate = estimates[currentPlayer];
        estimates[currentPlayer] = estimates[currentPlayer]
            .combineOrReplace(selectedAnalysis.handEstimate);

        print(
            "Matched action for $currentPlayer: ${selectedAnalysis.description}");
        print("Previous estimate: $previousEstimate");
        print("Estimate from action: ${selectedAnalysis.handEstimate}");
        print("Updated estimate: ${estimates[currentPlayer]}");
      }
    } else {
      HandEstimate? adHocEstimate = getAdHocHandEstimateForBidSequence(
        estimates,
        partialBidHistory,
        currentBid.action,
      );
      print("Ad-hoc estimate: $adHocEstimate");
      if (adHocEstimate != null) {
        estimates[currentPlayer] =
            estimates[currentPlayer].combineOrReplace(adHocEstimate);
      }
    }
    partialBidHistory.add(currentBid);
  }
  return estimates;
}

HandEstimate? getAdHocHandEstimateForBidSequence(List<HandEstimate> estimates,
    List<PlayerBid> partialBidHistory, BidAction currentBid) {
  int currentPlayerIndex = (partialBidHistory.last.player + 1) % 4;
  int partnerIndex = (currentPlayerIndex + 2) % 4;

  // See if this is an invitational bid.
  if (currentBid.bidType == BidType.contract) {
    RaiseStrength? raiseStrength = raiseStrengthForBid(
      partialBidHistory: partialBidHistory,
      estimates: estimates,
      currentBid: currentBid,
    );
    final trump = currentBid.contractBid!.trump;
    if (raiseStrength != null) {
      int partnerMinTrumps = trump != null
          ? estimates[partnerIndex].suitLengthRanges[trump]!.low ?? 0
          : 0;
      int partnerMinPoints = estimates[partnerIndex].pointRange.low ?? 0;
      Map<Suit, Range> suitLengthRanges =
          trump != null ? {trump: Range(low: 8 - partnerMinTrumps)} : {};
      if (raiseStrength == RaiseStrength.game) {
        int minPoints = 25 - partnerMinPoints;
        return HandEstimate.create(
          pointBonusType: HandPointBonusType.suitLength,
          pointRange: Range(low: minPoints),
          suitLengthRanges: suitLengthRanges,
        );
      } else if (raiseStrength == RaiseStrength.gameInvite) {
        int minPoints = 23 - partnerMinPoints;
        return HandEstimate.create(
          pointBonusType: HandPointBonusType.suitLength,
          pointRange: Range(low: minPoints),
          suitLengthRanges: suitLengthRanges,
        );
      } else if (raiseStrength == RaiseStrength.minimum) {
        // TODO: Figure out what point range this shows.
        // e.g. if an invitational or game bid would have been possible,
        // then it's weaker than that.
        Range minRaisePointRange = const Range();
        return HandEstimate.create(
          pointBonusType: HandPointBonusType.suitLength,
          pointRange: minRaisePointRange,
          suitLengthRanges: suitLengthRanges,
        );
      }
    }
  }

  return HandEstimate.create(
    pointBonusType: HandPointBonusType.suitLength,
    pointRange: const Range(),
    suitLengthRanges: const {},
  );
}
