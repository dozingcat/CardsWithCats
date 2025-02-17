import '../cards/card.dart';
import 'bridge.dart';
import 'bridge_ai.dart';

class BidRequest {
  final int playerIndex;
  final List<PlayingCard> hand;
  final List<PlayerBid> bidHistory;

  BidRequest({
    required this.playerIndex,
    required this.hand,
    required this.bidHistory,
  });
}

PlayerBid chooseBid(BidRequest req) {
  if (req.bidHistory.every((bid) => bid.bidType == BidType.pass)) {
    ContractBid? contractBid = makeOpeningBid(req.hand, precedingPasses: req.bidHistory.length);
    if (contractBid != null) {
      return PlayerBid.contract(req.playerIndex, contractBid);
    }
  }
  // TODO
  return PlayerBid.pass(req.playerIndex);
}

Map<Suit, int> suitCounts(List<PlayingCard> cards) {
  Map<Suit, int> counts = {
    Suit.spades: 0,
    Suit.hearts: 0,
    Suit.diamonds: 0,
    Suit.clubs: 0,
  };
  for (final c in cards) {
    counts[c.suit] = counts[c.suit]! + 1;
  }
  return counts;
}

bool suitCountCanOpenNoTrump(Map<Suit, int> counts) {
  bool hasDoubleton = false;
  for (final entry in counts.entries) {
    if (entry.value <= 1) {
      return false;
    }
    if (entry.value == 2) {
      if (hasDoubleton) {
        return false;
      }
      hasDoubleton = true;
    }
    // ok to bit NT with 5-card major?
  }
  return true;
}

Suit suitToOpen(Map<Suit, int> counts) {
  int numSpades = counts[Suit.spades]!;
  int numHearts = counts[Suit.hearts]!;
  if (numSpades >= 5 || numHearts >= 5) {
    return numSpades >= numHearts ? Suit.spades : Suit.hearts;
  }
  int numDiamonds = counts[Suit.diamonds]!;
  int numClubs = counts[Suit.clubs]!;
  if (numDiamonds == 3 && numClubs == 3) {
    return Suit.clubs;
  }
  return numDiamonds >= numClubs ? Suit.diamonds : Suit.clubs;
}

Suit findLongestSuit(Map<Suit, int> counts) {
  Suit longest = Suit.clubs;
  for (final s in [Suit.spades, Suit.hearts, Suit.diamonds]) {
    if (counts[s]! > counts[longest]!) {
      longest = s;
    }
  }
  return longest;
}

ContractBid? preemptBidIfPossible(Map<Suit, int> counts) {
  Suit longestSuit = findLongestSuit(counts);
  int suitLength = counts[longestSuit]!;
  if (suitLength <= 5 || (suitLength == 6 && longestSuit == Suit.clubs)) {
    return null;
  }
  if (suitLength == 6) {
    return ContractBid(2, longestSuit);
  }
  else if (suitLength == 7) {
    return ContractBid(3, longestSuit);
  }
  else {
    return ContractBid(4, longestSuit);
  }
}

ContractBid? makeOpeningBid(final List<PlayingCard> hand, {required int precedingPasses}) {
  final counts = suitCounts(hand);
  final basePoints = highCardPoints(hand);
  final pointsWithLength = basePoints + lengthPoints(hand);

  if (basePoints >= 15 && basePoints <= 17 && suitCountCanOpenNoTrump(counts)) {
    return ContractBid.noTrump(1);
  }
  if (basePoints >= 20 && basePoints <= 22 && suitCountCanOpenNoTrump(counts)) {
    return ContractBid.noTrump(2);
  }
  if (basePoints >= 23 && basePoints <= 25 && suitCountCanOpenNoTrump(counts)) {
    return ContractBid.noTrump(3);
  }

  if (pointsWithLength >= 21) {
    return ContractBid(2, Suit.clubs);
  }
  else if (pointsWithLength >= 13) {
    final suit = suitToOpen(counts);
    return ContractBid(1, suit);
  }
  else if (pointsWithLength <= 5) {
    return null;
  }
  else {
    // Don't preempt if last bidder.
    if (precedingPasses < 3) {
      final maybePreempt = preemptBidIfPossible(counts);
      if (maybePreempt != null) {
        return maybePreempt;
      }
    }
    return null;
  }
}