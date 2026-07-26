/// Integer ranges with optional bounds, used by the SAYC bidding engine to
/// express what a call shows (point counts and suit lengths).
library;

import 'dart:math';

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
