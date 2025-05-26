import 'dart:collection';

import '../cards/card.dart';
import 'bridge.dart';
import 'bridge_ai.dart';
import 'bridge_bidding.dart';
import 'hand_estimate.dart';
import 'utils.dart';

class BiddingRule {
  final String description;
  final bool Function(BidRequest) matcher;
  final LinkedHashMap<BidAction, BidAnalysis> Function(BidRequest) actions;

  BiddingRule(
      {required this.description,
      required this.matcher,
      required this.actions});
}

List<BiddingRule> allBiddingRules() {
  return [
    BiddingRule(
      description: "Opening bid",
      matcher: (req) {
        return req.bidHistory.every((b) => b.action.bidType == BidType.pass);
      },
      actions: openingBidActions,
    ),
    BiddingRule(
      description: "Response to opponent's opening 1-bid",
      matcher: (req) {
        if (_numBidsSinceOpen(req.bidHistory) == 1) {
          final openingBid = req.bidHistory.last.action.contractBid!;
          if (openingBid.count == 1 && openingBid.trump != null) {
            return true;
          }
        }
        return false;
      },
      actions: actionsForOpponentOpeningOneBid,
    ),
    BiddingRule(
      description: "Response to partner's opening major 1-bid, opponent passed",
      matcher: (req) {
        final bids = bidActionsRemovingInitialPasses(req.bidHistory);
        if (bids.length == 2 && bids[1].bidType == BidType.pass) {
          final openingBid = bids[0].contractBid!;
          return openingBid.count == 1 && isMajorSuit(openingBid.trump);
        }
        return false;
      },
      actions: actionsForPartnerOpeningOneMajor,
    ),
    BiddingRule(
      description: "Response to partner's opening minor 1-bid, opponent passed",
      matcher: (req) {
        final bids = bidActionsRemovingInitialPasses(req.bidHistory);
        if (bids.length == 2 && bids[1].bidType == BidType.pass) {
          final openingBid = bids[0].contractBid!;
          return openingBid.count == 1 && isMinorSuit(openingBid.trump);
        }
        return false;
      },
      actions: actionsForPartnerOpeningOneMinor,
    ),
    BiddingRule(
      description: "Response to partner's opening 1NT",
      matcher: (req) {
        final bids = bidActionsRemovingInitialPasses(req.bidHistory);
        if (bids.length == 2 && bids[1].bidType == BidType.pass) {
          final openingBid = bids[0].contractBid!;
          return openingBid.count == 1 && openingBid.trump == null;
        }
        return false;
      },
      actions: actionsForPartnerOpening1NT,
    ),
    BiddingRule(
      description: "Response to Stayman after opening 1NT",
      matcher: (req) {
        final bids = bidActionsRemovingInitialPasses(req.bidHistory);
        if (bids.length == 4 &&
            bids[1].bidType == BidType.pass &&
            bids[3].bidType == BidType.pass) {
          final openingBid = bids[0].contractBid!;
          final responseBid = bids[2].contractBid!;
          return openingBid.count == 1 &&
              openingBid.trump == null &&
              responseBid.count == 2 &&
              responseBid.trump == Suit.clubs;
        }
        return false;
      },
      actions: actionsForStaymanResponse,
    ),
    BiddingRule(
      description: "Response to Jacoby transfer after opening 1NT",
      matcher: (req) {
        final bids = bidActionsRemovingInitialPasses(req.bidHistory);
        if (bids.length == 4 &&
            bids[1].bidType == BidType.pass &&
            bids[3].bidType == BidType.pass) {
          final openingBid = bids[0].contractBid!;
          final responseBid = bids[2].contractBid!;
          return openingBid.count == 1 &&
              openingBid.trump == null &&
              responseBid.count == 2 &&
              (responseBid.trump == Suit.hearts ||
                  responseBid.trump == Suit.diamonds);
        }
        return false;
      },
      actions: actionsForJacobyTransferResponse,
    ),
  ];
}

int _numBidsSinceOpen(List<PlayerBid> bidHistory) {
  int firstBidIndex =
      bidHistory.indexWhere((bid) => bid.action.bidType != BidType.pass);
  if (firstBidIndex == -1) {
    return 0;
  }
  return bidHistory.length - firstBidIndex;
}

