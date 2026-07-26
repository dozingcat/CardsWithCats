/// SAYC bidding engine, ported from the Python reference implementation
/// (rules-based Standard American with a hand-free interpretation layer).
///
/// Architecture: every auction context is an ordered list of [SaycRule]s,
/// each pairing a candidate [BidAction] with the [BidMeaning] it shows and
/// (when the public meaning isn't the whole selection condition) a predicate.
/// The same tables drive both directions:
///
///   - [selectSaycBid] returns the first rule the hand satisfies.
///   - [describeSaycCall] interprets a call with no hand at all.
///   - [explainSaycAuction] interprets every call and accumulates per-seat
///     constraints.
///
/// Port status (phase 1): opening bids only. [saycRulesForAuction] returns
/// null for auction positions not yet ported, so callers can fall back to
/// the legacy engine.
///
/// The auction history is a flat list of [BidAction]s starting with the
/// dealer's first call; seats are derived from list positions relative to
/// the caller (the next call belongs to the caller).
library;

import '../../cards/card.dart';
import '../bridge.dart';
import '../hand_estimate.dart';
import '../utils.dart';

// ---------------------------------------------------------------------------
// Hand analysis
// ---------------------------------------------------------------------------

/// Precomputed bidding-relevant properties of a 13-card hand.
class HandAnalysis {
  final List<PlayingCard> cards;
  final Map<Suit, int> counts;
  final int hcp;
  final int totalPoints;

  HandAnalysis._(this.cards, this.counts, this.hcp, this.totalPoints);

  factory HandAnalysis(List<PlayingCard> cards) {
    if (cards.length != 13) {
      throw ArgumentError("A hand must have 13 cards, got ${cards.length}");
    }
    if (cards.toSet().length != 13) {
      throw ArgumentError("Hand contains duplicate cards");
    }
    final counts = suitCounts(cards);
    final hcp = highCardPoints(cards);
    return HandAnalysis._(
        cards, counts, hcp, hcp + lengthPointsForSuitCounts(counts));
  }

  int count(Suit suit) => counts[suit]!;

  int suitHcp(Suit suit) =>
      cards.where((c) => c.suit == suit).map(pointsForCard).fold(0, (a, b) => a + b);

  int get aces => cards.where((c) => c.rank == Rank.ace).length;

  /// True for shapes 4-3-3-3, 4-4-3-2, and 5-3-3-2.
  bool get isBalanced {
    final lengths = counts.values.toList()..sort();
    return lengths[0] >= 2 && lengths.where((n) => n == 2).length <= 1;
  }

  /// A, Kx, Qxx, or Jxxx in the given suit.
  bool hasStopper(Suit suit) {
    final ranks = cards.where((c) => c.suit == suit).map((c) => c.rank).toSet();
    final length = ranks.length;
    return ranks.contains(Rank.ace) ||
        (ranks.contains(Rank.king) && length >= 2) ||
        (ranks.contains(Rank.queen) && length >= 3) ||
        (ranks.contains(Rank.jack) && length >= 4);
  }

  /// Longest suit; ties broken toward the higher-ranking suit.
  Suit get longestSuit {
    Suit best = Suit.clubs;
    for (final suit in [Suit.diamonds, Suit.hearts, Suit.spades]) {
      if (count(suit) >= count(best)) best = suit;
    }
    return best;
  }
}

/// Parse a hand from either format:
///  - 13 cards: "AS QS 3S 2S KH 6H AD 4D 3D 2D 4C 3C 2C"
///  - four suit groups (spades hearts diamonds clubs, '-' for a void):
///    "A2 AKJT Q32 9876"
List<PlayingCard> parseHand(String s) {
  final tokens = s.trim().split(RegExp(r"[,\s]+"));
  final groupPattern = RegExp(r"^[AKQJT98765432]+$");
  if (tokens.length == 4 &&
      tokens.every((t) => t == "-" || groupPattern.hasMatch(t.toUpperCase()))) {
    final suits = [Suit.spades, Suit.hearts, Suit.diamonds, Suit.clubs];
    final cards = <PlayingCard>[];
    for (int i = 0; i < 4; i++) {
      if (tokens[i] == "-") continue;
      for (final ch in tokens[i].toUpperCase().split("")) {
        cards.add(PlayingCard(Rank.fromChar(ch), suits[i]));
      }
    }
    return cards;
  }
  return tokens.map(PlayingCard.cardFromString).toList();
}

/// Format a hand as four suit groups: "A2 AKJT Q32 9876" ('-' for voids).
String handGroupString(List<PlayingCard> hand) {
  return [Suit.spades, Suit.hearts, Suit.diamonds, Suit.clubs].map((suit) {
    final ranks = sortedRanksInSuit(hand, suit);
    return ranks.isEmpty ? "-" : ranks.map((r) => r.asciiChar).join();
  }).join(" ");
}

// ---------------------------------------------------------------------------
// Bid meanings and rules
// ---------------------------------------------------------------------------

Map<Suit, Range> _allSuitRanges(Map<Suit, Range>? partial) {
  return {
    for (final suit in Suit.values) suit: partial?[suit] ?? const Range(),
  };
}

String _formatRange(Range r) {
  if (r.low != null && r.low == r.high) return "${r.low}";
  if (r.high == null) return "${r.low}+";
  if (r.low == null) return "<=${r.high}";
  return "${r.low}-${r.high}";
}

const _suitNames = {
  Suit.spades: "spades",
  Suit.hearts: "hearts",
  Suit.diamonds: "diamonds",
  Suit.clubs: "clubs",
};

/// What a call shows about the bidder's hand. Fields left null (or
/// full-range) are unspecified by the call. `hcp` and `totalPoints` are both
/// available because notrump ranges are defined in HCP while suit openings
/// use total points (HCP + length points).
class BidMeaning {
  final String description;
  final Range? hcp;
  final Range? totalPoints;
  final bool? balanced;
  final bool artificial;
  final Map<Suit, Range> suitLengths; // always contains all four suits

  BidMeaning({
    required this.description,
    this.hcp,
    this.totalPoints,
    this.balanced,
    this.artificial = false,
    Map<Suit, Range>? suitLengths,
  }) : suitLengths = _allSuitRanges(suitLengths);

  /// True if the hand is consistent with every constraint in this meaning.
  bool satisfiedBy(HandAnalysis hand) {
    if (hcp != null && !hcp!.contains(hand.hcp)) return false;
    if (totalPoints != null && !totalPoints!.contains(hand.totalPoints)) {
      return false;
    }
    if (balanced != null && hand.isBalanced != balanced) return false;
    for (final suit in Suit.values) {
      if (!suitLengths[suit]!.contains(hand.count(suit))) return false;
    }
    return true;
  }

  String summary() {
    final parts = <String>[];
    if (hcp != null) parts.add("${_formatRange(hcp!)} HCP");
    if (totalPoints != null) {
      parts.add("${_formatRange(totalPoints!)} total points");
    }
    if (balanced == true) parts.add("balanced");
    if (balanced == false) parts.add("unbalanced");
    for (final suit in [Suit.spades, Suit.hearts, Suit.diamonds, Suit.clubs]) {
      final r = suitLengths[suit]!;
      if (r.low != null || r.high != null) {
        parts.add("${_formatRange(r)} ${_suitNames[suit]}");
      }
    }
    if (artificial) parts.add("artificial");
    return parts.isEmpty ? "no additional information" : parts.join(", ");
  }

  /// Union of two meanings for the same call (hull of each constraint).
  BidMeaning mergedWith(BidMeaning other) {
    Range? hull(Range? a, Range? b) {
      if (a == null || b == null) return null;
      final low = (a.low == null || b.low == null)
          ? null
          : (a.low! < b.low! ? a.low : b.low);
      final high = (a.high == null || b.high == null)
          ? null
          : (a.high! > b.high! ? a.high : b.high);
      return (low == null && high == null) ? null : Range(low: low, high: high);
    }

    return BidMeaning(
      description: description == other.description
          ? description
          : "$description / ${other.description}",
      hcp: hull(hcp, other.hcp),
      totalPoints: hull(totalPoints, other.totalPoints),
      balanced: balanced == other.balanced ? balanced : null,
      artificial: artificial && other.artificial,
      suitLengths: {
        for (final suit in Suit.values)
          suit: hull(suitLengths[suit], other.suitLengths[suit]) ?? const Range(),
      },
    );
  }

  /// Intersection: everything a player has shown across several calls.
  BidMeaning intersectedWith(BidMeaning other) {
    Range? both(Range? a, Range? b) {
      if (a == null) return b;
      if (b == null) return a;
      return a.combine(b);
    }

    return BidMeaning(
      description: "$description; ${other.description}",
      hcp: both(hcp, other.hcp),
      totalPoints: both(totalPoints, other.totalPoints),
      balanced: other.balanced ?? balanced,
      artificial: false,
      suitLengths: {
        for (final suit in Suit.values)
          suit: suitLengths[suit]!.combine(other.suitLengths[suit]),
      },
    );
  }
}

/// One candidate call in a specific auction context.
///
/// By default the meaning also serves as the selection condition; [require]
/// adds an extra predicate (stoppers, relative suit lengths, ...), and
/// [ignoreInfo] makes [require] the sole selection condition — used when the
/// advertised range is narrower than the hands that actually make the call.
class SaycRule {
  final BidAction action;
  final BidMeaning meaning;
  final bool Function(HandAnalysis)? require;
  final bool ignoreInfo;

  SaycRule(this.action, this.meaning, {this.require, this.ignoreInfo = false});

