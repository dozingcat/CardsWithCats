import 'dart:collection';

import 'package:cards_with_cats/bridge/bridge_bidding_rules.dart';

import '../cards/card.dart';
import 'bridge.dart';
import 'bridge_ai.dart';

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
      final actions = rule.actions(req);
      for (final bidAction in actions.keys) {
        if (actions[bidAction]!.matches(req.hand, counts)) {
          // print("${rule.description}: ${actions[bidAction]!.description}");
          return PlayerBid(req.playerIndex, bidAction);
        }
      }
    }
  }

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

  Suit? bestSuitFit = findBestSuitFit();
  if (bestSuitFit == null || isMajorSuit(bestSuitFit)) {
    // Heuristic is 25 points needed for game with 8 trumps,
    // 23 with 9 trumps, 21 with 10 trumps, etc.
    int trumpBonusPoints = (bestSuitFit != null)
        ? 2 * (combinedSuitRange(bestSuitFit).low! - 8)
        : 0;
    int pointsNeededForGame = 25 - trumpBonusPoints;
    if (combinedPointRange.low! >= pointsNeededForGame) {
      final targetBid = bestSuitFit == null
          ? ContractBid.noTrump(3)
          : ContractBid(4, bestSuitFit);
      if (canCurrentBidderMakeContractBid(req.bidHistory, targetBid)) {
        return PlayerBid(req.playerIndex, BidAction.withBid(targetBid));
      }
    }

    bool shouldInviteIfPossible =
        combinedPointRange.low! + 2 >= pointsNeededForGame ||
            (combinedPointRange.high != null &&
                combinedPointRange.high! > pointsNeededForGame);
    if (shouldInviteIfPossible) {
      ContractBid? invitationalBid = invitationalBidIfPossible(bestSuitFit);
      if (invitationalBid != null) {
        return PlayerBid(req.playerIndex, BidAction.withBid(invitationalBid));
      }
    }
  }
  // HERE: Try for NT, ideally checking for stoppers in opponent's suits.

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

List<HandEstimate> handEstimatesForBidSequence(BidRequest req) {
  final result = List.generate(4, (i) => HandEstimate());
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
        final previousEstimate = result[currentPlayer];
        result[currentPlayer] = result[currentPlayer]
            .combineOrReplace(selectedAnalysis.handEstimate);

        print(
            "Matched action for $currentPlayer: ${selectedAnalysis.description}");
        print("Previous estimate: $previousEstimate");
        print("Estimate from action: ${selectedAnalysis.handEstimate}");
        print("Updated estimate: ${result[currentPlayer]}");
      }
    } else {
      HandEstimate? adHocEstimate = getAdHocHandEstimateForBidSequence(
        partialBidHistory,
        currentBid.action,
      );
      print("Ad-hoc estimate: $adHocEstimate");
      if (adHocEstimate != null) {
        result[currentPlayer] = adHocEstimate;
      }
    }
    partialBidHistory.add(currentBid);
  }
  return result;
}

HandEstimate? getAdHocHandEstimateForBidSequence(
    List<PlayerBid> partialBidHistory, BidAction currentBid) {
  return null;
}
