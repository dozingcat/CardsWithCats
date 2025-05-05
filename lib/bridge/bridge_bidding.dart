import 'dart:collection';

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

LinkedHashMap<BidAction, BidAnalysis>? getBidAnalysesForNextBid(
    List<PlayerBid> bidHistory) {
  int bidsSinceOpen = _numBidsSinceOpen(bidHistory);
  if (bidsSinceOpen == 0) {
    print("Opening bid");
    return openingBidAnalyses();
  } else if (bidsSinceOpen == 1) {
    ContractBid openingBid =
        bidHistory[bidHistory.length - 1].action.contractBid!;
    if (openingBid.count == 1 && openingBid.trump != null) {
      print("Opponent opened 1 of suit");
      return bidAnalysisForResponseToOpponentOpeningOneBid(openingBid);
    }
  } else if (bidsSinceOpen == 2) {
    ContractBid openingBid =
        bidHistory[bidHistory.length - 2].action.contractBid!;
    if (openingBid.count == 1 && bidHistory[bidHistory.length - 1].action.bidType == BidType.pass) {
      print("Partner opened 1 of suit, opponent passed");
      return bidAnalysisForResponseToPartnerOpeningOneBid(bidHistory);
    }
  }
  return null;
}

PlayerBid chooseBid(BidRequest req) {
  final analyses = getBidAnalysesForNextBid(req.bidHistory);
  final counts = suitCounts(req.hand);
  if (analyses != null) {
    for (final bid in analyses.keys) {
      // print("Checking $bid");
      if (analyses[bid]!.matches(req.hand, counts)) {
        // print("Making bid: $bid");
        return PlayerBid(req.playerIndex, bid);
      }
    }
  }

  final handEstimates = handEstimatesForBidSequence(req.bidHistory);
  print(handEstimates);
  return makeBidUsingHandEstimates(req, handEstimates, counts);
}

PlayerBid makeBidUsingHandEstimates(BidRequest req, List<HandEstimate> handEstimates, Map<Suit, int> suitCounts) {
  // Do we have a major fit?
  HandEstimate partnerEstimate = handEstimates[(req.playerIndex + 2) % 4];
  // TODO: adjust points for hand distribution
  Range combinedPointRange = partnerEstimate.pointRange.plusConstant(highCardPoints(req.hand));
  Range combinedSuitRange(Suit s) => partnerEstimate.suitLengthRanges[s]!.plusConstant(suitCounts[s]!);

  Suit? majorSuitFit() {
    Range totalSpades = combinedSuitRange(Suit.spades);
    Range totalHearts = combinedSuitRange(Suit.hearts);
    if (totalHearts.low! >= 8 && totalHearts.low! > totalSpades.low!) {
      return Suit.hearts;
    } else if (totalSpades.low! >= 8) {
      return Suit.spades;
    }
    return null;
  }

  Suit? majorFitSuit = majorSuitFit();
  if (majorFitSuit != null) {
    int numTrumps = combinedSuitRange(majorFitSuit).low!;
    int pointsNeededForGame = 26 - 2 * (numTrumps - 8);
    if (combinedPointRange.low! >= pointsNeededForGame) {
      final targetBid = ContractBid(4, majorFitSuit);
      final currentBid = lastContractBid(req.bidHistory);
      if (currentBid == null || targetBid.isHigherThan(currentBid.action.contractBid!)) {
        return PlayerBid(req.playerIndex, BidAction.withBid(targetBid));
      }
    }
  }

  return PlayerBid(req.playerIndex, BidAction.pass());
}

