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
// Auction dispatch and public API
// ---------------------------------------------------------------------------

/// The ordered candidate rules for the next call in this auction, or null if
/// the position has not been ported yet (callers should fall back to the
/// legacy engine). Throws [StateError] if the auction is already over.
List<SaycRule>? saycRulesForAuction(List<BidAction> calls) {
  if (calls.length >= 4 &&
      calls
          .sublist(calls.length - 3)
          .every((c) => c.bidType == BidType.pass)) {
    throw StateError("The auction is already over");
  }
  if (calls.every((c) => c.bidType == BidType.pass)) {
    return openingRules();
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
