/// Scoring helpers for evaluating auctions against double-dummy results:
/// the final contract of an auction, non-vulnerable duplicate scores, and
/// double-dummy par. Trick tables come from a solver (see dds_ffi.dart);
/// nothing here calls one.
library;

import '../cards/card.dart';
import 'bridge.dart';

/// Every contract bid, lowest first.
final allContractBids = [
  for (int level = 1; level <= 7; level++)
    for (final trump in [...Suit.values, null]) ContractBid(level, trump)
];

/// The final contract of an auction: the bid, who declares it (the first
/// player of the declaring side to name the strain), and whether it was
/// doubled or redoubled.
class FinalContract {
  final ContractBid bid;
  final int declarer;
  final DoubledType doubled;

  /// Index in the auction of the final contract bid.
  final int index;

  FinalContract(this.bid, this.declarer, this.doubled, this.index);

  int get side => declarer % 2;

  /// Null when the auction was passed out. Seats are auction positions mod
  /// 4 (the dealer is seat 0).
  static FinalContract? of(List<BidAction> history) {
    int? last;
    for (int j = history.length - 1; j >= 0; j--) {
      if (history[j].bidType == BidType.contract) {
        last = j;
        break;
      }
    }
    if (last == null) return null;
    final bid = history[last].contractBid!;
    int declarer = last % 4;
    for (int j = last % 2; j <= last; j += 2) {
      if (history[j].bidType == BidType.contract &&
          history[j].contractBid!.trump == bid.trump) {
        declarer = j % 4;
        break;
      }
    }
    final after = history.sublist(last + 1);
    final doubled = after.any((c) => c.bidType == BidType.redouble)
        ? DoubledType.redoubled
        : after.any((c) => c.bidType == BidType.double)
            ? DoubledType.doubled
            : DoubledType.none;
    return FinalContract(bid, declarer, doubled, last);
  }
}

/// Non-vulnerable duplicate score for the declaring side of [bid] taking
/// [tricks].
int nonVulnerableScore(ContractBid bid, int tricks,
        {DoubledType doubled = DoubledType.none}) =>
    Contract(bid: bid, isVulnerable: false, declarer: 0, doubled: doubled)
        .scoreForTricksTaken(tricks);

/// The best score a side can make undoubled, given its best tricks per
/// strain (0 if it can't make anything).
int bestMakingScore(Map<Suit?, int> sideTricks) {
  int best = 0;
  for (final b in allContractBids) {
    final t = sideTricks[b.trump]!;
    if (t >= b.numTricksRequired) {
      final s = nonVulnerableScore(b, t);
      if (s > best) best = s;
    }
  }
  return best;
}

/// Double-dummy par for North-South (non-vulnerable), from each side's best
/// tricks per strain ([sideTricks] indexed by side: 0 for N-S, 1 for E-W).
/// The sides take turns outbidding, with a making contract or a doubled
/// sacrifice that costs less than defending, until neither improves; the
/// side with the better makeable contract bids first.
int parScoreNs(List<Map<Suit?, int>> sideTricks) {
  int result(int side, ContractBid bid) {
    final t = sideTricks[side][bid.trump]!;
    return t >= bid.numTricksRequired
        ? nonVulnerableScore(bid, t)
        : nonVulnerableScore(bid, t, doubled: DoubledType.doubled);
  }

  ContractBid? current;
  int owner = -1;
  int side = bestMakingScore(sideTricks[0]) >= bestMakingScore(sideTricks[1])
      ? 0
      : 1;
  int passes = 0;
  while (passes < 2) {
    final defend = current == null
        ? 0
        : (owner == side ? result(owner, current) : -result(owner, current));
    ContractBid? best;
    int bestScore = defend;
    for (final b in allContractBids) {
      if (current != null && !b.isHigherThan(current)) continue;
      final r = result(side, b);
      if (r > bestScore) {
        best = b;
        bestScore = r;
      }
    }
    if (best != null && owner != side) {
      current = best;
      owner = side;
      passes = 0;
    } else {
      passes++;
    }
    side = 1 - side;
  }
  if (current == null) return 0;
  final score = result(owner, current);
  return owner == 0 ? score : -score;
}