  bool matches(HandAnalysis hand) {
    if (!ignoreInfo && !meaning.satisfiedBy(hand)) return false;
    return require == null || require!(hand);
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

int _strainOrder(Suit? strain) => switch (strain) {
      Suit.clubs => 0,
      Suit.diamonds => 1,
      Suit.hearts => 2,
      Suit.spades => 3,
      null => 4, // notrump
    };

/// The lowest legal level at which `strain` can be bid over the bid `over`.
int cheapestLevel(Suit? strain, ContractBid over) {
  return _strainOrder(strain) > _strainOrder(over.trump)
      ? over.count
      : over.count + 1;
}

// ---------------------------------------------------------------------------
// Opening bids
// ---------------------------------------------------------------------------

const Range _openingSuitPoints = Range(low: 13, high: 21);

List<SaycRule> openingRules() {
  final rules = <SaycRule>[
    SaycRule(
      BidAction.contract(2, Suit.clubs),
      BidMeaning(
        description: "Strong, artificial, and forcing",
        hcp: const Range(low: 22),
      ),
    ),
    SaycRule(
      BidAction.noTrump(1),
      BidMeaning(
        description: "Balanced, may contain a 5-card major",
        hcp: const Range(low: 15, high: 17),
        balanced: true,
        suitLengths: {
          for (final suit in Suit.values) suit: const Range(low: 2, high: 5),
        },
      ),
    ),
    SaycRule(
      BidAction.noTrump(2),
      BidMeaning(
        description: "Balanced, may contain a 5-card major",
        hcp: const Range(low: 20, high: 21),
        balanced: true,
        suitLengths: {
          for (final suit in Suit.values) suit: const Range(low: 2, high: 5),
        },
      ),
    ),
  ];
  // Preempts (5-10 HCP) take priority over shape-based light openings.
  const preemptOrder = [Suit.spades, Suit.hearts, Suit.diamonds, Suit.clubs];
  for (final suit in preemptOrder) {
    rules.add(SaycRule(
      BidAction.contract(4, suit),
      BidMeaning(
        description: "Preempt: 8+ ${_suitNames[suit]}, weak hand",
        hcp: const Range(low: 5, high: 10),
        suitLengths: {suit: const Range(low: 8)},
      ),
    ));
  }
  for (final suit in preemptOrder) {
    rules.add(SaycRule(
      BidAction.contract(3, suit),
      BidMeaning(
        description: "Preempt: 7-card ${_suitNames[suit]} suit, weak hand",
        hcp: const Range(low: 5, high: 10),
        suitLengths: {suit: const Range(low: 7, high: 7)},
      ),
    ));
  }
  for (final suit in [Suit.spades, Suit.hearts, Suit.diamonds]) {
    // No weak 2C: that is the strong opening.
    rules.add(SaycRule(
      BidAction.contract(2, suit),
      BidMeaning(
        description: "Weak two: 6-card ${_suitNames[suit]} suit, 5-10 HCP",
        hcp: const Range(low: 5, high: 10),
        suitLengths: {suit: const Range(low: 6, high: 6)},
      ),
    ));
  }
  rules.addAll([
    SaycRule(
      BidAction.contract(1, Suit.spades),
      BidMeaning(
        description: "Opening hand with 5+ spades",
        totalPoints: _openingSuitPoints,
        suitLengths: {Suit.spades: const Range(low: 5)},
      ),
      ignoreInfo: true,
      require: (h) =>
          h.totalPoints >= 13 &&
          h.count(Suit.spades) >= 5 &&
          h.count(Suit.spades) >= h.count(Suit.hearts),
    ),
    SaycRule(
      BidAction.contract(1, Suit.hearts),
      BidMeaning(
        description: "Opening hand with 5+ hearts",
        totalPoints: _openingSuitPoints,
        suitLengths: {Suit.hearts: const Range(low: 5)},
      ),
      ignoreInfo: true,
      require: (h) => h.totalPoints >= 13 && h.count(Suit.hearts) >= 5,
    ),
    SaycRule(
      BidAction.contract(1, Suit.diamonds),
      BidMeaning(
        description: "Opening hand, 3+ diamonds "
            "(typically 4+; 3 only with exactly 4=4=3=2 shape), no 5-card major",
        totalPoints: _openingSuitPoints,
        suitLengths: {
          Suit.spades: const Range(high: 4),
          Suit.hearts: const Range(high: 4),
          Suit.diamonds: const Range(low: 3),
        },
      ),
      ignoreInfo: true,
      require: (h) =>
          h.totalPoints >= 13 &&
          (h.count(Suit.diamonds) > h.count(Suit.clubs) ||
              (h.count(Suit.diamonds) == h.count(Suit.clubs) &&
                  h.count(Suit.diamonds) >= 4)),
    ),
    SaycRule(
      BidAction.contract(1, Suit.clubs),
      BidMeaning(
        description: "Opening hand, 3+ clubs, no 5-card major",
        totalPoints: _openingSuitPoints,
        suitLengths: {
          Suit.spades: const Range(high: 4),
          Suit.hearts: const Range(high: 4),
          Suit.clubs: const Range(low: 3),
        },
      ),
      ignoreInfo: true,
      require: (h) => h.totalPoints >= 13,
    ),
    SaycRule(
      BidAction.pass(),
      BidMeaning(
        description: "No suitable opening bid: fewer than 13 total points "
            "and no hand fitting a preemptive opening",
        totalPoints: const Range(high: 12),
      ),
      ignoreInfo: true,
    ),
  ]);
  return rules;
}

// ---------------------------------------------------------------------------
// Suit-choice helpers
// ---------------------------------------------------------------------------

bool _isMajor(Suit s) => s == Suit.hearts || s == Suit.spades;

/// Choose a suit to bid: longest first, ties prefer a major, equal-length
/// minors take the higher-ranking with 5+ cards and the cheaper with 4.
Suit? bestSuit(HandAnalysis hand, Iterable<Suit> candidates) {
  List<int> key(Suit s) {
    final length = hand.count(s);
    return [
      length,
      _isMajor(s) ? 1 : 0,
      length >= 5 ? _strainOrder(s) : -_strainOrder(s),
    ];
  }

  Suit? best;
  List<int>? bestKey;
  for (final s in candidates) {
    final k = key(s);
    if (bestKey == null ||
        k[0] > bestKey[0] ||
        (k[0] == bestKey[0] &&
            (k[1] > bestKey[1] ||
                (k[1] == bestKey[1] && k[2] > bestKey[2])))) {
      best = s;
      bestKey = k;
    }
  }
  return best;
}

/// Responder's suit choice with 10+ points over partner's major opening.
Suit? _newSuitChoiceOverMajor(HandAnalysis hand, ContractBid opening) {
  if (hand.totalPoints < 10) return null;
  final candidates = <Suit>[];
  if (opening.trump == Suit.hearts && hand.count(Suit.spades) >= 4) {
    candidates.add(Suit.spades);
  }
  if (opening.trump == Suit.spades && hand.count(Suit.hearts) >= 5) {
    candidates.add(Suit.hearts);
  }
  for (final minor in [Suit.diamonds, Suit.clubs]) {
    if (hand.count(minor) >= 4) candidates.add(minor);
  }
  return candidates.isEmpty ? null : bestSuit(hand, candidates);
}

Suit? _majorChoiceOverMinor(HandAnalysis hand) {
  final spades = hand.count(Suit.spades);
  final hearts = hand.count(Suit.hearts);
  if (spades < 4 && hearts < 4) return null;
  if (spades > hearts) return Suit.spades;
  if (hearts > spades) return Suit.hearts;
  return spades >= 5 ? Suit.spades : Suit.hearts;
}

// ---------------------------------------------------------------------------
// Responses to partner's opening bid
// ---------------------------------------------------------------------------

List<SaycRule>? responseRules(BidAction opening) {
  if (opening.bidType != BidType.contract) return null;
  final bid = opening.contractBid!;
  if (bid.trump == null) {
    if (bid.count == 1) return oneNtResponseRules();
    if (bid.count == 2) return twoNtResponseRules();
    return null;
  }
  if (bid.count == 2 && bid.trump == Suit.clubs) return twoClubResponseRules();
  if (bid.count == 1) {
    return _isMajor(bid.trump!)
        ? _majorResponseRules(bid)
        : _minorResponseRules(bid);
  }
  if (bid.count == 2) return weakTwoResponseRules(bid);
  if (bid.count == 3 || bid.count == 4) return preemptResponseRules(bid);
  return null;
}

List<SaycRule> _majorResponseRules(ContractBid opening) {
  final suit = opening.trump!;
  final name = _suitNames[suit]!;
  final rules = <SaycRule>[
    SaycRule(
      BidAction.pass(),
      BidMeaning(
          description: "Too weak to respond",
          totalPoints: const Range(high: 5)),
    ),
    SaycRule(
      BidAction.noTrump(2),
      BidMeaning(
        description: "Jacoby 2NT: game-forcing raise with 4+ $name",
        totalPoints: const Range(low: 13),
        artificial: true,
        suitLengths: {suit: const Range(low: 4)},
      ),
    ),
    SaycRule(
      BidAction.contract(2, suit),
      BidMeaning(
        description: "Single raise: 3+ $name, 6-10 points",
        totalPoints: const Range(low: 6, high: 10),
        suitLengths: {suit: const Range(low: 3)},
      ),
    ),
    SaycRule(
      BidAction.contract(3, suit),
      BidMeaning(
        description: "Limit raise: 3+ $name, 11-12 points, invitational",
        totalPoints: const Range(low: 11, high: 12),
        suitLengths: {suit: const Range(low: 3)},
      ),
    ),
  ];
  // New suits with 10+ points: longest suit first.
  final targets = <(Suit, int, int, int)>[
    if (suit == Suit.hearts) (Suit.spades, 1, 4, 6),
    if (suit == Suit.spades) (Suit.hearts, 2, 5, 10),
    (Suit.diamonds, 2, 4, 10),
    (Suit.clubs, 2, 4, 10),
  ];
  for (final (target, level, minLen, minPts) in targets) {
    final label = level == 1
        ? "New suit (forcing): 4+ ${_suitNames[target]}, 6+ points"
        : "Two-over-one: $minLen+ ${_suitNames[target]}, 10+ points, forcing";
    rules.add(SaycRule(
      BidAction.contract(level, target),
      BidMeaning(
        description: label,
        totalPoints: Range(low: minPts),
        suitLengths: {target: Range(low: minLen)},
      ),
      ignoreInfo: true,
      require: (h) => _newSuitChoiceOverMajor(h, opening) == target,
    ));
  }
  if (suit == Suit.hearts) {
    // Weak hands still show a spade suit at the one level.
    rules.add(SaycRule(
      BidAction.contract(1, Suit.spades),
      BidMeaning(
        description: "New suit (forcing): 4+ spades, 6+ points",
        totalPoints: const Range(low: 6),
        suitLengths: {Suit.spades: const Range(low: 4)},
      ),
      ignoreInfo: true,
      require: (h) => h.totalPoints <= 9 && h.count(Suit.spades) >= 4,
    ));
  }
  rules.add(SaycRule(
    BidAction.noTrump(1),
    BidMeaning(
      description:
          "6-9 points, fewer than three $name, no suit to bid at the one level",
      totalPoints: const Range(low: 6, high: 9),
      suitLengths: {
        suit: const Range(high: 2),
        if (suit == Suit.hearts) Suit.spades: const Range(high: 3),
      },
    ),
  ));
  return rules;
}

List<SaycRule> _minorResponseRules(ContractBid opening) {
  final suit = opening.trump!;
  final name = _suitNames[suit]!;
  const noMajor = {
    Suit.spades: Range(high: 3),
    Suit.hearts: Range(high: 3),
  };
  final rules = <SaycRule>[
    SaycRule(
      BidAction.pass(),
      BidMeaning(
          description: "Too weak to respond",
          totalPoints: const Range(high: 5)),
    ),
  ];
  for (final major in [Suit.hearts, Suit.spades]) {
    rules.add(SaycRule(
      BidAction.contract(1, major),
      BidMeaning(
        description: "New suit (forcing): 4+ ${_suitNames[major]}, 6+ points",
        totalPoints: const Range(low: 6),
        suitLengths: {major: const Range(low: 4)},
      ),
      ignoreInfo: true,
      require: (h) => h.totalPoints >= 6 && _majorChoiceOverMinor(h) == major,
    ));
  }
  if (suit == Suit.clubs) {
    rules.add(SaycRule(
      BidAction.contract(1, Suit.diamonds),
      BidMeaning(
        description: "New suit (forcing): 4+ diamonds, 6+ points, no 4-card major",
        totalPoints: const Range(low: 6),
        suitLengths: {Suit.diamonds: const Range(low: 4), ...noMajor},
      ),
      require: (h) => h.count(Suit.diamonds) >= h.count(Suit.clubs),
    ));
  }
  rules.addAll([
    SaycRule(
      BidAction.contract(2, suit),
      BidMeaning(
        description: "Single raise: 4+ $name, 6-10 points, no 4-card major",
        totalPoints: const Range(low: 6, high: 10),
        suitLengths: {suit: const Range(low: 4), ...noMajor},
      ),
    ),
    SaycRule(
      BidAction.contract(3, suit),
      BidMeaning(
        description: "Limit raise: 4+ $name, 11-12 points, no 4-card major",
        totalPoints: const Range(low: 11, high: 12),
        suitLengths: {suit: const Range(low: 4), ...noMajor},
      ),
    ),
    SaycRule(
      BidAction.noTrump(2),
      BidMeaning(
        description: "13-15 HCP, balanced, no 4-card major",
        hcp: const Range(low: 13, high: 15),
        balanced: true,
        suitLengths: noMajor,
      ),
    ),
    SaycRule(
      BidAction.noTrump(3),
      BidMeaning(
        description: "16-18 HCP, balanced, no 4-card major",
        hcp: const Range(low: 16, high: 18),
        balanced: true,
        suitLengths: noMajor,
      ),
    ),
  ]);
  final other = suit == Suit.clubs ? Suit.diamonds : Suit.clubs;
  rules.addAll([
    SaycRule(
      BidAction.contract(2, other),
      BidMeaning(
        description: "Two-over-one: 4+ ${_suitNames[other]}, 10+ points, forcing",
        totalPoints: const Range(low: 10),
        suitLengths: {other: const Range(low: 4), ...noMajor},
      ),
    ),
    SaycRule(
      BidAction.noTrump(1),
      BidMeaning(
        description: "6-9 points, no 4-card major, no fit",
        totalPoints: const Range(low: 6, high: 9),
        suitLengths: noMajor,
      ),
    ),
  ]);
  return rules;
}

List<SaycRule> oneNtResponseRules() {
  const noMajor = {
    Suit.spades: Range(high: 3),
    Suit.hearts: Range(high: 3),
  };
  return [
    SaycRule(
      BidAction.contract(2, Suit.hearts),
      BidMeaning(
        description: "Jacoby transfer: 5+ spades, any strength",
        artificial: true,
        suitLengths: {Suit.spades: const Range(low: 5)},
      ),
      require: (h) => h.count(Suit.spades) >= h.count(Suit.hearts),
    ),
    SaycRule(
      BidAction.contract(2, Suit.diamonds),
      BidMeaning(
        description: "Jacoby transfer: 5+ hearts, any strength",
        artificial: true,
        suitLengths: {Suit.hearts: const Range(low: 5)},
      ),
      require: (h) => h.count(Suit.hearts) > h.count(Suit.spades),
    ),
    SaycRule(
      BidAction.contract(2, Suit.clubs),
      BidMeaning(
        description: "Stayman: at least one 4-card major, invitational or better",
        hcp: const Range(low: 8),
        artificial: true,
      ),
      ignoreInfo: true,
      require: (h) =>
          h.hcp >= 8 &&
          (h.count(Suit.spades) == 4 || h.count(Suit.hearts) == 4),
    ),
    SaycRule(
      BidAction.pass(),
      BidMeaning(
          description: "Too weak to invite game", hcp: const Range(high: 7)),
    ),
    SaycRule(
      BidAction.noTrump(2),
      BidMeaning(
        description: "Invites 3NT; no 4-card major",
        hcp: const Range(low: 8, high: 9),
        suitLengths: noMajor,
      ),
    ),
    SaycRule(
      BidAction.noTrump(3),
      BidMeaning(
        description: "To play; no 4-card major",
        hcp: const Range(low: 10, high: 15),
        suitLengths: noMajor,
      ),
    ),
    SaycRule(
      BidAction.noTrump(4),
      BidMeaning(
        description: "Quantitative: invites 6NT",
        hcp: const Range(low: 16, high: 17),
        suitLengths: noMajor,
      ),
    ),
    SaycRule(
      BidAction.contract(4, Suit.clubs),
      BidMeaning(
        description: "Gerber: asking for aces, slam-going",
        hcp: const Range(low: 18),
        artificial: true,
        suitLengths: noMajor,
      ),
    ),
  ];
}

List<SaycRule> twoNtResponseRules() {
  // Simplified: no Stayman or transfers over 2NT yet.
  return [
    SaycRule(
      BidAction.contract(4, Suit.clubs),
      BidMeaning(
        description: "Gerber: asking for aces, slam-going",
        hcp: const Range(low: 13),
        artificial: true,
      ),
    ),
    SaycRule(
      BidAction.noTrump(4),
      BidMeaning(
        description: "Quantitative: invites 6NT",
        hcp: const Range(low: 11, high: 12),
      ),
    ),
    SaycRule(
      BidAction.noTrump(3),
      BidMeaning(
          description: "To play", hcp: const Range(low: 5, high: 10)),
    ),
    SaycRule(
      BidAction.pass(),
      BidMeaning(
          description: "Too weak to try for game", hcp: const Range(high: 4)),
    ),
  ];
}

List<SaycRule> twoClubResponseRules() {
  // Simplified: always 2D waiting; no positive responses.
  return [
    SaycRule(
      BidAction.contract(2, Suit.diamonds),
      BidMeaning(
        description: "Waiting; says nothing about diamonds",
        artificial: true,
      ),
    ),
  ];
}

List<SaycRule> weakTwoResponseRules(ContractBid opening) {
  final suit = opening.trump!;
  final name = _suitNames[suit]!;
  final rules = <SaycRule>[];
  if (_isMajor(suit)) {
    rules.add(SaycRule(
      BidAction.contract(4, suit),
      BidMeaning(
        description: "Raise to game: 3+ $name, 15+ points",
        totalPoints: const Range(low: 15),
        suitLengths: {suit: const Range(low: 3)},
      ),
    ));
  } else {
    rules.add(SaycRule(
      BidAction.noTrump(3),
      BidMeaning(
        description: "To play over partner's weak two",
        totalPoints: const Range(low: 15),
      ),
      require: (h) => h.count(suit) >= 3,
    ));
  }
  rules.addAll([
    SaycRule(
      BidAction.noTrump(3),
      BidMeaning(
        description: "To play: strong hand, no trump fit required",
        hcp: const Range(low: 16),
      ),
    ),
    SaycRule(
      BidAction.contract(3, suit),
      BidMeaning(
        description: "Preemptive raise: 3+ $name, extends the barrage",
        totalPoints: const Range(high: 14),
        suitLengths: {suit: const Range(low: 3)},
      ),
    ),
    SaycRule(
      BidAction.pass(),
      BidMeaning(
          description: "No fit and no reason to act over partner's weak two"),
    ),
  ]);
  return rules;
}

List<SaycRule> preemptResponseRules(ContractBid opening) {
  final suit = opening.trump!;
  final rules = <SaycRule>[];
  if (opening.count == 3 && _isMajor(suit)) {
    rules.add(SaycRule(
      BidAction.contract(4, suit),
      BidMeaning(
        description: "Raise to game: 2+ ${_suitNames[suit]}, 15+ points",
        totalPoints: const Range(low: 15),
        suitLengths: {suit: const Range(low: 2)},
      ),
    ));
  }
  if (opening.count == 3) {
    rules.add(SaycRule(
      BidAction.noTrump(3),
      BidMeaning(
        description: "To play: strong hand over partner's preempt",
        hcp: const Range(low: 16),
      ),
    ));
  }
  rules.add(SaycRule(
    BidAction.pass(),
    BidMeaning(description: "No reason to act over partner's preempt"),
  ));
  return rules;
}

// ---------------------------------------------------------------------------
// Slam conventions: Blackwood (4NT over suits) and Gerber (4C over notrump)
// ---------------------------------------------------------------------------

List<SaycRule> blackwoodAnswerRules() {
  final steps = [
    (Suit.clubs, "0 or 4 aces", (HandAnalysis h) => h.aces == 0 || h.aces == 4),
    (Suit.diamonds, "1 ace", (HandAnalysis h) => h.aces == 1),
    (Suit.hearts, "2 aces", (HandAnalysis h) => h.aces == 2),
    (Suit.spades, "3 aces", (HandAnalysis h) => h.aces == 3),
  ];
  return [
    for (final (suit, desc, req) in steps)
      SaycRule(
        BidAction.contract(5, suit),
        BidMeaning(description: "Blackwood answer: $desc", artificial: true),
        require: req,
      ),
  ];
}

/// Place the contract after partner answered our 4NT ace-ask. Simplified:
/// bid a small slam missing at most one ace, otherwise stop at the five
/// level; no 5NT king-ask or grand-slam exploration.
List<SaycRule>? blackwoodPlacementRules(
    BidAction opening, BidAction response, BidAction rebid, BidAction answer) {
  if (answer.bidType != BidType.contract ||
      answer.contractBid!.count != 5 ||
      answer.contractBid!.trump == null) {
    return null;
  }
  final answerSuit = answer.contractBid!.trump!;
  final int? shown = switch (answerSuit) {
    Suit.clubs => null, // 0 or 4, disambiguated by our aces
    Suit.diamonds => 1,
    Suit.hearts => 2,
    Suit.spades => 3,
  };
  // The agreed trump suit.
  final openingBid =
      opening.bidType == BidType.contract ? opening.contractBid : null;
  Suit? trump;
  if (response == BidAction.noTrump(2) &&
      openingBid?.trump != null &&
      _isMajor(openingBid!.trump!)) {
    trump = openingBid.trump; // Jacoby 2NT
  } else if (rebid.bidType == BidType.contract &&
      rebid.contractBid!.trump != null &&
      response.bidType == BidType.contract &&
      rebid.contractBid!.trump == response.contractBid!.trump) {
    trump = response.contractBid!.trump;
  } else if (openingBid?.trump != null) {
    trump = openingBid!.trump;
  }
  if (trump == null) return null;
  final trumpSuit = trump;

  int partnerAces(HandAnalysis h) =>
      shown ?? (h.aces >= 1 ? 0 : 4);

  final rules = <SaycRule>[
    SaycRule(
      BidAction.contract(6, trumpSuit),
      BidMeaning(description: "Small slam: at most one ace missing"),
      require: (h) => h.aces + partnerAces(h) >= 3,
    ),
  ];
  if (_strainOrder(trumpSuit) > _strainOrder(answerSuit)) {
    rules.add(SaycRule(
      BidAction.contract(5, trumpSuit),
      BidMeaning(description: "Signing off: two aces missing"),
    ));
  } else {
    rules.add(SaycRule(
      BidAction.contract(6, trumpSuit),
      BidMeaning(
          description:
              "Two aces missing, but the answer is past our five-level spot"),
    ));
  }
  return rules;
}

List<SaycRule> gerberAnswerRules(Range shownHcp) {
  final steps = [
    (Suit.diamonds as Suit?, "0 or 4 aces",
        (HandAnalysis h) => h.aces == 0 || h.aces == 4),
    (Suit.hearts as Suit?, "1 ace", (HandAnalysis h) => h.aces == 1),
    (Suit.spades as Suit?, "2 aces", (HandAnalysis h) => h.aces == 2),
    (null, "3 aces", (HandAnalysis h) => h.aces == 3),
  ];
  return [
    for (final (suit, desc, req) in steps)
      SaycRule(
        BidAction.withBid(ContractBid(4, suit)),
        BidMeaning(
            description: "Gerber answer: $desc",
            hcp: shownHcp,
            artificial: true),
        require: req,
      ),
  ];
}

/// Place the contract after partner answered our 4C ace-ask.
List<SaycRule>? gerberContinuationRules(BidAction answer) {
  if (answer.bidType != BidType.contract || answer.contractBid!.count != 4) {
    return null;
  }
  final answerTrump = answer.contractBid!.trump;
  if (answerTrump == Suit.clubs) return null;
  final int? shown = switch (answerTrump) {
    Suit.diamonds => null, // 0 or 4
    Suit.hearts => 1,
    Suit.spades => 2,
    null => 3,
    _ => null,
  };

  int partnerAces(HandAnalysis h) => shown ?? (h.aces >= 1 ? 0 : 4);

  final rules = <SaycRule>[
    SaycRule(
      BidAction.noTrump(6),
      BidMeaning(description: "Small slam: at most one ace missing"),
      require: (h) => h.aces + partnerAces(h) >= 3,
    ),
  ];
  if (answerTrump != null) {
    rules.add(SaycRule(
      BidAction.noTrump(4),
      BidMeaning(description: "Signing off: two aces missing"),
    ));
  } else {
    rules.add(SaycRule(
      BidAction.pass(),
      BidMeaning(description: "Signing off: two aces missing"),
    ));
  }
  return rules;
}

// ---------------------------------------------------------------------------
// Opener's rebid (uncontested)
// ---------------------------------------------------------------------------

/// Opener's second-suit choice: longest 4+ suit biddable below the three
/// level, skipping reverses without 17+ points.
Suit? _secondSuitChoice(
    HandAnalysis hand, Suit mySuit, Set<Suit> excluded, ContractBid over) {
  final total = hand.totalPoints;
  final candidates = Suit.values
      .where((s) => !excluded.contains(s) && hand.count(s) >= 4)
      .toList();
  // Sort by preference, best first.
  candidates.sort((a, b) {
    final la = hand.count(a), lb = hand.count(b);
    if (la != lb) return lb - la;
    final ma = _isMajor(a) ? 1 : 0, mb = _isMajor(b) ? 1 : 0;
    if (ma != mb) return mb - ma;
    final ra = la >= 5 ? _strainOrder(a) : -_strainOrder(a);
    final rb = lb >= 5 ? _strainOrder(b) : -_strainOrder(b);
    return rb - ra;
  });
  for (final s in candidates) {
    final level = cheapestLevel(s, over);
    if (level >= 3) continue;
    if (level >= 2 && _strainOrder(s) > _strainOrder(mySuit) && total < 17) {
      continue;
    }
    return s;
  }
  return null;
}

List<SaycRule>? openerRebidRules(BidAction opening, BidAction response) {
  if (opening.bidType != BidType.contract ||
      response.bidType != BidType.contract) {
    return null;
  }
  final openBid = opening.contractBid!;
  if (openBid.trump == null && openBid.count == 1) {
    return oneNtRebidRules(response);
  }
  if (openBid.trump == null && openBid.count == 2) {
    return twoNtRebidRules(response);
  }
  if (openBid == ContractBid(2, Suit.clubs)) {
    return twoClubRebidRules(response);
  }
  if (openBid.trump != null && openBid.count == 1) {
    return _oneSuitRebidRules(openBid, response.contractBid!);
  }
  if (openBid.trump != null && openBid.count >= 2) {
    // Preemptive openings: the preemptor never bids again voluntarily.
    if (response.contractBid!.trump == openBid.trump) {
      return [
        SaycRule(
          BidAction.pass(),
          BidMeaning(description: "Preemptive opener has nothing more to say"),
        )
      ];
    }
    return null;
  }
  return null;
}

List<SaycRule>? oneNtRebidRules(BidAction response) {
  if (response == BidAction.contract(4, Suit.clubs)) {
    return gerberAnswerRules(const Range(low: 15, high: 17));
  }
  if (response == BidAction.contract(2, Suit.clubs)) {
    // Stayman.
    return [
      SaycRule(
        BidAction.contract(2, Suit.hearts),
        BidMeaning(
          description: "4 hearts (may also hold 4 spades)",
          hcp: const Range(low: 15, high: 17),
          suitLengths: {Suit.hearts: const Range(low: 4, high: 5)},
        ),
      ),
      SaycRule(
        BidAction.contract(2, Suit.spades),
        BidMeaning(
          description: "4 spades, fewer than 4 hearts",
          hcp: const Range(low: 15, high: 17),
          suitLengths: {
            Suit.spades: const Range(low: 4, high: 5),
            Suit.hearts: const Range(high: 3),
          },
        ),
      ),
      SaycRule(
        BidAction.contract(2, Suit.diamonds),
        BidMeaning(
          description: "Denies a 4-card major",
          hcp: const Range(low: 15, high: 17),
          artificial: true,
          suitLengths: {
            Suit.spades: const Range(high: 3),
            Suit.hearts: const Range(high: 3),
          },
        ),
      ),
    ];
  }
  if (response == BidAction.contract(2, Suit.diamonds)) {
    return [
      SaycRule(
        BidAction.contract(2, Suit.hearts),
        BidMeaning(
            description: "Completing the transfer (forced)", artificial: true),
      )
    ];
  }
  if (response == BidAction.contract(2, Suit.hearts)) {
    return [
      SaycRule(
        BidAction.contract(2, Suit.spades),
        BidMeaning(
            description: "Completing the transfer (forced)", artificial: true),
      )
    ];
  }
  if (response == BidAction.noTrump(2)) {
    return [
      SaycRule(
        BidAction.noTrump(3),
        BidMeaning(
            description: "Accepting the invitation",
            hcp: const Range(low: 16, high: 17)),
      ),
      SaycRule(
        BidAction.pass(),
        BidMeaning(
            description: "Declining the invitation",
            hcp: const Range(low: 15, high: 15)),
      ),
    ];
  }
  if (response == BidAction.noTrump(4)) {
    return [
      SaycRule(
        BidAction.noTrump(6),
        BidMeaning(
            description: "Accepting the slam invitation",
            hcp: const Range(low: 17, high: 17)),
      ),
      SaycRule(
        BidAction.pass(),
        BidMeaning(
            description: "Declining the slam invitation",
            hcp: const Range(low: 15, high: 16)),
      ),
    ];
  }
  if (response == BidAction.noTrump(3) ||
      response == BidAction.contract(4, Suit.hearts) ||
      response == BidAction.contract(4, Suit.spades)) {
    return [
      SaycRule(BidAction.pass(),
          BidMeaning(description: "Respecting partner's signoff"))
    ];
  }
  return null;
}

List<SaycRule>? twoNtRebidRules(BidAction response) {
  if (response == BidAction.contract(4, Suit.clubs)) {
    return gerberAnswerRules(const Range(low: 20, high: 21));
  }
  if (response == BidAction.noTrump(4)) {
    return [
      SaycRule(
        BidAction.noTrump(6),
        BidMeaning(
            description: "Accepting the slam invitation",
            hcp: const Range(low: 21, high: 21)),
      ),
      SaycRule(
        BidAction.pass(),
        BidMeaning(
            description: "Declining the slam invitation",
            hcp: const Range(low: 20, high: 20)),
      ),
    ];
  }
  if (response.bidType == BidType.contract &&
      response.contractBid!.trump == null) {
    return [
      SaycRule(BidAction.pass(),
          BidMeaning(description: "Respecting partner's signoff"))
    ];
  }
  return null;
}

List<SaycRule>? twoClubRebidRules(BidAction response) {
  if (response != BidAction.contract(2, Suit.diamonds)) return null;
  final rules = <SaycRule>[
    SaycRule(
      BidAction.noTrump(2),
      BidMeaning(
          description: "22-24 HCP, balanced",
          hcp: const Range(low: 22, high: 24),
          balanced: true),
    ),
    SaycRule(
      BidAction.noTrump(3),
      BidMeaning(
          description: "25-27 HCP, balanced",
          hcp: const Range(low: 25, high: 27),
          balanced: true),
      ignoreInfo: true,
      require: (h) => h.isBalanced,
    ),
  ];
  final responseBid = ContractBid(2, Suit.diamonds);
  for (final suit in [Suit.spades, Suit.hearts, Suit.diamonds, Suit.clubs]) {
    rules.add(SaycRule(
      BidAction.contract(cheapestLevel(suit, responseBid), suit),
      BidMeaning(
        description:
            "Natural, longest suit (usually 5+ ${_suitNames[suit]}), game-forcing",
        hcp: const Range(low: 22),
        suitLengths: {suit: const Range(low: 4)},
      ),
      ignoreInfo: true,
      require: (h) => h.longestSuit == suit,
    ));
  }
  return rules;
}

List<SaycRule> _oneSuitRebidRules(ContractBid opening, ContractBid response) {
  final mySuit = opening.trump!;

  if (response.trump == mySuit) {
    return _rebidAfterRaiseRules(opening, response);
  }
  if (response.trump == null && response.count == 2) {
    if (_isMajor(mySuit)) {
      // Jacoby 2NT.
      return [
        SaycRule(
          BidAction.contract(4, mySuit),
          BidMeaning(
              description: "Minimum opening, no interest beyond game",
              totalPoints: const Range(low: 13, high: 15)),
          ignoreInfo: true,
          require: (h) => h.totalPoints <= 15,
        ),
        SaycRule(
          BidAction.contract(3, mySuit),
          BidMeaning(
              description: "Extra values opposite the game-forcing raise",
              totalPoints: const Range(low: 16, high: 21)),
          ignoreInfo: true,
        ),
      ];
    }
    return [
      SaycRule(
        BidAction.noTrump(3),
        BidMeaning(
            description: "Accepting 3NT opposite 13-15 balanced",
            totalPoints: const Range(low: 13, high: 21)),
        ignoreInfo: true,
      )
    ];
  }
  if (response.trump == null && response.count == 1) {
    return _rebidAfter1ntResponseRules(opening);
  }
  if (response.trump == null) {
    return [
      SaycRule(BidAction.pass(),
          BidMeaning(description: "Respecting partner's signoff"))
    ];
  }
  return _rebidAfterNewSuitRules(opening, response);
}

List<SaycRule> _rebidAfterRaiseRules(ContractBid opening, ContractBid response) {
  final mySuit = opening.trump!;
  final name = _suitNames[mySuit]!;
  final gameLevel = _isMajor(mySuit) ? 4 : 5;
  if (response.count == 2) {
    // Single raise, 6-10.
    return [
      SaycRule(
        BidAction.pass(),
        BidMeaning(
            description: "Minimum opening, no game interest",
            totalPoints: const Range(low: 13, high: 15)),
        ignoreInfo: true,
        require: (h) => h.totalPoints <= 15,
      ),
      SaycRule(
        BidAction.contract(3, mySuit),
        BidMeaning(
            description: "Inviting game in $name",
            totalPoints: const Range(low: 16, high: 18)),
        ignoreInfo: true,
        require: (h) => h.totalPoints <= 18,
      ),
      SaycRule(
        BidAction.contract(gameLevel, mySuit),
        BidMeaning(
            description: "Accepting game",
            totalPoints: const Range(low: 19, high: 21)),
        ignoreInfo: true,
      ),
    ];
  }
  if (response.count == 3) {
    // Limit raise, 11-12.
    return [
      SaycRule(
        BidAction.pass(),
        BidMeaning(
            description: "Minimum opening, declining the invitation",
            totalPoints: const Range(low: 13, high: 13)),
        ignoreInfo: true,
        require: (h) => h.totalPoints <= 13,
      ),
      SaycRule(
        BidAction.contract(gameLevel, mySuit),
        BidMeaning(
            description: "Accepting the game invitation",
            totalPoints: const Range(low: 14, high: 21)),
        ignoreInfo: true,
      ),
    ];
  }
  return [
    SaycRule(
        BidAction.pass(), BidMeaning(description: "Respecting partner's signoff"))
  ];
}

List<SaycRule> _rebidAfter1ntResponseRules(ContractBid opening) {
  final mySuit = opening.trump!;
  final name = _suitNames[mySuit]!;
  final response = ContractBid.noTrump(1);
  final rules = <SaycRule>[
    SaycRule(
      BidAction.contract(2, mySuit),
      BidMeaning(
        description: "6+ $name, minimum opening",
        totalPoints: const Range(low: 13, high: 15),
        suitLengths: {mySuit: const Range(low: 6)},
      ),
      ignoreInfo: true,
      require: (h) => h.count(mySuit) >= 6 && h.totalPoints <= 15,
    ),
    SaycRule(
      BidAction.contract(3, mySuit),
      BidMeaning(
        description: "6+ $name, inviting game",
        totalPoints: const Range(low: 16, high: 18),
        suitLengths: {mySuit: const Range(low: 6)},
      ),
      ignoreInfo: true,
      require: (h) => h.count(mySuit) >= 6,
    ),
    SaycRule(
      BidAction.noTrump(2),
      BidMeaning(
          description: "18-19 HCP, balanced",
          hcp: const Range(low: 18, high: 19),
          balanced: true),
      ignoreInfo: true,
      require: (h) => h.isBalanced && h.hcp >= 18,
    ),
    SaycRule(
      BidAction.pass(),
      BidMeaning(
          description: "Balanced minimum, content to play 1NT",
          hcp: const Range(low: 12, high: 14)),
      ignoreInfo: true,
      require: (h) => h.isBalanced,
    ),
  ];
  // Jump shifts: 18+, lower-ranking suits only.
  for (final s in Suit.values) {
    if (s == mySuit || _strainOrder(s) > _strainOrder(mySuit)) continue;
    rules.add(SaycRule(
      BidAction.contract(3, s),
      BidMeaning(
        description: "Jump shift: 4+ ${_suitNames[s]}, 18+ points",
        totalPoints: const Range(low: 18, high: 21),
        suitLengths: {s: const Range(low: 4)},
      ),
      ignoreInfo: true,
      require: (h) =>
          h.totalPoints >= 18 &&
          _secondSuitChoice(h, mySuit, {mySuit}, response) == s,
    ));
  }
  for (final s in Suit.values) {
    if (s == mySuit) continue;
    final isReverse = _strainOrder(s) > _strainOrder(mySuit);
    rules.add(SaycRule(
      BidAction.contract(2, s),
      BidMeaning(
        description: "Second suit: 4+ ${_suitNames[s]}"
            "${isReverse ? ', reverse showing extra strength' : ''}",
        totalPoints: isReverse
            ? const Range(low: 17, high: 21)
            : const Range(low: 13, high: 17),
        suitLengths: {
          s: const Range(low: 4),
          mySuit: Range(low: _isMajor(mySuit) ? 5 : 3),
        },
      ),
      ignoreInfo: true,
      require: (h) => _secondSuitChoice(h, mySuit, {mySuit}, response) == s,
    ));
  }
  rules.add(SaycRule(
    BidAction.pass(),
    BidMeaning(
        description: "Minimum with no better rebid",
        totalPoints: const Range(low: 13, high: 15)),
    ignoreInfo: true,
  ));
  return rules;
}

List<SaycRule> _rebidAfterNewSuitRules(
    ContractBid opening, ContractBid response) {
  final mySuit = opening.trump!;
  final partnerSuit = response.trump!;
  final myName = _suitNames[mySuit]!;
  final pName = _suitNames[partnerSuit]!;
  final partnerMajor = _isMajor(partnerSuit);

  List<SaycRule> raiseRules() {
    final out = <SaycRule>[
      SaycRule(
        BidAction.contract(response.count + 1, partnerSuit),
        BidMeaning(
          description: "Raise: 4+ $pName, minimum opening",
          totalPoints: const Range(low: 13, high: 15),
          suitLengths: {partnerSuit: const Range(low: 4)},
        ),
        ignoreInfo: true,
        require: (h) =>
            h.count(partnerSuit) >= 4 && h.totalPoints <= 15,
      ),
      SaycRule(
        BidAction.contract(response.count + 2, partnerSuit),
        BidMeaning(
          description: "Jump raise: 4+ $pName, extra values",
          totalPoints: const Range(low: 16, high: 18),
          suitLengths: {partnerSuit: const Range(low: 4)},
        ),
        ignoreInfo: true,
        require: (h) =>
            h.count(partnerSuit) >= 4 &&
            (h.totalPoints <= 18 || !partnerMajor),
      ),
    ];
    if (partnerMajor) {
      out.add(SaycRule(
        BidAction.contract(4, partnerSuit),
        BidMeaning(
          description: "Raise to game: 4+ $pName, maximum opening",
          totalPoints: const Range(low: 19, high: 21),
          suitLengths: {partnerSuit: const Range(low: 4)},
        ),
        ignoreInfo: true,
        require: (h) => h.count(partnerSuit) >= 4,
      ));
    }
    return out;
  }

  final rules = <SaycRule>[];
  if (partnerMajor) {
    rules.addAll(raiseRules());
  } else {
    if (response.count == 1) {
      // Over a minor-suit response, show a 4-card major before raising.
      for (final major in [Suit.hearts, Suit.spades]) {
        rules.add(SaycRule(
          BidAction.contract(1, major),
          BidMeaning(
            description: "Second suit: 4+ ${_suitNames[major]}",
            totalPoints: const Range(low: 13, high: 18),
            suitLengths: {major: const Range(low: 4)},
          ),
          ignoreInfo: true,
          require: (h) => h.count(major) >= 4,
        ));
      }
    }
    rules.addAll(raiseRules());
  }

  rules.addAll([
    SaycRule(
      BidAction.noTrump(response.count + 1),
      BidMeaning(
          description: "18-19 HCP, balanced",
          hcp: const Range(low: 18, high: 19),
          balanced: true),
      ignoreInfo: true,
      require: (h) => h.isBalanced && h.hcp >= 18,
    ),
    SaycRule(
      BidAction.noTrump(response.count),
      BidMeaning(
          description: "12-14 HCP, balanced",
          hcp: const Range(low: 12, high: 14),
          balanced: true),
      ignoreInfo: true,
      require: (h) => h.isBalanced,
    ),
    SaycRule(
      BidAction.contract(cheapestLevel(mySuit, response), mySuit),
      BidMeaning(
        description: "6+ $myName, minimum opening",
        totalPoints: const Range(low: 13, high: 15),
        suitLengths: {mySuit: const Range(low: 6)},
      ),
      ignoreInfo: true,
      require: (h) => h.count(mySuit) >= 6 && h.totalPoints <= 15,
    ),
    SaycRule(
      BidAction.contract(cheapestLevel(mySuit, response) + 1, mySuit),
      BidMeaning(
        description: "6+ $myName, extra values",
        totalPoints: const Range(low: 16, high: 18),
        suitLengths: {mySuit: const Range(low: 6)},
      ),
      ignoreInfo: true,
      require: (h) => h.count(mySuit) >= 6,
    ),
  ]);
  // Jump shifts: 18+, lower-ranking suits only.
  for (final s in Suit.values) {
    if (s == mySuit ||
        s == partnerSuit ||
        _strainOrder(s) > _strainOrder(mySuit)) {
      continue;
    }
    final jumpLevel = cheapestLevel(s, response) + 1;
    if (jumpLevel > 3) continue;
    rules.add(SaycRule(
      BidAction.contract(jumpLevel, s),
      BidMeaning(
        description: "Jump shift: 4+ ${_suitNames[s]}, 18+ points",
        totalPoints: const Range(low: 18, high: 21),
        suitLengths: {s: const Range(low: 4)},
      ),
      ignoreInfo: true,
      require: (h) =>
          h.totalPoints >= 18 &&
          _secondSuitChoice(h, mySuit, {mySuit, partnerSuit}, response) == s,
    ));
  }
  for (final s in Suit.values) {
    if (s == mySuit || s == partnerSuit) continue;
    final level = cheapestLevel(s, response);
    if (level >= 3) continue;
    final isReverse = level >= 2 && _strainOrder(s) > _strainOrder(mySuit);
    rules.add(SaycRule(
      BidAction.contract(level, s),
      BidMeaning(
        description: "Second suit: 4+ ${_suitNames[s]}"
            "${isReverse ? ', reverse showing extra strength' : ''}",
        totalPoints: isReverse
            ? const Range(low: 17, high: 21)
            : const Range(low: 13, high: 17),
        suitLengths: {s: const Range(low: 4)},
      ),
      ignoreInfo: true,
      require: (h) =>
          _secondSuitChoice(h, mySuit, {mySuit, partnerSuit}, response) == s,
    ));
  }
  rules.add(SaycRule(
    BidAction.contract(cheapestLevel(mySuit, response), mySuit),
    BidMeaning(
      description: "Suit rebid, minimum with no better option",
      totalPoints: const Range(low: 13, high: 16),
      suitLengths: {mySuit: Range(low: _isMajor(mySuit) ? 5 : 3)},
    ),
    ignoreInfo: true,
  ));
  return rules;
}

// ---------------------------------------------------------------------------
// Responder's rebid (fourth call of the auction)
// ---------------------------------------------------------------------------

List<SaycRule>? responderRebidRules(
    BidAction opening, BidAction response, BidAction rebid) {
  if (rebid.bidType != BidType.contract) return null;
  if (opening == BidAction.noTrump(1)) {
    return _responderRebidAfter1ntRules(response, rebid);
  }
  if (opening == BidAction.noTrump(2)) {
    if (response == BidAction.contract(4, Suit.clubs)) {
      return gerberContinuationRules(rebid);
    }
    if (response == BidAction.noTrump(4)) {
      return [
        SaycRule(BidAction.pass(),
            BidMeaning(description: "Respecting partner's decision"))
      ];
    }
    return null;
  }
  if (opening == BidAction.contract(2, Suit.clubs)) {
    return _responderRebidAfter2cRules(response, rebid);
  }
  if (opening.bidType == BidType.contract &&
      opening.contractBid!.trump != null &&
      opening.contractBid!.count == 1) {
    return _responderRebidAfterSuitRules(
        opening.contractBid!, response, rebid.contractBid!);
  }
  return null;
}

List<SaycRule>? _responderRebidAfter1ntRules(
    BidAction response, BidAction rebid) {
  if (response == BidAction.contract(4, Suit.clubs)) {
    return gerberContinuationRules(rebid);
  }
  final rebidBid = rebid.contractBid!;
  if (response == BidAction.contract(2, Suit.clubs)) {
    // Stayman.
    final rules = <SaycRule>[];
    if (rebidBid.trump != null && _isMajor(rebidBid.trump!)) {
      final major = rebidBid.trump!;
      final name = _suitNames[major]!;
      rules.addAll([
        SaycRule(
          BidAction.contract(3, major),
          BidMeaning(
            description: "Invitational raise: 4 $name, 8-9 HCP",
            hcp: const Range(low: 8, high: 9),
            suitLengths: {major: const Range(low: 4)},
          ),
          ignoreInfo: true,
          require: (h) => h.count(major) >= 4 && h.hcp <= 9,
        ),
        SaycRule(
          BidAction.contract(4, major),
          BidMeaning(
            description: "Raise to game: 4 $name",
            hcp: const Range(low: 10, high: 15),
            suitLengths: {major: const Range(low: 4)},
          ),
          ignoreInfo: true,
          require: (h) => h.count(major) >= 4,
        ),
      ]);
    }
    rules.addAll([
      SaycRule(
        BidAction.noTrump(2),
        BidMeaning(
            description: "Inviting 3NT, no major-suit fit",
            hcp: const Range(low: 8, high: 9)),
        ignoreInfo: true,
        require: (h) => h.hcp <= 9,
      ),
      SaycRule(
        BidAction.noTrump(3),
        BidMeaning(
            description: "To play, no major-suit fit",
            hcp: const Range(low: 10, high: 15)),
        ignoreInfo: true,
      ),
    ]);
    return rules;
  }
  final transferTargets = {
    BidAction.contract(2, Suit.diamonds): Suit.hearts,
    BidAction.contract(2, Suit.hearts): Suit.spades,
  };
  if (transferTargets.containsKey(response)) {
    final major = transferTargets[response]!;
    final name = _suitNames[major]!;
    return [
      SaycRule(
        BidAction.pass(),
        BidMeaning(
            description: "Signing off after the transfer",
            hcp: const Range(high: 7)),
      ),
      SaycRule(
        BidAction.contract(3, major),
        BidMeaning(
          description: "Inviting game: 6+ $name, 8-9 HCP",
          hcp: const Range(low: 8, high: 9),
          suitLengths: {major: const Range(low: 6)},
        ),
      ),
      SaycRule(
        BidAction.noTrump(2),
        BidMeaning(
          description: "Inviting game: exactly 5 $name, 8-9 HCP",
          hcp: const Range(low: 8, high: 9),
          suitLengths: {major: const Range(low: 5, high: 5)},
        ),
      ),
      SaycRule(
        BidAction.contract(4, major),
        BidMeaning(
          description: "To play: 6+ $name, game values",
          hcp: const Range(low: 10, high: 15),
          suitLengths: {major: const Range(low: 6)},
        ),
        ignoreInfo: true,
        require: (h) => h.count(major) >= 6,
      ),
      SaycRule(
        BidAction.noTrump(3),
        BidMeaning(
          description:
              "Choice of games: exactly 5 $name, opener corrects with a fit",
          hcp: const Range(low: 10, high: 15),
          suitLengths: {major: const Range(low: 5, high: 5)},
        ),
        ignoreInfo: true,
      ),
    ];
  }
  if (rebid == BidAction.noTrump(3)) {
    return [
      SaycRule(BidAction.pass(),
          BidMeaning(description: "Respecting partner's signoff"))
    ];
  }
  return null;
}

List<SaycRule>? _responderRebidAfter2cRules(
    BidAction response, BidAction rebid) {
  if (response != BidAction.contract(2, Suit.diamonds)) return null;
  final rebidBid = rebid.contractBid!;
  if (rebid == BidAction.noTrump(2)) {
    // 22-24 balanced; simplified (no Stayman/transfers here yet).
    return [
      SaycRule(
        BidAction.noTrump(3),
        BidMeaning(description: "To play", hcp: const Range(low: 3)),
      ),
      SaycRule(
        BidAction.pass(),
        BidMeaning(
            description: "Bust hand, no game", hcp: const Range(high: 2)),
      ),
    ];
  }
  if (rebidBid.trump != null && _isMajor(rebidBid.trump!)) {
    final major = rebidBid.trump!;
    final name = _suitNames[major]!;
    return [
      SaycRule(
        BidAction.contract(4, major),
        BidMeaning(
          description: "Raise to game: 3+ $name",
          suitLengths: {major: const Range(low: 3)},
        ),
      ),
      SaycRule(
        BidAction.noTrump(rebidBid.count == 2 ? 2 : 3),
        BidMeaning(
          description: "No fit for $name; keeping the auction alive",
          suitLengths: {major: const Range(high: 2)},
        ),
      ),
    ];
  }
  if (rebidBid.trump != null) {
    return [
      SaycRule(
        BidAction.noTrump(3),
        BidMeaning(description: "Game in notrump over partner's minor"),
      )
    ];
  }
  if (rebid == BidAction.noTrump(3)) {
    return [
      SaycRule(BidAction.pass(),
          BidMeaning(description: "Respecting partner's signoff"))
    ];
  }
  return null;
}

List<SaycRule> _responderRebidAfterSuitRules(
    ContractBid opening, BidAction response, ContractBid rebid) {
  final oSuit = opening.trump!;
  final oMajor = _isMajor(oSuit);
  final oName = _suitNames[oSuit]!;
  final oGame =
      oMajor ? BidAction.contract(4, oSuit) : BidAction.noTrump(3);
  final responseBid =
      response.bidType == BidType.contract ? response.contractBid! : null;

  List<SaycRule> passOnly(String description) =>
      [SaycRule(BidAction.pass(), BidMeaning(description: description))];

  // Our response was a raise: opener either invited or signed off.
  if (responseBid != null && responseBid.trump == oSuit) {
    if (rebid == ContractBid(3, oSuit) && responseBid.count == 2) {
      return [
        SaycRule(
          oGame,
          BidMeaning(
              description: "Accepting the game try, maximum raise",
              totalPoints: const Range(low: 9, high: 10)),
          ignoreInfo: true,
          require: (h) => h.totalPoints >= 9,
        ),
        SaycRule(
          BidAction.pass(),
          BidMeaning(
              description: "Declining the game try",
              totalPoints: const Range(low: 6, high: 8)),
          ignoreInfo: true,
        ),
      ];
    }
    return passOnly("Respecting partner's signoff");
  }

  // Our response was 2NT: Jacoby over a major, natural over a minor.
  if (response == BidAction.noTrump(2)) {
    if (oMajor) {
      if (rebid == ContractBid(4, oSuit)) {
        return [
          SaycRule(
            BidAction.noTrump(4),
            BidMeaning(
                description: "Blackwood: asking for aces",
                totalPoints: const Range(low: 18),
                artificial: true),
          ),
          SaycRule(
            BidAction.pass(),
            BidMeaning(
                description: "Game reached; no slam interest",
                totalPoints: const Range(low: 13, high: 17)),
            ignoreInfo: true,
          ),
        ];
      }
      return [
        SaycRule(
          BidAction.noTrump(4),
          BidMeaning(
              description: "Blackwood: asking for aces",
              totalPoints: const Range(low: 16),
              artificial: true),
        ),
        SaycRule(
          BidAction.contract(4, oSuit),
          BidMeaning(
              description: "Returning to game",
              totalPoints: const Range(low: 13, high: 15)),
          ignoreInfo: true,
        ),
      ];
    }
    if (rebid == ContractBid.noTrump(3)) {
      return passOnly("Respecting partner's signoff");
    }
    return [
      SaycRule(BidAction.noTrump(3),
          BidMeaning(description: "Offering 3NT with 13-15 balanced"))
    ];
  }

  // Our response was 1NT (6-9): keep it low.
  if (response == BidAction.noTrump(1)) {
    if (rebid.trump == oSuit) {
      if (rebid.count == 2) {
        return [
          SaycRule(
            BidAction.pass(),
            BidMeaning(
                description: "Nothing more to say",
                totalPoints: const Range(low: 6, high: 9)),
          )
        ];
      }
      return [
        SaycRule(
          oGame,
          BidMeaning(
              description: "Accepting the invitation",
              totalPoints: const Range(low: 8, high: 9)),
          ignoreInfo: true,
          require: (h) => h.totalPoints >= 8,
        ),
        SaycRule(
          BidAction.pass(),
          BidMeaning(
              description: "Declining the invitation",
              totalPoints: const Range(low: 6, high: 7)),
          ignoreInfo: true,
        ),
      ];
    }
    if (rebid == ContractBid.noTrump(2)) {
      // 18-19.
      return [
        SaycRule(
          BidAction.noTrump(3),
          BidMeaning(
              description: "Raising to game", hcp: const Range(low: 7, high: 9)),
          ignoreInfo: true,
          require: (h) => h.hcp >= 7,
        ),
        SaycRule(
          BidAction.pass(),
          BidMeaning(
              description: "Minimum for the 1NT response",
              hcp: const Range(high: 6)),
          ignoreInfo: true,
        ),
      ];
    }
    if (rebid.trump != null) {
      final second = rebid.trump!;
      if (rebid.count > cheapestLevel(second, ContractBid.noTrump(1))) {
        // Jump shift after our 1NT: 18+, one-round force.
        final rules = <SaycRule>[];
        if (_isMajor(second)) {
          rules.add(SaycRule(
            BidAction.contract(4, second),
            BidMeaning(
              description:
                  "Game: 3+ ${_suitNames[second]} opposite a jump shift",
              totalPoints: const Range(low: 7, high: 9),
              suitLengths: {second: const Range(low: 3)},
            ),
            ignoreInfo: true,
            require: (h) => h.count(second) >= 3 && h.totalPoints >= 7,
          ));
        }
        if (cheapestLevel(null, rebid) <= 3) {
          rules.add(SaycRule(
            BidAction.noTrump(3),
            BidMeaning(
                description: "Game opposite a jump shift",
                totalPoints: const Range(low: 7, high: 9)),
            ignoreInfo: true,
            require: (h) => h.totalPoints >= 7,
          ));
        }
        rules.add(SaycRule(
          BidAction.contract(cheapestLevel(oSuit, rebid), oSuit),
          BidMeaning(
              description: "Minimum preference to $oName",
              totalPoints: const Range(low: 6, high: 6)),
          ignoreInfo: true,
        ));
        return rules;
      }
      return [
        SaycRule(
          BidAction.contract(cheapestLevel(oSuit, rebid), oSuit),
          BidMeaning(
              description: "Preference to $oName, no extra values",
              totalPoints: const Range(low: 6, high: 9)),
          ignoreInfo: true,
          require: (h) => h.count(oSuit) >= h.count(second),
        ),
        SaycRule(
          BidAction.pass(),
          BidMeaning(
              description:
                  "Preferring ${_suitNames[second]}, no extra values",
              totalPoints: const Range(low: 6, high: 9)),
          ignoreInfo: true,
        ),
      ];
    }
    return passOnly("Nothing more to say");
  }

  if (responseBid == null || responseBid.trump == null) {
    // 3NT and higher notrump responses: partner decided.
    return passOnly("Respecting partner's decision");
  }

  // Our response was a new suit.
  final mySuit = responseBid.trump!;
  final myName = _suitNames[mySuit]!;
  final myMajor = _isMajor(mySuit);
  final myGame =
      myMajor ? BidAction.contract(4, mySuit) : BidAction.noTrump(3);
  final myGameBid = myMajor ? ContractBid(4, mySuit) : ContractBid.noTrump(3);

  if (rebid.trump == mySuit) {
    // Opener raised us.
    final gameIsLegal = myGameBid.isHigherThan(rebid);
    if (rebid.count == responseBid.count + 1) {
      if (!gameIsLegal) {
        return passOnly("Partner has bid game; nothing to add");
      }
      if (responseBid.count == 2) {
        return [
          SaycRule(
            myGame,
            BidMeaning(
                description: "Going on to game",
                totalPoints: const Range(low: 12)),
          ),
          SaycRule(
            BidAction.pass(),
            BidMeaning(
                description: "Minimum two-over-one",
                totalPoints: const Range(low: 10, high: 11)),
            ignoreInfo: true,
          ),
        ];
      }
      if (responseBid.count >= 3) {
        return [
          SaycRule(
            myGame,
            BidMeaning(
                description: "Going on to game",
                totalPoints: const Range(low: 12)),
          ),
          SaycRule(BidAction.pass(),
              BidMeaning(description: "Nothing more to say")),
        ];
      }
      final invite = myMajor
          ? BidAction.contract(responseBid.count + 2, mySuit)
          : BidAction.noTrump(2);
      return [
        SaycRule(
          BidAction.pass(),
          BidMeaning(
              description: "Minimum response",
              totalPoints: const Range(low: 6, high: 10)),
          ignoreInfo: true,
          require: (h) => h.totalPoints <= 10,
        ),
        SaycRule(
          invite,
          BidMeaning(
              description: "Inviting game",
              totalPoints: const Range(low: 11, high: 12)),
          ignoreInfo: true,
          require: (h) => h.totalPoints <= 12,
        ),
        SaycRule(
          myGame,
          BidMeaning(
              description: "Bidding game", totalPoints: const Range(low: 13)),
          ignoreInfo: true,
        ),
      ];
    }
    if (rebid.count == responseBid.count + 2) {
      // Jump raise, 16-18.
      if (!gameIsLegal) {
        if (!myMajor && rebid.count == 4) {
          return [
            SaycRule(
              BidAction.contract(5, mySuit),
              BidMeaning(
                  description: "Accepting the invitation",
                  totalPoints: const Range(low: 10)),
            ),
            SaycRule(
                BidAction.pass(),
                BidMeaning(description: "Declining the invitation"),
                ignoreInfo: true),
          ];
        }
        return passOnly("Partner has bid game; nothing to add");
      }
      return [
        SaycRule(
          myGame,
          BidMeaning(
              description: "Accepting the invitation",
              totalPoints: const Range(low: 8)),
        ),
        SaycRule(
          BidAction.pass(),
          BidMeaning(
              description: "Declining the invitation",
              totalPoints: const Range(low: 6, high: 7)),
          ignoreInfo: true,
        ),
      ];
    }
    return passOnly("Respecting partner's signoff");
  }

  if (rebid.trump == null) {
    if (rebid.count >= 3) {
      return passOnly("Respecting partner's game decision");
    }
    if (rebid.count == responseBid.count) {
      // Cheapest notrump.
      if (responseBid.count == 2) {
        // 2NT after a two-over-one (12-14).
        return [
          SaycRule(
            BidAction.noTrump(3),
            BidMeaning(
                description: "Raising to game",
                totalPoints: const Range(low: 12)),
          ),
          SaycRule(
            BidAction.pass(),
            BidMeaning(
                description: "Minimum two-over-one",
                totalPoints: const Range(low: 10, high: 11)),
            ignoreInfo: true,
          ),
        ];
      }
      // 1NT rebid, 12-14.
      return [
        SaycRule(
          BidAction.contract(2, mySuit),
          BidMeaning(
            description: "Signoff: 6+ $myName",
            totalPoints: const Range(low: 6, high: 10),
            suitLengths: {mySuit: const Range(low: 6)},
          ),
          ignoreInfo: true,
          require: (h) =>
              myMajor && h.count(mySuit) >= 6 && h.totalPoints <= 10,
        ),
        SaycRule(
          BidAction.contract(3, mySuit),
          BidMeaning(
            description: "Inviting game with 6+ $myName",
            totalPoints: const Range(low: 11, high: 12),
            suitLengths: {mySuit: const Range(low: 6)},
          ),
          ignoreInfo: true,
          require: (h) =>
              myMajor && h.count(mySuit) >= 6 && h.totalPoints <= 12,
        ),
        SaycRule(
          BidAction.contract(4, mySuit),
          BidMeaning(
            description: "Game with 6+ $myName",
            totalPoints: const Range(low: 13),
            suitLengths: {mySuit: const Range(low: 6)},
          ),
          ignoreInfo: true,
          require: (h) => myMajor && h.count(mySuit) >= 6,
        ),
        SaycRule(
          BidAction.pass(),
          BidMeaning(
              description: "Nothing more to say",
              totalPoints: const Range(low: 6, high: 10)),
          ignoreInfo: true,
          require: (h) => h.totalPoints <= 10,
        ),
        SaycRule(
          BidAction.noTrump(2),
          BidMeaning(
              description: "Inviting game",
              totalPoints: const Range(low: 11, high: 12)),
          ignoreInfo: true,
          require: (h) => h.totalPoints <= 12,
        ),
        SaycRule(
          BidAction.noTrump(3),
          BidMeaning(
              description: "Bidding game", totalPoints: const Range(low: 13)),
          ignoreInfo: true,
        ),
      ];
    }
    // Jump to 2NT (18-19).
    return [
      SaycRule(
        BidAction.contract(4, mySuit),
        BidMeaning(
          description: "Game with 6+ $myName",
          suitLengths: {mySuit: const Range(low: 6)},
        ),
        ignoreInfo: true,
        require: (h) => myMajor && h.count(mySuit) >= 6,
      ),
      SaycRule(
          BidAction.noTrump(3), BidMeaning(description: "Raising to game")),
    ];
  }

  if (rebid.trump == oSuit) {
    // Opener rebid its own suit.
    if (rebid.count == cheapestLevel(oSuit, responseBid)) {
      // Minimum rebid.
      final rules = <SaycRule>[
        SaycRule(
          BidAction.contract(cheapestLevel(mySuit, rebid), mySuit),
          BidMeaning(
            description: "Signoff: 6+ $myName",
            totalPoints: const Range(low: 6, high: 10),
            suitLengths: {mySuit: const Range(low: 6)},
          ),
          ignoreInfo: true,
          require: (h) =>
              myMajor && h.count(mySuit) >= 6 && h.totalPoints <= 10,
        ),
        SaycRule(
          BidAction.pass(),
          BidMeaning(
              description: "Nothing more to say",
              totalPoints: const Range(low: 6, high: 10)),
          ignoreInfo: true,
          require: (h) => h.totalPoints <= 10,
        ),
      ];
      if (rebid.count + 1 < (oMajor ? 4 : 5)) {
        rules.add(SaycRule(
          BidAction.contract(rebid.count + 1, oSuit),
          BidMeaning(
            description: "Inviting game in $oName",
            totalPoints: const Range(low: 11, high: 12),
            suitLengths: {oSuit: const Range(low: 3)},
          ),
          ignoreInfo: true,
          require: (h) => h.totalPoints <= 12 && h.count(oSuit) >= 3,
        ));
      }
      if (cheapestLevel(null, rebid) <= 2) {
        rules.add(SaycRule(
          BidAction.noTrump(2),
          BidMeaning(
              description: "Inviting game",
              totalPoints: const Range(low: 11, high: 12)),
          ignoreInfo: true,
          require: (h) => h.totalPoints <= 12,
        ));
      }
      rules.addAll([
        SaycRule(
          BidAction.contract(4, oSuit),
          BidMeaning(
              description: "Bidding game", totalPoints: const Range(low: 13)),
          ignoreInfo: true,
          require: (h) =>
              oMajor &&
              rebid.count < 4 &&
              h.count(oSuit) >= 2 &&
              h.totalPoints >= 13,
        ),
        SaycRule(
          BidAction.noTrump(3),
          BidMeaning(
              description: "Bidding game", totalPoints: const Range(low: 13)),
          ignoreInfo: true,
          require: (h) =>
              h.totalPoints >= 13 && cheapestLevel(null, rebid) <= 3,
        ),
        SaycRule(
            BidAction.pass(),
            BidMeaning(
                description: "No convenient call; settling for a partscore"),
            ignoreInfo: true),
      ]);
      return rules;
    }
    // Jump rebid, 16-18.
    if (rebid.count >= 4) {
      return passOnly("Respecting partner's game decision");
    }
    return [
      SaycRule(
        BidAction.contract(4, oSuit),
        BidMeaning(
            description: "Accepting the invitation",
            totalPoints: const Range(low: 8)),
        ignoreInfo: true,
        require: (h) =>
            h.totalPoints >= 8 && oMajor && h.count(oSuit) >= 2,
      ),
      SaycRule(
        BidAction.noTrump(3),
        BidMeaning(
            description: "Accepting the invitation",
            totalPoints: const Range(low: 8)),
      ),
      SaycRule(
        BidAction.pass(),
        BidMeaning(
            description: "Declining the invitation",
            totalPoints: const Range(low: 6, high: 7)),
        ignoreInfo: true,
      ),
    ];
  }

  // Opener showed a second suit.
  final second = rebid.trump!;
  final sName = _suitNames[second]!;
  final isReverse =
      rebid.count >= 2 && _strainOrder(second) > _strainOrder(oSuit);
  final isJump = rebid.count > cheapestLevel(second, responseBid);
  if (isReverse || isJump) {
    // A reverse or jump shift shows 17+: responder moves toward game with
    // 8+ and otherwise retreats as cheaply as possible.
    final rules = <SaycRule>[];
    if (_isMajor(second)) {
      rules.add(SaycRule(
        BidAction.contract(4, second),
        BidMeaning(
          description: "Raise to game: 4+ $sName opposite a strong rebid",
          totalPoints: const Range(low: 8),
          suitLengths: {second: const Range(low: 4)},
        ),
        ignoreInfo: true,
        require: (h) => h.count(second) >= 4 && h.totalPoints >= 8,
      ));
    }
    if (cheapestLevel(null, rebid) <= 3) {
      rules.add(SaycRule(
        BidAction.noTrump(3),
        BidMeaning(
            description: "Choosing game opposite a strong rebid",
            totalPoints: const Range(low: 8)),
        ignoreInfo: true,
        require: (h) => h.totalPoints >= 8,
      ));
    }
    rules.addAll([
      SaycRule(
        BidAction.contract(cheapestLevel(mySuit, rebid), mySuit),
        BidMeaning(
          description: "Minimum rebid of a 5+ card suit",
          totalPoints: const Range(low: 6, high: 7),
          suitLengths: {mySuit: const Range(low: 5)},
        ),
        ignoreInfo: true,
        require: (h) => h.count(mySuit) >= 5 && h.totalPoints <= 7,
      ),
      SaycRule(
        BidAction.contract(cheapestLevel(oSuit, rebid), oSuit),
        BidMeaning(
            description: "Minimum preference to $oName",
            totalPoints: const Range(low: 6, high: 7)),
        ignoreInfo: true,
        require: (h) => h.totalPoints <= 7,
      ),
      SaycRule(BidAction.pass(), BidMeaning(description: "Nothing suitable"),
          ignoreInfo: true),
    ]);
    return rules;
  }
  final rules = <SaycRule>[];
  if (_isMajor(second)) {
    rules.addAll([
      SaycRule(
        BidAction.contract(rebid.count + 1, second),
        BidMeaning(
          description: "Raise: 4+ $sName, minimum",
          totalPoints: const Range(low: 6, high: 9),
          suitLengths: {second: const Range(low: 4)},
        ),
      ),
      SaycRule(
        BidAction.contract(rebid.count + 2 > 4 ? 4 : rebid.count + 2, second),
        BidMeaning(
          description: "Jump raise: 4+ $sName, invitational",
          totalPoints: const Range(low: 10, high: 12),
          suitLengths: {second: const Range(low: 4)},
        ),
      ),
      SaycRule(
        BidAction.contract(4, second),
        BidMeaning(
          description: "Raise to game: 4+ $sName",
          totalPoints: const Range(low: 13),
          suitLengths: {second: const Range(low: 4)},
        ),
        ignoreInfo: true,
        require: (h) => h.count(second) >= 4,
      ),
    ]);
  }
  rules.add(SaycRule(
    BidAction.contract(cheapestLevel(mySuit, rebid), mySuit),
    BidMeaning(
      description: "Signoff: 6+ $myName",
      totalPoints: const Range(low: 6, high: 10),
      suitLengths: {mySuit: const Range(low: 6)},
    ),
    ignoreInfo: true,
    require: (h) =>
        myMajor && h.count(mySuit) >= 6 && h.totalPoints <= 10,
  ));
  if (rebid.count == 1) {
    rules.add(SaycRule(
      BidAction.noTrump(1),
      BidMeaning(
          description: "6-10, no fit for either suit",
          totalPoints: const Range(low: 6, high: 10)),
      ignoreInfo: true,
      require: (h) => h.totalPoints <= 10,
    ));
  } else {
    rules.addAll([
      SaycRule(
        BidAction.contract(cheapestLevel(oSuit, rebid), oSuit),
        BidMeaning(
            description: "Preference to $oName, no extra values",
            totalPoints: const Range(low: 6, high: 10)),
        ignoreInfo: true,
        require: (h) =>
            h.totalPoints <= 10 && h.count(oSuit) >= h.count(second),
      ),
      SaycRule(
        BidAction.pass(),
        BidMeaning(
            description: "Preferring $sName, no extra values",
            totalPoints: const Range(low: 6, high: 10)),
        ignoreInfo: true,
        require: (h) => h.totalPoints <= 10,
      ),
    ]);
  }
  if (cheapestLevel(null, rebid) <= 2) {
    rules.add(SaycRule(
      BidAction.noTrump(2),
      BidMeaning(
          description: "Inviting game",
          totalPoints: const Range(low: 11, high: 12)),
      ignoreInfo: true,
      require: (h) => h.totalPoints <= 12,
    ));
  }
  if (cheapestLevel(null, rebid) <= 3) {
    rules.add(SaycRule(
      BidAction.noTrump(3),
      BidMeaning(
          description: "Bidding game", totalPoints: const Range(low: 13)),
      ignoreInfo: true,
    ));
  }
  rules.add(SaycRule(
      BidAction.pass(), BidMeaning(description: "Nothing suitable"),
      ignoreInfo: true));
  return rules;
}

// ---------------------------------------------------------------------------
// Opener's third call (fifth call of the auction, uncontested)
// ---------------------------------------------------------------------------

List<SaycRule>? openerThirdCallRules(
    BidAction opening, BidAction response, BidAction rebid, BidAction r2) {
  if (r2.bidType != BidType.contract) return null;
  if (opening == BidAction.noTrump(1)) {
    return _oneNtOpenerThirdRules(response, rebid, r2);
  }
  if (opening == BidAction.noTrump(2)) {
    return [
      SaycRule(BidAction.pass(),
          BidMeaning(description: "Responder has placed the contract"))
    ];
  }
  if (opening == BidAction.contract(2, Suit.clubs)) {
    if (r2 == BidAction.noTrump(4)) return blackwoodAnswerRules();
    if (r2 == BidAction.noTrump(2)) {
      // Responder denied a fit but the 2C auction is game-forcing.
      final rules = <SaycRule>[];
      final rebidBid =
          rebid.bidType == BidType.contract ? rebid.contractBid : null;
      if (rebidBid?.trump != null && _isMajor(rebidBid!.trump!)) {
        final major = rebidBid.trump!;
        rules.add(SaycRule(
          BidAction.contract(4, major),
          BidMeaning(
            description: "Insisting on game with a self-sufficient suit",
            suitLengths: {major: const Range(low: 6)},
          ),
          require: (h) => h.count(major) >= 6,
        ));
      }
      rules.add(SaycRule(
        BidAction.noTrump(3),
        BidMeaning(
            description: "Choosing game; the 2C auction is game-forcing"),
      ));
      return rules;
    }
    return [
      SaycRule(BidAction.pass(),
          BidMeaning(description: "Responder has placed the contract"))
    ];
  }
  if (opening.bidType == BidType.contract &&
      opening.contractBid!.trump != null &&
      opening.contractBid!.count == 1) {
    return _oneSuitOpenerThirdRules(
        opening.contractBid!, response, rebid, r2.contractBid!);
  }
  return [
    SaycRule(BidAction.pass(),
        BidMeaning(description: "Preemptive opener never bids again"))
  ];
}

List<SaycRule> _oneNtOpenerThirdRules(
    BidAction response, BidAction rebid, BidAction r2) {
  final defaultRules = [
    SaycRule(BidAction.pass(),
        BidMeaning(description: "Responder has placed the contract"))
  ];
  List<SaycRule> quantitative() => [
        SaycRule(
          BidAction.noTrump(6),
          BidMeaning(
              description: "Accepting the slam invitation",
              hcp: const Range(low: 17, high: 17)),
        ),
        SaycRule(
          BidAction.pass(),
          BidMeaning(
              description: "Declining the slam invitation",
              hcp: const Range(low: 15, high: 16)),
        ),
      ];

  if (response == BidAction.contract(2, Suit.clubs)) {
    // Stayman.
    if (r2 == BidAction.noTrump(4)) return quantitative();
    if (r2 == BidAction.noTrump(2)) {
      final rules = <SaycRule>[];
      if (rebid == BidAction.contract(2, Suit.hearts)) {
        // Responder's major was spades; with four we belong there.
        rules.add(SaycRule(
          BidAction.contract(4, Suit.spades),
          BidMeaning(
            description: "Maximum with four spades (responder's major)",
            hcp: const Range(low: 16, high: 17),
            suitLengths: {Suit.spades: const Range(low: 4, high: 5)},
          ),
        ));
      }
      rules.addAll([
        SaycRule(
          BidAction.noTrump(3),
          BidMeaning(
              description: "Accepting the invitation",
              hcp: const Range(low: 16, high: 17)),
        ),
        SaycRule(
          BidAction.pass(),
          BidMeaning(
              description: "Declining the invitation",
              hcp: const Range(low: 15, high: 15)),
        ),
      ]);
      return rules;
    }
    if (r2 == BidAction.noTrump(3)) {
      if (rebid == BidAction.contract(2, Suit.hearts)) {
        return [
          SaycRule(
            BidAction.contract(4, Suit.spades),
            BidMeaning(
              description: "Correcting to the 4-4 spade fit",
              suitLengths: {Suit.spades: const Range(low: 4, high: 5)},
            ),
          ),
          SaycRule(
            BidAction.pass(),
            BidMeaning(
              description: "No spade fit; 3NT stands",
              suitLengths: {Suit.spades: const Range(high: 3)},
            ),
          ),
        ];
      }
      return defaultRules;
    }
    if (r2.bidType == BidType.contract &&
        r2.contractBid!.count == 3 &&
        r2.contractBid!.trump != null &&
        _isMajor(r2.contractBid!.trump!) &&
        rebid.bidType == BidType.contract &&
        r2.contractBid!.trump == rebid.contractBid!.trump) {
      // Invitational raise of our major.
      return [
        SaycRule(
          BidAction.contract(4, r2.contractBid!.trump!),
          BidMeaning(
              description: "Accepting the invitation",
              hcp: const Range(low: 16, high: 17)),
        ),
        SaycRule(
          BidAction.pass(),
          BidMeaning(
              description: "Declining the invitation",
              hcp: const Range(low: 15, high: 15)),
        ),
      ];
    }
    return defaultRules;
  }
  final transferTargets = {
    BidAction.contract(2, Suit.diamonds): Suit.hearts,
    BidAction.contract(2, Suit.hearts): Suit.spades,
  };
  if (transferTargets.containsKey(response)) {
    final major = transferTargets[response]!;
    final name = _suitNames[major]!;
    if (r2 == BidAction.noTrump(2)) {
      // Invitation with exactly five of the major.
      return [
        SaycRule(
          BidAction.contract(4, major),
          BidMeaning(
            description: "Maximum with 3+ $name",
            hcp: const Range(low: 16, high: 17),
            suitLengths: {major: const Range(low: 3, high: 5)},
          ),
        ),
        SaycRule(
          BidAction.noTrump(3),
          BidMeaning(
              description: "Maximum, no fit",
              hcp: const Range(low: 16, high: 17)),
        ),
        SaycRule(
          BidAction.pass(),
          BidMeaning(
              description: "Minimum", hcp: const Range(low: 15, high: 15)),
        ),
      ];
    }
    if (r2 == BidAction.contract(3, major)) {
      return [
        SaycRule(
          BidAction.contract(4, major),
          BidMeaning(
              description: "Accepting the invitation",
              hcp: const Range(low: 16, high: 17)),
        ),
        SaycRule(
          BidAction.pass(),
          BidMeaning(
              description: "Declining the invitation",
              hcp: const Range(low: 15, high: 15)),
        ),
      ];
    }
    if (r2 == BidAction.noTrump(3)) {
      // Choice of games with exactly five of the major.
      return [
        SaycRule(
          BidAction.contract(4, major),
          BidMeaning(
            description: "Choice of games: 3+ $name",
            suitLengths: {major: const Range(low: 3, high: 5)},
          ),
        ),
        SaycRule(
          BidAction.pass(),
          BidMeaning(
            description: "Doubleton $name; 3NT stands",
            suitLengths: {major: const Range(high: 2)},
          ),
        ),
      ];
    }
    if (r2 == BidAction.noTrump(4)) return quantitative();
    return defaultRules;
  }
  return defaultRules;
}

List<SaycRule> _oneSuitOpenerThirdRules(
    ContractBid opening, BidAction response, BidAction rebid, ContractBid r2) {
  final oSuit = opening.trump!;
  final defaultRules = [
    SaycRule(BidAction.pass(),
        BidMeaning(description: "Responder has placed the contract"))
  ];
  final rebidBid =
      rebid.bidType == BidType.contract ? rebid.contractBid : null;
  final responseBid =
      response.bidType == BidType.contract ? response.contractBid : null;
  if (rebidBid == null || responseBid == null) return defaultRules;

  // 4NT: quantitative over our notrump rebid, Blackwood otherwise.
  if (r2 == ContractBid.noTrump(4)) {
    if (rebidBid.trump == null) {
      if (rebidBid.count == responseBid.count) {
        // 12-14 shown.
        return [
          SaycRule(
            BidAction.noTrump(6),
            BidMeaning(
                description: "Accepting the slam invitation",
                hcp: const Range(low: 14, high: 14)),
          ),
          SaycRule(
            BidAction.pass(),
            BidMeaning(
                description: "Declining the slam invitation",
                hcp: const Range(low: 12, high: 13)),
          ),
        ];
      }
      // 18-19 shown.
      return [
        SaycRule(
          BidAction.noTrump(6),
          BidMeaning(
              description: "Accepting the slam invitation",
              hcp: const Range(low: 19, high: 19)),
        ),
        SaycRule(
          BidAction.pass(),
          BidMeaning(
              description: "Declining the slam invitation",
              hcp: const Range(low: 18, high: 18)),
        ),
      ];
    }
    return blackwoodAnswerRules();
  }

  List<SaycRule> inviteRules(
      BidAction accept, int threshold, Range shown, bool useHcp) {
    int value(HandAnalysis h) => useHcp ? h.hcp : h.totalPoints;
    final acceptRange = Range(low: threshold, high: shown.high);
    final declineRange = Range(low: shown.low, high: threshold - 1);
    return [
      SaycRule(
        accept,
        useHcp
            ? BidMeaning(
                description: "Accepting the invitation", hcp: acceptRange)
            : BidMeaning(
                description: "Accepting the invitation",
                totalPoints: acceptRange),
        ignoreInfo: true,
        require: (h) => value(h) >= threshold,
      ),
      SaycRule(
        BidAction.pass(),
        useHcp
            ? BidMeaning(
                description: "Declining the invitation", hcp: declineRange)
            : BidMeaning(
                description: "Declining the invitation",
                totalPoints: declineRange),
        ignoreInfo: true,
      ),
    ];
  }

  BidAction suitGame(Suit suit) {
    if (_isMajor(suit)) return BidAction.contract(4, suit);
    // Minor-suit game: prefer 3NT when still available over responder's
    // last call, otherwise five of the minor.
    if (cheapestLevel(null, r2) <= 3) return BidAction.noTrump(3);
    return BidAction.contract(5, suit);
  }

  if (rebidBid.trump == null && rebidBid.count == responseBid.count) {
    // 12-14 notrump rebid.
    if (r2 == ContractBid.noTrump(2)) {
      return inviteRules(
          BidAction.noTrump(3), 13, const Range(low: 12, high: 14), true);
    }
    if (r2.trump != null && r2.count == 3) {
      return inviteRules(
          suitGame(r2.trump!), 13, const Range(low: 12, high: 14), true);
    }
    return defaultRules;
  }
  if (rebidBid.trump == null) {
    // 18-19 jump: responder placed the contract.
    return defaultRules;
  }
  if (responseBid.trump != null && rebidBid.trump == responseBid.trump) {
    // We raised responder's suit.
    final single = rebidBid.count == responseBid.count + 1;
    final threshold = single ? 14 : 17;
    final shown =
        single ? const Range(low: 13, high: 15) : const Range(low: 16, high: 18);
    final gameLevel = _isMajor(responseBid.trump!) ? 4 : 5;
    if (r2.trump == responseBid.trump &&
        r2.count == rebidBid.count + 1 &&
        r2.count < gameLevel) {
      return inviteRules(suitGame(responseBid.trump!), threshold, shown, false);
    }
    if (r2 == ContractBid.noTrump(2)) {
      return inviteRules(suitGame(responseBid.trump!), threshold, shown, false);
    }
    return defaultRules;
  }
  if (rebidBid.trump == oSuit) {
    // We rebid our own suit.
    final single = rebidBid.count == cheapestLevel(oSuit, responseBid);
    final threshold = single ? 14 : 17;
    final shown =
        single ? const Range(low: 13, high: 15) : const Range(low: 16, high: 18);
    final gameLevel = _isMajor(oSuit) ? 4 : 5;
    if (r2.trump == oSuit &&
        r2.count == rebidBid.count + 1 &&
        r2.count < gameLevel) {
      return inviteRules(suitGame(oSuit), threshold, shown, false);
    }
    if (r2 == ContractBid.noTrump(2)) {
      return inviteRules(BidAction.noTrump(3), threshold, shown, false);
    }
    return defaultRules;
  }
  // We showed a second suit (13-18).
  if (r2 == ContractBid.noTrump(1)) {
    return [
      SaycRule(
        BidAction.noTrump(2),
        BidMeaning(
            description: "Inviting game with extra values",
            totalPoints: const Range(low: 17, high: 18)),
        ignoreInfo: true,
        require: (h) => h.totalPoints >= 17,
      ),
      ...defaultRules,
    ];
  }
  if (r2 == ContractBid.noTrump(2)) {
    return inviteRules(
        BidAction.noTrump(3), 15, const Range(low: 13, high: 18), false);
  }
  if (r2.trump == rebidBid.trump &&
      r2.count == rebidBid.count + 2 &&
      r2.count < (_isMajor(rebidBid.trump!) ? 4 : 5)) {
    // Invitational jump raise of the second suit.
    return inviteRules(
        suitGame(rebidBid.trump!), 15, const Range(low: 13, high: 18), false);
  }
  return defaultRules;
}

// ---------------------------------------------------------------------------
// Auction dispatch and public API
// ---------------------------------------------------------------------------

/// The ordered candidate rules for the next call in this auction, or null if
/// the position has not been ported yet (callers should fall back to the
/// legacy engine). Throws [StateError] if the auction is already over.
List<SaycRule>? saycRulesForAuction(List<BidAction> calls) {
  final n = calls.length;
  if (n >= 4 &&
      calls.sublist(n - 3).every((c) => c.bidType == BidType.pass)) {
    throw StateError("The auction is already over");
  }
  int? first;
  for (int i = 0; i < n; i++) {
    if (calls[i].bidType != BidType.pass) {
      first = i;
      break;
    }
  }
  if (first == null) return openingRules();

  // Positions relative to the caller: (n - i) % 4 is 0 for the caller's own
  // calls, 2 for partner's, and odd for the opponents'.
  final openerOffset = (n - first) % 4;
  final anyOpponentAction = Iterable.generate(n).any(
      (i) => (n - i) % 2 == 1 && calls[i].bidType != BidType.pass);

  if (openerOffset == 2 && !anyOpponentAction) {
    // Partner opened, uncontested.
    if (n == first + 2) return responseRules(calls[first]);
    if (n == first + 6) {
      return responderRebidRules(
          calls[first], calls[first + 2], calls[first + 4]);
    }
    if (n == first + 10 && calls[first + 6] == BidAction.noTrump(4)) {
      // Placing the contract after partner answered our Blackwood 4NT.
      return blackwoodPlacementRules(
          calls[first], calls[first + 2], calls[first + 4], calls[first + 8]);
    }
    return null;
  }
  if (openerOffset == 0 && !anyOpponentAction) {
    // We opened, uncontested.
    if (n == first + 4) {
      return openerRebidRules(calls[first], calls[first + 2]);
    }
    if (n == first + 8) {
      return openerThirdCallRules(
          calls[first], calls[first + 2], calls[first + 4], calls[first + 6]);
    }
    return null;
  }
  return null; // not ported yet
}

class SaycBid {
  final BidAction action;
  final BidMeaning meaning;

  SaycBid(this.action, this.meaning);

  @override
  String toString() => "$action (${meaning.summary()})";
}

/// Choose a call for `hand` given the auction so far (dealer's call first).
/// Returns null when the position is outside the ported rule tables.
SaycBid? selectSaycBid(List<PlayingCard> hand, List<BidAction> history,
    {Vulnerability vulnerability = Vulnerability.neither}) {
  final rules = saycRulesForAuction(history);
  if (rules == null) return null;
  final analysis = HandAnalysis(hand);
  for (final rule in rules) {
    if (rule.matches(analysis)) return SaycBid(rule.action, rule.meaning);
  }
  return SaycBid(
    BidAction.pass(),
    BidMeaning(description: "No rule matched; passing by default"),
  );
}

/// What `call` would show in this auction, independent of any hand. Returns
/// null when the position is not ported or the engine attaches no meaning to
/// that call here. When a call has several meanings, the merged (union)
/// interpretation is returned.
BidMeaning? describeSaycCall(List<BidAction> history, BidAction call) {
  final rules = saycRulesForAuction(history);
  if (rules == null) return null;
  BidMeaning? merged;
  for (final rule in rules.where((r) => r.action == call)) {
    merged = merged == null ? rule.meaning : merged.mergedWith(rule.meaning);
  }
  return merged;
}

class SaycCallExplanation {
  final BidAction action;
  final BidMeaning? meaning; // null: no defined meaning / not ported

  SaycCallExplanation(this.action, this.meaning);
}

class SaycAuctionExplanation {
  final List<SaycCallExplanation> calls;

  /// Seat index from the dealer (0-3) -> accumulated constraints.
  final Map<int, BidMeaning> players;

  SaycAuctionExplanation(this.calls, this.players);
}

/// Interpret every call in an auction and accumulate per-seat constraints.
SaycAuctionExplanation explainSaycAuction(List<BidAction> history) {
  final explained = <SaycCallExplanation>[];
  for (int i = 0; i < history.length; i++) {
    BidMeaning? meaning;
    try {
      meaning = describeSaycCall(history.sublist(0, i), history[i]);
    } on StateError {
      meaning = null;
    }
    explained.add(SaycCallExplanation(history[i], meaning));
  }
  final players = <int, BidMeaning>{};
  for (int i = 0; i < explained.length; i++) {
    final meaning = explained[i].meaning;
    if (meaning == null) continue;
    final seat = i % 4;
    players[seat] = players.containsKey(seat)
        ? players[seat]!.intersectedWith(meaning)
        : meaning;
  }
  return SaycAuctionExplanation(explained, players);
}
