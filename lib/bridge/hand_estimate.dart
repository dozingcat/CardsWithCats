import 'dart:math';

import 'package:cards_with_cats/bridge/utils.dart';

import '../cards/card.dart';

class Range {
  final int? low;
  final int? high;

  const Range({this.low, this.high});

  @override
  String toString() {
    return "Range(low: $low, high: $high)";
  }

  String shortString() {
    if (low == null && high == null) {
      return "any";
    }
    if (low == null) {
      return "<=$high";
    }
    if (high == null) {
      return ">=$low";
    }
    return "$low-$high";
  }

  @override
  bool operator ==(Object other) {
    return other is Range && low == other.low && high == other.high;
  }

  @override
  int get hashCode => Object.hash(low, high);

  bool contains(int value) {
    return (low == null || value >= low!) && (high == null || value <= high!);
  }

  Range combine(Range? other) {
    if (other == null) {
      return this;
    }
    return Range(
      low: low == null
          ? other.low
          : other.low == null
              ? low
              : max(low!, other.low!),
      high: high == null
          ? other.high
          : other.high == null
              ? high
              : min(high!, other.high!),
    );
  }

  bool isDisjointWith(Range other) {
    return (high != null && other.low != null && high! < other.low!) ||
        (low != null && other.high != null && low! > other.high!);
  }

  Range combineOrReplace(Range? other) {
    if (other != null && isDisjointWith(other)) {
      return other;
    }
    return combine(other);
  }

  Range plusConstant(int n) {
    // Assumes nonnegative values.
    return Range(
      low: (low == null ? n : n + low!),
      high: (high == null) ? null : high! + n,
    );
  }
}

Map<Suit, Range> _addMissingSuitRanges(Map<Suit, Range>? suitLengths) {
  Map<Suit, Range> allSuitLengths = {};
  for (final suit in Suit.values) {
    allSuitLengths[suit] = suitLengths?[suit] ?? const Range();
  }
  return allSuitLengths;
}

enum HandPointBonusType {
  none,
  suitLength,
}

class HandEstimate {
  final Range pointRange;
  final Map<Suit, Range> suitLengthRanges;
  final HandPointBonusType pointBonusType;

  HandEstimate(
      {required this.pointRange,
      required this.suitLengthRanges,
      required this.pointBonusType});

  static HandEstimate create(
      {pointRange = const Range(),
      Map<Suit, Range>? suitLengthRanges,
      HandPointBonusType pointBonusType = HandPointBonusType.none}) {
    return HandEstimate(
      pointRange: pointRange,
      suitLengthRanges: _addMissingSuitRanges(suitLengthRanges),
      pointBonusType: pointBonusType,
    );
  }

  @override
  String toString() {
    final s = suitLengthRanges;
    return "Points: ${pointRange.shortString()} S:${s[Suit.spades]!.shortString()} H:${s[Suit.hearts]!.shortString()} D:${s[Suit.diamonds]!.shortString()} C:${s[Suit.clubs]!.shortString()}";
  }

  bool matches(List<PlayingCard> hand, Map<Suit, int> suitCounts) {
    int points = highCardPoints(hand);
    if (pointBonusType == HandPointBonusType.suitLength) {
      points += lengthPointsForSuitCounts(suitCounts);
    }
    // print("Checking points: $pointRange $points");
    if (!pointRange.contains(points)) {
      // print("Failed point range");
      return false;
    }
    for (final suit in Suit.values) {
      // print("Checking suit: $suit ${suitLengthRanges[suit]} ${suitCounts[suit]}");
      if (!suitLengthRanges[suit]!.contains(suitCounts[suit]!)) {
        // print("Failed suit length");
        return false;
      }
    }
    return true;
  }

  HandEstimate combineOrReplace(HandEstimate other) {
    final combinedPoints = pointRange.combineOrReplace(other.pointRange);
    final combinedSuits = {
      Suit.clubs: suitLengthRanges[Suit.clubs]!
          .combineOrReplace(other.suitLengthRanges[Suit.clubs]),
      Suit.diamonds: suitLengthRanges[Suit.diamonds]!
          .combineOrReplace(other.suitLengthRanges[Suit.diamonds]),
      Suit.hearts: suitLengthRanges[Suit.hearts]!
          .combineOrReplace(other.suitLengthRanges[Suit.hearts]),
      Suit.spades: suitLengthRanges[Suit.spades]!
          .combineOrReplace(other.suitLengthRanges[Suit.spades]),
    };
    return HandEstimate.create(
      pointRange: combinedPoints,
      suitLengthRanges: combinedSuits,
    );
  }
}
