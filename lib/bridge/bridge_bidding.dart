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

int _numBidsSinceOpen(List<PlayerBid> bidHistory) {
  int firstBidIndex =
      bidHistory.indexWhere((bid) => bid.action.bidType != BidType.pass);
  if (firstBidIndex == -1) {
    return 0;
  }
  return bidHistory.length - firstBidIndex;
}

PlayerBid chooseBid(BidRequest req) {
  int bidsSinceOpen = _numBidsSinceOpen(req.bidHistory);
  if (bidsSinceOpen == 0) {
    return PlayerBid(req.playerIndex, makeOpeningBid(req));
  }
  if (bidsSinceOpen == 1) {
    return PlayerBid(req.playerIndex, makeOvercallBid(req));
  }

  // TODO
  return PlayerBid(req.playerIndex, BidAction.pass());
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

BidAction preemptBidIfPossible(Map<Suit, int> counts) {
  Suit longestSuit = findLongestSuit(counts);
  int suitLength = counts[longestSuit]!;
  if (suitLength <= 5 || (suitLength == 6 && longestSuit == Suit.clubs)) {
    return BidAction.pass();
  }
  if (suitLength == 6) {
    return BidAction.contract(2, longestSuit);
  } else if (suitLength == 7) {
    return BidAction.contract(3, longestSuit);
  } else {
    return BidAction.contract(4, longestSuit);
  }
}

BidAction makeOpeningBid(final BidRequest req) {
  assert(req.bidHistory.every((bid) => bid.action.bidType == BidType.pass));

  final hand = req.hand;
  final precedingPasses = req.bidHistory.length;
  final counts = suitCounts(hand);
  final basePoints = highCardPoints(hand);
  final pointsWithLength = basePoints + lengthPoints(hand);

  if (basePoints >= 15 && basePoints <= 17 && suitCountCanOpenNoTrump(counts)) {
    return BidAction.noTrump(1);
  }
  if (basePoints >= 20 && basePoints <= 22 && suitCountCanOpenNoTrump(counts)) {
    return BidAction.noTrump(2);
  }
  if (basePoints >= 23 && basePoints <= 25 && suitCountCanOpenNoTrump(counts)) {
    return BidAction.noTrump(3);
  }

  if (pointsWithLength >= 21) {
    return BidAction.contract(2, Suit.clubs);
  } else if (pointsWithLength >= 13) {
    final suit = suitToOpen(counts);
    return BidAction.contract(1, suit);
  } else if (pointsWithLength <= 5) {
    return BidAction.pass();
  } else {
    // Don't preempt if last bidder.
    if (precedingPasses < 3) {
      return preemptBidIfPossible(counts);
    }
    return BidAction.pass();
  }
}

BidAction makeOvercallBid(final BidRequest req) {
  final hand = req.hand;
  final openingBid = req.bidHistory.last.action.contractBid!;
  final counts = suitCounts(hand);
  final basePoints = highCardPoints(hand);
  final pointsWithLength = basePoints + lengthPoints(hand);

  // Very strong hand - make a takeout double
  if (basePoints >= 17) {
    return BidAction.double();
  }

  bool isOpeningOneOfSuit = openingBid.count == 1 && openingBid.trump != null;
  if (isOpeningOneOfSuit) {
    Suit openingSuit = openingBid.trump!;
    // 1NT overcall with 15-18 points and a stopper in opponent's suit
    if (basePoints >= 15 &&
        basePoints <= 18 &&
        suitCountCanOpenNoTrump(counts) &&
        hasStopperInSuit(hand, openingSuit)) {
      return BidAction.noTrump(1);
    }

    // Simple overcall with a good 5+ card suit
    for (final suit in Suit.values) {
      if (suit != openingBid.trump &&
          counts[suit]! >= 5 &&
          basePoints >= 8 &&
          basePoints <= 16) {
        // Bid at the 1-level if possible
        if (suit.index > openingSuit.index && openingBid.count == 1) {
          return BidAction.contract(1, suit);
        }
        // Otherwise bid at the 2-level if we have enough strength
        else if (basePoints >= 10) {
          return BidAction.contract(2, suit);
        }
      }
    }

    // Preemptive jump overcall with a weak hand and a good 6+ card suit
    for (final suit in Suit.values) {
      if (suit != openingBid.trump &&
          counts[suit]! >= 6 &&
          basePoints >= 6 &&
          basePoints <= 10) {
        // Jump to one level higher than necessary
        final minLevel = openingSuit.index > suit.index
            ? openingBid.count + 1
            : openingBid.count;
        return BidAction.contract(minLevel + 1, suit);
      }
    }

    // Takeout double with opening strength and support for unbid suits
    if (basePoints >= 12 &&
        basePoints <= 16 &&
        hasShortageInSuit(counts, openingSuit) &&
        hasSupportForUnbidSuits(counts, openingSuit)) {
      return BidAction.double();
    }
  }

  return BidAction.pass();
}

bool hasStopperInSuit(final List<PlayingCard> hand, final Suit suit) {
  // Check for A, Kx, Qxx, or Jxxx in the opponent's suit
  final cardsInSuit = hand.where((card) => card.suit == suit).toList();

  if (cardsInSuit.isEmpty) return false;

  if (cardsInSuit.any((card) => card.rank == Rank.ace)) return true;
  if (cardsInSuit.length >= 2 &&
      cardsInSuit.any((card) => card.rank == Rank.king)) return true;
  if (cardsInSuit.length >= 3 &&
      cardsInSuit.any((card) => card.rank == Rank.queen)) return true;
  if (cardsInSuit.length >= 4 &&
      cardsInSuit.any((card) => card.rank == Rank.jack)) return true;

  return false;
}

bool hasShortageInSuit(final Map<Suit, int> counts, final Suit suit) {
  return counts[suit]! <= 2;
}

bool hasSupportForUnbidSuits(final Map<Suit, int> counts, final Suit bidSuit) {
  // Support means at least 4 cards in each unbid major and reasonable distribution
  for (final suit in Suit.values) {
    if (suit != bidSuit) {
      if (isMajorSuit(suit) && counts[suit]! < 4) {
        return false;
      }
      if (isMinorSuit(suit) && counts[suit]! < 3) {
        return false;
      }
    }
  }
  return true;
}