List<HandEstimate> handEstimatesForBidSequence(List<PlayerBid> bidSequence) {
  final result = List.generate(4, (i) => HandEstimate());
  List<PlayerBid> partialBidHistory = [];
  for (int i = 0; i < bidSequence.length; i++) {
    final currentBid = bidSequence[i];
    int currentPlayer = currentBid.player;
    final analyses = getBidAnalysesForNextBid(partialBidHistory);
    if (analyses != null) {
      final selectedAnalysis = analyses[currentBid.action];
      if (selectedAnalysis != null) {
        result[currentPlayer] = result[currentPlayer]
            .combineOrReplace(selectedAnalysis.handEstimate);
      }
    }
    partialBidHistory.add(bidSequence[i]);
  }
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

const notrumpSuitLengthRanges = {
  Suit.spades: Range(low: 2, high: 5),
  Suit.hearts: Range(low: 2, high: 5),
  Suit.diamonds: Range(low: 2, high: 5),
  Suit.clubs: Range(low: 2, high: 5),
};

LinkedHashMap<BidAction, BidAnalysis> openingBidAnalyses() {
  final LinkedHashMap<BidAction, BidAnalysis> result = LinkedHashMap();

  result[BidAction.noTrump(1)] = BidAnalysis(
    description: "Balanced hand with 15-17 points",
    handEstimate: HandEstimate(
      pointRange: const Range(low: 15, high: 17),
      suitLengthRanges: notrumpSuitLengthRanges,
    ),
    handMatcher: (hand, counts) => suitCountCanOpenNoTrump(counts),
  );

  result[BidAction.noTrump(2)] = BidAnalysis(
    description: "Balanced hand with 20-22 points",
    handEstimate: HandEstimate(
      pointRange: const Range(low: 20, high: 22),
      suitLengthRanges: notrumpSuitLengthRanges,
    ),
    handMatcher: (hand, counts) => suitCountCanOpenNoTrump(counts),
  );

  result[BidAction.noTrump(3)] = BidAnalysis(
    description: "Balanced hand with 23-25 points",
    handEstimate: HandEstimate(
      pointRange: const Range(low: 23, high: 25),
      suitLengthRanges: notrumpSuitLengthRanges,
    ),
    handMatcher: (hand, counts) => suitCountCanOpenNoTrump(counts),
  );

  result[BidAction.contract(2, Suit.clubs)] = BidAnalysis(
    description: "22 or more points",
    handEstimate: HandEstimate(
      pointRange: const Range(low: 22),
      pointBonusType: HandPointBonusType.suitLength,
    ),
  );

  result[BidAction.contract(1, Suit.clubs)] = BidAnalysis(
    description:
        "13-21 points, clubs is longest suit or 3 clubs and 3 diamonds without 5 card major",
    handEstimate: HandEstimate(
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
    handEstimate: HandEstimate(
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
    handEstimate: HandEstimate(
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
    handEstimate: HandEstimate(
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
      handEstimate: HandEstimate(
        pointRange: const Range(low: 0, high: 10),
        suitLengthRanges: {suit: const Range(low: 7)},
      ),
    );
  }

  for (final suit in [Suit.spades, Suit.hearts, Suit.diamonds]) {
    result[BidAction.contract(2, suit)] = BidAnalysis(
      description: "Weak 2-bid, 5-10 points, 6 cards in suit",
      handEstimate: HandEstimate(
        pointRange: const Range(low: 5, high: 10),
        suitLengthRanges: {suit: const Range(low: 6, high: 6)},
      ),
    );
  }

  result[BidAction.pass()] = BidAnalysis(
    handEstimate: HandEstimate(pointRange: const Range(low: 0, high: 11)),
    description: "Less than 12 points",
  );

  return result;
}

LinkedHashMap<BidAction, BidAnalysis>
    bidAnalysisForResponseToOpponentOpeningOneBid(ContractBid openingBid) {
  final openedSuit = openingBid.trump!;
  final LinkedHashMap<BidAction, BidAnalysis> result = LinkedHashMap();

  result[BidAction.noTrump(1)] = BidAnalysis(
    description: "15-17 points with balanced hand and stopper in opening suit",
    handEstimate: HandEstimate(
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
    handEstimate: HandEstimate(
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
        handEstimate: HandEstimate(
          pointRange: const Range(low: 5, high: 10),
          suitLengthRanges: {overcallSuit: const Range(low: 7)},
        ),
      );
      result[BidAction.contract(2, overcallSuit)] = BidAnalysis(
        description: "Preemptive, 6 cards in suit, 5-10 points",
        handEstimate: HandEstimate(
          pointRange: const Range(low: 5, high: 10),
          suitLengthRanges: {overcallSuit: const Range(low: 6, high: 6)},
        ),
      );
      // TODO: Check that there's not a longer suit? Rare but possible.
      result[BidAction.contract(1, overcallSuit)] = BidAnalysis(
        description: "10-16 points, at least 5 cards in suit",
        handEstimate: HandEstimate(
          pointBonusType: HandPointBonusType.suitLength,
          pointRange: const Range(low: 11, high: 18),
          suitLengthRanges: {overcallSuit: const Range(low: 5)},
        ),
      );
    } else {
      result[BidAction.contract(4, overcallSuit)] = BidAnalysis(
        description: "Preemptive, 7+ cards in suit, 7-10 points",
        handEstimate: HandEstimate(
          pointRange: const Range(low: 7, high: 10),
          suitLengthRanges: {overcallSuit: const Range(low: 7)},
        ),
      );
      result[BidAction.contract(3, overcallSuit)] = BidAnalysis(
        description: "Preemptive, 6 cards in suit, 7-10 points",
        handEstimate: HandEstimate(
          pointRange: const Range(low: 7, high: 10),
          suitLengthRanges: {overcallSuit: const Range(low: 6, high: 6)},
        ),
      );
      result[BidAction.contract(2, overcallSuit)] = BidAnalysis(
        description: "13-16 points, at least 5 cards in suit",
        handEstimate: HandEstimate(
          pointBonusType: HandPointBonusType.suitLength,
          pointRange: const Range(low: 13, high: 18),
          suitLengthRanges: {overcallSuit: const Range(low: 5)},
        ),
      );
    }
  }

  result[BidAction.pass()] = BidAnalysis(
    description: "",
    handEstimate: HandEstimate(pointRange: const Range(high: 16)),
  );

  return result;
}

LinkedHashMap<BidAction, BidAnalysis> bidAnalysesForResponseToPartnerOpeningOneMajor(List<PlayerBid> bidHistory) {
  final openingBid = bidHistory[bidHistory.length - 2].action.contractBid!;
  final openedSuit = openingBid.trump!;
  final LinkedHashMap<BidAction, BidAnalysis> bids = LinkedHashMap();

  bids[BidAction.contract(4, openedSuit)] = BidAnalysis(
    description: "6-9 points, 5+ card trump support",
    handEstimate: HandEstimate(
      pointBonusType: HandPointBonusType.suitLength,
      pointRange: const Range(low: 6, high: 9),
      suitLengthRanges: {openedSuit: const Range(low: 5)},
    ),
  );
  bids[BidAction.contract(3, openedSuit)] = BidAnalysis(
    description: "Limit raise: 10-12 points, 3+ card trump support",
    handEstimate: HandEstimate(
      pointBonusType: HandPointBonusType.suitLength,
      pointRange: const Range(low: 10, high: 12),
      suitLengthRanges: {openedSuit: const Range(low: 3)},
    ),
  );
  bids[BidAction.contract(2, openedSuit)] = BidAnalysis(
    description: "6-9 points, 3+ card trump support",
    handEstimate: HandEstimate(
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
          description: "Splinter: 11+ points, 4+ card trump support, singleton or void in bid suit",
          handEstimate: HandEstimate(
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
      handEstimate: HandEstimate(
        pointBonusType: HandPointBonusType.suitLength,
        pointRange: const Range(low: 6),
        suitLengthRanges: const {Suit.spades: Range(low: 4)},
      ),
    );
  }

  {
    final ntSuitRanges = openedSuit == Suit.hearts ?
        const {Suit.hearts: Range(high: 2), Suit.spades: Range(high: 3)} :
        const {Suit.spades: Range(high: 2)};
    bids[BidAction.noTrump(1)] = BidAnalysis(
      description: "6-9 points",
      handEstimate: HandEstimate(
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
      handEstimate: HandEstimate(
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
      description: "10+ points, 4+ diamonds, clubs shorter or equal to diamonds",
      handEstimate: HandEstimate(
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
      handEstimate: HandEstimate(
        pointBonusType: HandPointBonusType.suitLength,
        pointRange: const Range(low: 10),
        suitLengthRanges: suitRangesFor2Clubs,
      ),
      handMatcher: (hand, counts) {
        if (counts[Suit.diamonds]! >= counts[Suit.clubs]! && counts[Suit.clubs]! > 3) {
          return false;
        }
        return true;
      },
    );
  }

  {
    // 2NT is Jacoby if responder hasn't previously passed, invitational if they have passed.
    bool hasPreviouslyPassed = bidHistory.length >= 4;
    if (hasPreviouslyPassed) {
      if (openedSuit == Suit.hearts) {
        bids[BidAction.noTrump(2)] = BidAnalysis(
            description: "10-12 points, <3 hearts, <4 spades, no 5-card minor",
            handEstimate: HandEstimate(
              pointRange: const Range(low: 10, high: 12),
              suitLengthRanges: {
                Suit.clubs: const Range(high: 4),
                Suit.diamonds: const Range(high: 4),
                Suit.hearts: const Range(high: 2),
                Suit.spades: const Range(high: 3),
              },
            )
        );
      } else {
        bids[BidAction.noTrump(2)] = BidAnalysis(
            description: "10-12 points, <3 spades, no 5-card suit",
            handEstimate: HandEstimate(
              pointRange: const Range(low: 10, high: 12),
              suitLengthRanges: {
                Suit.clubs: const Range(high: 4),
                Suit.diamonds: const Range(high: 4),
                Suit.hearts: const Range(high: 4),
                Suit.spades: const Range(high: 2),
              },
            )
        );
      }
    } else {
      bids[BidAction.noTrump(2)] = BidAnalysis(
        description: "Jacoby 2NT: 13+ points, 4+ card trump support",
        handEstimate: HandEstimate(
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

LinkedHashMap<BidAction, BidAnalysis> bidAnalysesForResponseToPartnerOpeningOneMinor(List<PlayerBid> bidHistory) {
  LinkedHashMap<BidAction, BidAnalysis> bids = LinkedHashMap();
  final openingBid = bidHistory[bidHistory.length - 2].action.contractBid!;
  final openedSuit = openingBid.trump!;

  if (openedSuit == Suit.clubs) {
    bids[BidAction.contract(1, Suit.diamonds)] = BidAnalysis(
      description: "6+ points, 4+ diamonds, no major with as many diamonds",
      handEstimate: HandEstimate(
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
    handEstimate: HandEstimate(
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
    handEstimate: HandEstimate(
      pointBonusType: HandPointBonusType.suitLength,
      pointRange: const Range(low: 6),
      suitLengthRanges: const {Suit.spades: Range(low: 4)},
    ),
  );

  // Raise with 5 card support and no 4-card major.
  bids[BidAction.contract(2, openedSuit)] = BidAnalysis(
    description: "6-9 points, 5+ card trump support, no 4 card major",
    handEstimate: HandEstimate(
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
    handEstimate: HandEstimate(
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
      handEstimate: HandEstimate(
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
      handEstimate: HandEstimate(
        pointBonusType: HandPointBonusType.suitLength,
        pointRange: const Range(low: 6, high: 9),
        suitLengthRanges: ntSuitRanges,
      ),
    );
    bids[BidAction.noTrump(2)] = BidAnalysis(
      description: "10-12 points, no 4 card major",
      handEstimate: HandEstimate(
        pointBonusType: HandPointBonusType.suitLength,
        pointRange: const Range(low: 10, high: 12),
        suitLengthRanges: ntSuitRanges,
      ),
    );
    bids[BidAction.noTrump(3)] = BidAnalysis(
      description: "13-15 points, no 4 card major",
      handEstimate: HandEstimate(
        pointBonusType: HandPointBonusType.suitLength,
        pointRange: const Range(low: 13, high: 15),
        suitLengthRanges: ntSuitRanges,
      ),
    );
    // Not a real convention, but for now 4NT is balanced with 16+ points.
    bids[BidAction.noTrump(3)] = BidAnalysis(
      description: "16+ points, no 4 card major",
      handEstimate: HandEstimate(
        pointBonusType: HandPointBonusType.suitLength,
        pointRange: const Range(low: 16),
        suitLengthRanges: ntSuitRanges,
      ),
    );
  }

  return bids;
}

LinkedHashMap<BidAction, BidAnalysis> bidAnalysesForResponseToPartnerOpening1NT(List<PlayerBid> bidHistory) {
  LinkedHashMap<BidAction, BidAnalysis> bids = LinkedHashMap();

  // Stayman if 4+ in both majors, or exactly 4 in one.
  bids[BidAction.contract(2, Suit.clubs)] = BidAnalysis(
    description: "Stayman, requests parter to bid 4-card major",
    handEstimate: HandEstimate(
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
    handEstimate: HandEstimate(
      suitLengthRanges: const {Suit.spades: Range(low: 5)},
    ),
    handMatcher: (hand, suitCounts) {
      return suitCounts[Suit.hearts]! <= suitCounts[Suit.spades]!;
    },
  );

  bids[BidAction.contract(2, Suit.diamonds)] = BidAnalysis(
    description: "Jacoby transfer, 5+ hearts",
    handEstimate: HandEstimate(
      suitLengthRanges: const {Suit.hearts: Range(low: 5)},
    ),
  );

  // Ignore minors for now, could do 2S->3C.

  bids[BidAction.noTrump(2)] = BidAnalysis(
    description: "8-10 points, no 4-card major",
    handEstimate: HandEstimate(
      pointRange: const Range(low: 8, high: 10),
      suitLengthRanges: const {
        Suit.hearts: Range(high: 3),
        Suit.spades: Range(high: 3),
      },
    ),
  );

  bids[BidAction.noTrump(3)] = BidAnalysis(
    description: "11-15 points, no 4-card major",
    handEstimate: HandEstimate(
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
    handEstimate: HandEstimate(
      pointRange: const Range(low: 16, high: 17),
      suitLengthRanges: const {
        Suit.hearts: Range(high: 3),
        Suit.spades: Range(high: 3),
      },
    ),
  );

  bids[BidAction.noTrump(6)] = BidAnalysis(
    description: "18+ points",
    handEstimate: HandEstimate(
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


LinkedHashMap<BidAction, BidAnalysis>
    bidAnalysisForResponseToPartnerOpeningOneBid(List<PlayerBid> bidHistory) {
  final openingBid = bidHistory[bidHistory.length - 2].action.contractBid!;
  final openedSuit = openingBid.trump;
  if (openedSuit == null) {
    return bidAnalysesForResponseToPartnerOpening1NT(bidHistory);
  } else if (isMajorSuit(openedSuit)) {
    return bidAnalysesForResponseToPartnerOpeningOneMajor(bidHistory);
  } else {
    return bidAnalysesForResponseToPartnerOpeningOneMinor(bidHistory);
  }
}

LinkedHashMap<BidAction, BidAnalysis>
    bidAnalysisForResponseToPartnerOpeningNoTrump(ContractBid openingBid) {
  final openedSuit = openingBid.trump!;
  final LinkedHashMap<BidAction, BidAnalysis> result = LinkedHashMap();

  result[BidAction.pass()] = BidAnalysis(
    description: "Fewer than 6 points",
    handEstimate: HandEstimate(pointRange: const Range(high: 5)),
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