List<BidAction> bidActionsRemovingInitialPasses(List<PlayerBid> bids) {
  int firstBidIndex =
      bids.indexWhere((bid) => bid.action.bidType != BidType.pass);
  if (firstBidIndex == -1) {
    return bids.map((b) => b.action).toList();
  }
  return bids.sublist(firstBidIndex).map((b) => b.action).toList();
}

LinkedHashMap<BidAction, BidAnalysis> openingBidActions(BidRequest req) {
  final LinkedHashMap<BidAction, BidAnalysis> result = LinkedHashMap();

  result[BidAction.noTrump(1)] = BidAnalysis(
    description: "Balanced hand with 15-17 points",
    handEstimate: HandEstimate.create(
      pointRange: const Range(low: 15, high: 17),
      suitLengthRanges: notrumpSuitLengthRanges,
    ),
    handMatcher: (hand, counts) => suitCountCanOpenNoTrump(counts),
  );

  result[BidAction.noTrump(2)] = BidAnalysis(
    description: "Balanced hand with 20-22 points",
    handEstimate: HandEstimate.create(
      pointRange: const Range(low: 20, high: 22),
      suitLengthRanges: notrumpSuitLengthRanges,
    ),
    handMatcher: (hand, counts) => suitCountCanOpenNoTrump(counts),
  );

  result[BidAction.noTrump(3)] = BidAnalysis(
    description: "Balanced hand with 23-25 points",
    handEstimate: HandEstimate.create(
      pointRange: const Range(low: 23, high: 25),
      suitLengthRanges: notrumpSuitLengthRanges,
    ),
    handMatcher: (hand, counts) => suitCountCanOpenNoTrump(counts),
  );

  result[BidAction.contract(2, Suit.clubs)] = BidAnalysis(
    description: "22 or more points",
    handEstimate: HandEstimate.create(
      pointRange: const Range(low: 22),
      pointBonusType: HandPointBonusType.suitLength,
    ),
  );

  result[BidAction.contract(1, Suit.clubs)] = BidAnalysis(
    description:
        "13-21 points, clubs is longest suit or 3 clubs and 3 diamonds without 5 card major",
    handEstimate: HandEstimate.create(
      pointRange: const Range(low: 13, high: 21),
      pointBonusType: HandPointBonusType.suitLength,
      suitLengthRanges: {Suit.clubs: const Range(low: 3)},
    ),
    handMatcher: (hand, counts) {
      if (counts[Suit.spades]! >= 5 &&
          counts[Suit.spades]! >= counts[Suit.clubs]!) {
        return false;
      }
      if (counts[Suit.hearts]! >= 5 &&
          counts[Suit.hearts]! >= counts[Suit.clubs]!) {
        return false;
      }
      if (counts[Suit.diamonds]! >= 4 &&
          counts[Suit.diamonds]! >= counts[Suit.clubs]!) {
        return false;
      }
      return true;
    },
  );

  result[BidAction.contract(1, Suit.diamonds)] = BidAnalysis(
    description:
        "13-21 points, diamonds is longest suit or no 5 card major and diamonds is best minor",
    handEstimate: HandEstimate.create(
      pointRange: const Range(low: 13, high: 21),
      pointBonusType: HandPointBonusType.suitLength,
      suitLengthRanges: {Suit.diamonds: const Range(low: 3)},
    ),
    handMatcher: (hand, counts) {
      if (counts[Suit.spades]! >= 5 &&
          counts[Suit.spades]! >= counts[Suit.diamonds]!) {
        return false;
      }
      if (counts[Suit.hearts]! >= 5 &&
          counts[Suit.hearts]! >= counts[Suit.diamonds]!) {
        return false;
      }
      if (counts[Suit.clubs]! > counts[Suit.diamonds]!) {
        return false;
      }
      if (counts[Suit.clubs]! == 3 && counts[Suit.diamonds]! == 3) {
        return false;
      }
      return true;
    },
  );

  result[BidAction.contract(1, Suit.hearts)] = BidAnalysis(
    description: "13-21 points, 5+ hearts",
    handEstimate: HandEstimate.create(
      pointRange: const Range(low: 13, high: 21),
      pointBonusType: HandPointBonusType.suitLength,
      suitLengthRanges: {Suit.hearts: const Range(low: 5)},
    ),
    handMatcher: (hand, counts) {
      if (counts[Suit.spades]! >= counts[Suit.hearts]!) {
        return false;
      }
      if (counts[Suit.diamonds]! > counts[Suit.hearts]!) {
        return false;
      }
      if (counts[Suit.clubs]! > counts[Suit.hearts]!) {
        return false;
      }
      return true;
    },
  );

  result[BidAction.contract(1, Suit.spades)] = BidAnalysis(
    description: "13-21 points, 5+ spades",
    handEstimate: HandEstimate.create(
      pointRange: const Range(low: 13, high: 21),
      pointBonusType: HandPointBonusType.suitLength,
      suitLengthRanges: {Suit.spades: const Range(low: 5)},
    ),
    handMatcher: (hand, counts) {
      if (counts[Suit.hearts]! > counts[Suit.spades]!) {
        return false;
      }
      if (counts[Suit.diamonds]! > counts[Suit.spades]!) {
        return false;
      }
      if (counts[Suit.clubs]! > counts[Suit.spades]!) {
        return false;
      }
      return true;
    },
  );

  for (final suit in Suit.values) {
    result[BidAction.contract(3, suit)] = BidAnalysis(
      description: "Preemptive, 0-10 points, 7+ cards in suit",
      handEstimate: HandEstimate.create(
        pointRange: const Range(low: 0, high: 10),
        suitLengthRanges: {suit: const Range(low: 7)},
      ),
    );
  }

  for (final suit in [Suit.spades, Suit.hearts, Suit.diamonds]) {
    result[BidAction.contract(2, suit)] = BidAnalysis(
      description: "Weak 2-bid, 5-10 points, 6 cards in suit",
      handEstimate: HandEstimate.create(
        pointRange: const Range(low: 5, high: 10),
        suitLengthRanges: {suit: const Range(low: 6, high: 6)},
      ),
    );
  }

  result[BidAction.pass()] = BidAnalysis(
    handEstimate:
        HandEstimate.create(pointRange: const Range(low: 0, high: 11)),
    description: "Less than 12 points",
  );

  return result;
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

const notrumpSuitLengthRanges = {
  Suit.spades: Range(low: 2, high: 5),
  Suit.hearts: Range(low: 2, high: 5),
  Suit.diamonds: Range(low: 2, high: 5),
  Suit.clubs: Range(low: 2, high: 5),
};

LinkedHashMap<BidAction, BidAnalysis> actionsForOpponentOpeningOneBid(
    BidRequest req) {
  final openingBid = req.bidHistory.last.action.contractBid!;
  final openedSuit = openingBid.trump!;
  final LinkedHashMap<BidAction, BidAnalysis> result = LinkedHashMap();

  result[BidAction.noTrump(1)] = BidAnalysis(
    description: "15-17 points with balanced hand and stopper in opening suit",
    handEstimate: HandEstimate.create(
      pointRange: const Range(low: 15, high: 17),
      suitLengthRanges: notrumpSuitLengthRanges,
    ),
    handMatcher: (hand, suitCounts) {
      return suitCountCanOpenNoTrump(suitCounts) &&
          hasStopperInSuit(hand, openedSuit);
    },
  );

  result[BidAction.double()] = BidAnalysis(
    description:
        "Takeout double with 12+ points and support for other suits, or 17+ points",
    handEstimate: HandEstimate.create(
      pointRange: const Range(low: 12),
    ),
    handMatcher: (hand, counts) {
      if (highCardPoints(hand) >= 17) {
        return true;
      }
      if (hasShortageInSuit(counts, openingBid.trump!) &&
          hasSupportForUnbidSuits(counts, openingBid.trump!)) {
        return true;
      }
      return false;
    },
  );

  for (final overcallSuit in [
    Suit.spades,
    Suit.hearts,
    Suit.diamonds,
    Suit.clubs
  ]) {
    if (overcallSuit == openedSuit) continue;
    if (isSuitHigherThan(overcallSuit, openedSuit)) {
      // Check for preempts first.
      result[BidAction.contract(3, overcallSuit)] = BidAnalysis(
        description: "Preemptive, 7+ cards in suit, 5-10 points",
        handEstimate: HandEstimate.create(
          pointRange: const Range(low: 5, high: 10),
          suitLengthRanges: {overcallSuit: const Range(low: 7)},
        ),
      );
      result[BidAction.contract(2, overcallSuit)] = BidAnalysis(
        description: "Preemptive, 6 cards in suit, 5-10 points",
        handEstimate: HandEstimate.create(
          pointRange: const Range(low: 5, high: 10),
          suitLengthRanges: {overcallSuit: const Range(low: 6, high: 6)},
        ),
      );
      // TODO: Check that there's not a longer suit? Rare but possible.
      result[BidAction.contract(1, overcallSuit)] = BidAnalysis(
        description: "10-16 points, at least 5 cards in suit",
        handEstimate: HandEstimate.create(
          pointBonusType: HandPointBonusType.suitLength,
          pointRange: const Range(low: 11, high: 18),
          suitLengthRanges: {overcallSuit: const Range(low: 5)},
        ),
      );
    } else {
      result[BidAction.contract(4, overcallSuit)] = BidAnalysis(
        description: "Preemptive, 7+ cards in suit, 7-10 points",
        handEstimate: HandEstimate.create(
          pointRange: const Range(low: 7, high: 10),
          suitLengthRanges: {overcallSuit: const Range(low: 7)},
        ),
      );
      result[BidAction.contract(3, overcallSuit)] = BidAnalysis(
        description: "Preemptive, 6 cards in suit, 7-10 points",
        handEstimate: HandEstimate.create(
          pointRange: const Range(low: 7, high: 10),
          suitLengthRanges: {overcallSuit: const Range(low: 6, high: 6)},
        ),
      );
      result[BidAction.contract(2, overcallSuit)] = BidAnalysis(
        description: "13-16 points, at least 5 cards in suit",
        handEstimate: HandEstimate.create(
          pointBonusType: HandPointBonusType.suitLength,
          pointRange: const Range(low: 13, high: 18),
          suitLengthRanges: {overcallSuit: const Range(low: 5)},
        ),
      );
    }
  }

  result[BidAction.pass()] = BidAnalysis(
    description: "",
    handEstimate: HandEstimate.create(pointRange: const Range(high: 16)),
  );

  return result;
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

LinkedHashMap<BidAction, BidAnalysis> actionsForPartnerOpeningOneMajor(
    BidRequest req) {
  final openingBid =
      req.bidHistory[req.bidHistory.length - 2].action.contractBid!;
  final openedSuit = openingBid.trump!;
  final LinkedHashMap<BidAction, BidAnalysis> bids = LinkedHashMap();

  bids[BidAction.contract(4, openedSuit)] = BidAnalysis(
    description: "6-9 points, 5+ card trump support",
    handEstimate: HandEstimate.create(
      pointBonusType: HandPointBonusType.suitLength,
      pointRange: const Range(low: 6, high: 9),
      suitLengthRanges: {openedSuit: const Range(low: 5)},
    ),
  );
  bids[BidAction.contract(3, openedSuit)] = BidAnalysis(
    description: "Limit raise: 10-12 points, 3+ card trump support",
    handEstimate: HandEstimate.create(
      pointBonusType: HandPointBonusType.suitLength,
      pointRange: const Range(low: 10, high: 12),
      suitLengthRanges: {openedSuit: const Range(low: 3)},
    ),
  );
  bids[BidAction.contract(2, openedSuit)] = BidAnalysis(
    description: "6-9 points, 3+ card trump support",
    handEstimate: HandEstimate.create(
      pointBonusType: HandPointBonusType.suitLength,
      pointRange: const Range(low: 6, high: 9),
      suitLengthRanges: {openedSuit: const Range(low: 3)},
    ),
  );

  {
    var splinterBid = ContractBid(3, openedSuit);
    while (!(splinterBid.count == 4 && splinterBid.trump == openedSuit)) {
      splinterBid = splinterBid.nextHigherBid();
      if (splinterBid.trump != null && splinterBid.trump != openedSuit) {
        bids[BidAction.withBid(splinterBid)] = BidAnalysis(
          description:
              "Splinter: 11+ points, 4+ card trump support, singleton or void in bid suit",
          handEstimate: HandEstimate.create(
            pointRange: const Range(low: 11),
            suitLengthRanges: {
              openedSuit: const Range(low: 4),
              splinterBid.trump!: const Range(high: 1),
            },
          ),
        );
      }
    }
  }

  if (openedSuit == Suit.hearts) {
    bids[BidAction.contract(1, Suit.spades)] = BidAnalysis(
      description: "6+ points, 4+ spades",
      handEstimate: HandEstimate.create(
        pointBonusType: HandPointBonusType.suitLength,
        pointRange: const Range(low: 6),
        suitLengthRanges: const {Suit.spades: Range(low: 4)},
      ),
    );
  }

  {
    final ntSuitRanges = openedSuit == Suit.hearts
        ? const {Suit.hearts: Range(high: 2), Suit.spades: Range(high: 3)}
        : const {Suit.spades: Range(high: 2)};
    bids[BidAction.noTrump(1)] = BidAnalysis(
      description: "6-9 points",
      handEstimate: HandEstimate.create(
        pointBonusType: HandPointBonusType.suitLength,
        pointRange: const Range(low: 6, high: 9),
        suitLengthRanges: ntSuitRanges,
      ),
    );
  }

  // Prioritize 2H over minors if responding to 1S.
  if (openedSuit == Suit.spades) {
    bids[BidAction.contract(2, Suit.hearts)] = BidAnalysis(
      description: "10+ points, 5+ hearts",
      handEstimate: HandEstimate.create(
        pointBonusType: HandPointBonusType.suitLength,
        pointRange: const Range(low: 10),
        suitLengthRanges: const {Suit.hearts: Range(low: 5)},
      ),
    );
  }

  {
    final suitRangesFor2Diamonds = {Suit.diamonds: const Range(low: 4)};
    if (openedSuit == Suit.hearts) {
      suitRangesFor2Diamonds[Suit.spades] = const Range(high: 3);
    }
    bids[BidAction.contract(2, Suit.diamonds)] = BidAnalysis(
      description:
          "10+ points, 4+ diamonds, clubs shorter or equal to diamonds",
      handEstimate: HandEstimate.create(
        pointBonusType: HandPointBonusType.suitLength,
        pointRange: const Range(low: 10),
        suitLengthRanges: suitRangesFor2Diamonds,
      ),
      handMatcher: (hand, counts) {
        if (counts[Suit.clubs]! > counts[Suit.diamonds]!) {
          return false;
        }
        return true;
      },
    );
  }

  // For 2C, it's possible to have only 3 clubs, e.g. ♠A72 ♥9862 ♦Q93 ♣AK6
  // after parter opens 1S. Too strong for 3S, not enough spades for Jacoby 2NT,
  // so have to bid 2C.
  {
    final suitRangesFor2Clubs = {Suit.clubs: const Range(low: 3)};
    if (openedSuit == Suit.hearts) {
      suitRangesFor2Clubs[Suit.spades] = const Range(high: 3);
    }
    bids[BidAction.contract(2, Suit.clubs)] = BidAnalysis(
      description: "10+ points, 4+ clubs, diamonds shorter than clubs",
      handEstimate: HandEstimate.create(
        pointBonusType: HandPointBonusType.suitLength,
        pointRange: const Range(low: 10),
        suitLengthRanges: suitRangesFor2Clubs,
      ),
      handMatcher: (hand, counts) {
        if (counts[Suit.diamonds]! >= counts[Suit.clubs]! &&
            counts[Suit.clubs]! > 3) {
          return false;
        }
        return true;
      },
    );
  }

  {
    // 2NT is Jacoby if responder hasn't previously passed, invitational if they have passed.
    bool hasPreviouslyPassed = req.bidHistory.length >= 4;
    if (hasPreviouslyPassed) {
      if (openedSuit == Suit.hearts) {
        bids[BidAction.noTrump(2)] = BidAnalysis(
            description: "10-12 points, <3 hearts, <4 spades, no 5-card minor",
            handEstimate: HandEstimate.create(
              pointRange: const Range(low: 10, high: 12),
              suitLengthRanges: {
                Suit.clubs: const Range(high: 4),
                Suit.diamonds: const Range(high: 4),
                Suit.hearts: const Range(high: 2),
                Suit.spades: const Range(high: 3),
              },
            ));
      } else {
        bids[BidAction.noTrump(2)] = BidAnalysis(
            description: "10-12 points, <3 spades, no 5-card suit",
            handEstimate: HandEstimate.create(
              pointRange: const Range(low: 10, high: 12),
              suitLengthRanges: {
                Suit.clubs: const Range(high: 4),
                Suit.diamonds: const Range(high: 4),
                Suit.hearts: const Range(high: 4),
                Suit.spades: const Range(high: 2),
              },
            ));
      }
    } else {
      bids[BidAction.noTrump(2)] = BidAnalysis(
        description: "Jacoby 2NT: 13+ points, 4+ card trump support",
        handEstimate: HandEstimate.create(
          pointRange: const Range(low: 13),
          suitLengthRanges: {
            openedSuit: const Range(low: 4),
          },
        ),
      );
    }
  }

  return bids;
}

LinkedHashMap<BidAction, BidAnalysis> actionsForPartnerOpeningOneMinor(
    BidRequest req) {
  final openingBid =
      req.bidHistory[req.bidHistory.length - 2].action.contractBid!;
  final LinkedHashMap<BidAction, BidAnalysis> bids = LinkedHashMap();
  final openedSuit = openingBid.trump!;

  if (openedSuit == Suit.clubs) {
    bids[BidAction.contract(1, Suit.diamonds)] = BidAnalysis(
      description: "6+ points, 4+ diamonds, no major with as many diamonds",
      handEstimate: HandEstimate.create(
        pointBonusType: HandPointBonusType.suitLength,
        pointRange: const Range(low: 6),
        suitLengthRanges: {Suit.diamonds: const Range(low: 4)},
      ),
      handMatcher: (hand, suitCounts) {
        return suitCounts[Suit.hearts]! < suitCounts[Suit.diamonds]! &&
            suitCounts[Suit.spades]! < suitCounts[Suit.diamonds]!;
      },
    );
  }

  bids[BidAction.contract(1, Suit.hearts)] = BidAnalysis(
    description: "6+ points, 4+ hearts",
    handEstimate: HandEstimate.create(
      pointBonusType: HandPointBonusType.suitLength,
      pointRange: const Range(low: 6),
      suitLengthRanges: {Suit.hearts: const Range(low: 4)},
    ),
    handMatcher: (hand, suitCounts) {
      return suitCounts[Suit.hearts]! >= suitCounts[Suit.spades]!;
    },
  );

  bids[BidAction.contract(1, Suit.spades)] = BidAnalysis(
    description: "6+ points, 4+ spades",
    handEstimate: HandEstimate.create(
      pointBonusType: HandPointBonusType.suitLength,
      pointRange: const Range(low: 6),
      suitLengthRanges: const {Suit.spades: Range(low: 4)},
    ),
  );

  // Raise with 5 card support and no 4-card major.
  bids[BidAction.contract(2, openedSuit)] = BidAnalysis(
    description: "6-9 points, 5+ card trump support, no 4 card major",
    handEstimate: HandEstimate.create(
      pointBonusType: HandPointBonusType.suitLength,
      pointRange: const Range(low: 6, high: 9),
      suitLengthRanges: {
        openedSuit: const Range(low: 5),
        Suit.hearts: const Range(high: 3),
        Suit.spades: const Range(high: 3),
      },
    ),
  );
  bids[BidAction.contract(2, openedSuit)] = BidAnalysis(
    description: "10-12 points, 5+ card trump support, no 4 card major",
    handEstimate: HandEstimate.create(
      pointBonusType: HandPointBonusType.suitLength,
      pointRange: const Range(low: 10, high: 12),
      suitLengthRanges: {
        openedSuit: const Range(low: 5),
        Suit.hearts: const Range(high: 3),
        Suit.spades: const Range(high: 3),
      },
    ),
  );

  if (openedSuit == Suit.diamonds) {
    bids[BidAction.contract(2, Suit.clubs)] = BidAnalysis(
      description: "5+ clubs, 10+ points, no 4 card major",
      handEstimate: HandEstimate.create(
        pointBonusType: HandPointBonusType.suitLength,
        pointRange: const Range(low: 10, high: 12),
        suitLengthRanges: {
          Suit.clubs: const Range(low: 5),
          Suit.hearts: const Range(high: 3),
          Suit.spades: const Range(high: 3),
        },
      ),
    );
  }

  {
    Map<Suit, Range> ntSuitRanges = {
      Suit.hearts: const Range(high: 3),
      Suit.spades: const Range(high: 3),
    };
    if (openedSuit == Suit.clubs) {
      ntSuitRanges[Suit.diamonds] = const Range(high: 4);
    }
    bids[BidAction.noTrump(1)] = BidAnalysis(
      description: "6-9 points, no 4 card major",
      handEstimate: HandEstimate.create(
        pointBonusType: HandPointBonusType.suitLength,
        pointRange: const Range(low: 6, high: 9),
        suitLengthRanges: ntSuitRanges,
      ),
    );
    bids[BidAction.noTrump(2)] = BidAnalysis(
      description: "10-12 points, no 4 card major",
      handEstimate: HandEstimate.create(
        pointBonusType: HandPointBonusType.suitLength,
        pointRange: const Range(low: 10, high: 12),
        suitLengthRanges: ntSuitRanges,
      ),
    );
    bids[BidAction.noTrump(3)] = BidAnalysis(
      description: "13-15 points, no 4 card major",
      handEstimate: HandEstimate.create(
        pointBonusType: HandPointBonusType.suitLength,
        pointRange: const Range(low: 13, high: 15),
        suitLengthRanges: ntSuitRanges,
      ),
    );
    // Not a real convention, but for now 3NT is balanced with 16+ points.
    bids[BidAction.noTrump(3)] = BidAnalysis(
      description: "16+ points, no 4 card major",
      handEstimate: HandEstimate.create(
        pointBonusType: HandPointBonusType.suitLength,
        pointRange: const Range(low: 16),
        suitLengthRanges: ntSuitRanges,
      ),
    );
  }

  return bids;
}

LinkedHashMap<BidAction, BidAnalysis> actionsForPartnerOpening1NT(
    BidRequest req) {
  final LinkedHashMap<BidAction, BidAnalysis> bids = LinkedHashMap();

  // Stayman if 4+ in both majors, or exactly 4 in one.
  bids[BidAction.contract(2, Suit.clubs)] = BidAnalysis(
    description: "Stayman, requests parter to bid 4-card major",
    handEstimate: HandEstimate.create(
      pointRange: const Range(low: 8),
    ),
    handMatcher: (hand, suitCounts) {
      int h = suitCounts[Suit.hearts]!;
      int s = suitCounts[Suit.spades]!;
      return (h >= 4 && s >= 4) || (h == 4 && s < 4) || (s == 4 && h < 4);
    },
  );

  // Jacoby transfer, prefer spades if 5-5.
  bids[BidAction.contract(2, Suit.hearts)] = BidAnalysis(
    description: "Jacoby transfer, 5+ spades",
    handEstimate: HandEstimate.create(
      suitLengthRanges: const {Suit.spades: Range(low: 5)},
    ),
    handMatcher: (hand, suitCounts) {
      return suitCounts[Suit.hearts]! <= suitCounts[Suit.spades]!;
    },
  );

  bids[BidAction.contract(2, Suit.diamonds)] = BidAnalysis(
    description: "Jacoby transfer, 5+ hearts",
    handEstimate: HandEstimate.create(
      suitLengthRanges: const {Suit.hearts: Range(low: 5)},
    ),
  );

  // Ignore minors for now, could do 2S->3C.

  bids[BidAction.noTrump(2)] = BidAnalysis(
    description: "8-10 points, no 4-card major",
    handEstimate: HandEstimate.create(
      pointRange: const Range(low: 8, high: 10),
      suitLengthRanges: const {
        Suit.hearts: Range(high: 3),
        Suit.spades: Range(high: 3),
      },
    ),
  );

  bids[BidAction.noTrump(3)] = BidAnalysis(
    description: "11-15 points, no 4-card major",
    handEstimate: HandEstimate.create(
      pointRange: const Range(low: 11, high: 15),
      suitLengthRanges: const {
        Suit.hearts: Range(high: 3),
        Suit.spades: Range(high: 3),
      },
    ),
  );

  // Could do Gerber 4C, for now just 4NT invitational.
  bids[BidAction.noTrump(4)] = BidAnalysis(
    description: "16-17 points, invitational to slam",
    handEstimate: HandEstimate.create(
      pointRange: const Range(low: 16, high: 17),
      suitLengthRanges: const {
        Suit.hearts: Range(high: 3),
        Suit.spades: Range(high: 3),
      },
    ),
  );

  bids[BidAction.noTrump(6)] = BidAnalysis(
    description: "18+ points",
    handEstimate: HandEstimate.create(
      pointRange: const Range(low: 18),
      suitLengthRanges: const {
        Suit.hearts: Range(high: 3),
        Suit.spades: Range(high: 3),
      },
    ),
  );

  // 5NT invitational to 7?

  return bids;
}

LinkedHashMap<BidAction, BidAnalysis> actionsForStaymanResponse(
    BidRequest req) {
  final LinkedHashMap<BidAction, BidAnalysis> bids = LinkedHashMap();

  // 2D = no 4-card major
  bids[BidAction.contract(2, Suit.diamonds)] = BidAnalysis(
    description: "No 4-card major",
    handEstimate: HandEstimate.create(
      suitLengthRanges: {
        Suit.hearts: const Range(high: 3),
        Suit.spades: const Range(high: 3),
      },
    ),
    handMatcher: (hand, suitCounts) {
      return suitCounts[Suit.hearts]! < 4 && suitCounts[Suit.spades]! < 4;
    },
  );

  // 2H = 4 hearts, may have 4 spades
  bids[BidAction.contract(2, Suit.hearts)] = BidAnalysis(
    description: "4+ hearts, may also have 4 spades",
    handEstimate: HandEstimate.create(
      suitLengthRanges: {
        Suit.hearts: const Range(low: 4),
        Suit.spades: const Range(high: 4),
      },
    ),
  );

  // 2S = 4 spades, no 4 hearts
  bids[BidAction.contract(2, Suit.spades)] = BidAnalysis(
    description: "4+ spades, less than 4 hearts",
    handEstimate: HandEstimate.create(
      suitLengthRanges: {
        Suit.hearts: const Range(high: 3),
        Suit.spades: const Range(low: 4),
      },
    ),
  );

  return bids;
}

LinkedHashMap<BidAction, BidAnalysis> actionsForJacobyTransferResponse(
    BidRequest req) {
  final LinkedHashMap<BidAction, BidAnalysis> bids = LinkedHashMap();
  final transferBid =
      req.bidHistory[req.bidHistory.length - 2].action.contractBid!;

  // If partner bid 2H, they have 5+ spades, so we bid 2S.
  // If partner bid 2D, they have 5+ hearts, so we bid 2H.
  final targetSuit =
      transferBid.trump == Suit.hearts ? Suit.spades : Suit.hearts;

  bids[BidAction.contract(3, targetSuit)] = BidAnalysis(
    description: "Super-accept Jacoby transfer with 4+ card support",
    handEstimate: HandEstimate.create(
      pointRange: const Range(low: 16),
      suitLengthRanges: {
        targetSuit: const Range(low: 4),
      },
    ),
  );

  bids[BidAction.contract(2, targetSuit)] = BidAnalysis(
    description: "Accept Jacoby transfer",
    handEstimate: HandEstimate.create(),
  );

  return bids;
}
