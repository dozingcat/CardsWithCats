/// A double-dummy solver for bridge: given all four hands, the trump suit,
/// and the player on lead, computes the number of remaining tricks that
/// North-South win with optimal play by both sides.
///
/// Representation: each hand is four 13-bit rank masks (bit 0 = two,
/// bit 12 = ace), one per suit. Alpha-beta over the number of NS tricks
/// with a transposition table at trick boundaries and equivalence-class
/// move reduction (adjacent ranks whose gaps have all been played are
/// interchangeable).
library;

import '../cards/card.dart';

const int _numPlayers = 4;

/// Mutable solver state. Create one per position via [DDSolver.fromHands]
/// and call [solve]; not reentrant.
class DDSolver {
  // holdings[player * 4 + suit] = rank bitmask.
  final List<int> holdings;
  final int trump; // 0-3 suit index, or -1 for notrump
  int leader;
  final List<int> trickSuits = List.filled(4, 0);
  final List<int> trickRanks = List.filled(4, 0);
  int trickCount = 0;
  final Map<int, int> _transposition = {};

  // Debug toggles for isolating search bugs; see scripts/dd_debug.dart.
  bool debugSimpleMovegen = false;
  bool debugDisableTT = false;
  bool debugNoLastSeatReduction = false;
  bool debugNoEquivalenceClasses = false;
  bool debugClearTTBetweenPasses = false;

  DDSolver._(this.holdings, this.trump, this.leader);

  static DDSolver fromHands(
      List<List<PlayingCard>> hands, Suit? trumpSuit, int leader) {
    final holdings = List.filled(16, 0);
    for (int p = 0; p < _numPlayers; p++) {
      for (final c in hands[p]) {
        holdings[p * 4 + c.suit.index] |= 1 << c.rank.index;
      }
    }
    return DDSolver._(
        holdings, trumpSuit == null ? -1 : trumpSuit.index, leader);
  }

  /// Adds a card already played to the current (partial) trick, in play
  /// order starting with the leader.
  void addTrickCard(PlayingCard c) {
    trickSuits[trickCount] = c.suit.index;
    trickRanks[trickCount] = c.rank.index;
    trickCount++;
  }

  int _cardsPerHand() {
    int total = 0;
    for (final h in holdings) {
      total += _popCount(h);
    }
    // Players who already played to the current trick have one fewer card.
    return (total + trickCount) ~/ 4;
  }

  /// Tricks won by North-South (players 0 and 2) from here with optimal
  /// play, including the trick currently in progress.
  ///
  /// Uses zero-window searches with a binary search over the trick target;
  /// each pass is far cheaper than one full-window search and the bounds
  /// accumulate in the transposition table.
  int solve() {
    final remainingTricks = _cardsPerHand();
    if (remainingTricks == 0) return 0;
    int lo = 0, hi = remainingTricks;
    while (lo < hi) {
      if (debugClearTTBetweenPasses) _transposition.clear();
      final target = (lo + hi + 1) ~/ 2;
      // Window (target-1, target): result >= target means NS make it.
      final value = _search(target - 1, target);
      if (value >= target) {
        lo = target;
      } else {
        hi = target - 1;
      }
    }
    return lo;
  }

  /// Alpha-beta: returns NS tricks in [0, tricksLeft]. `alpha`/`beta`
  /// bound NS tricks from this point on.
  int _search(int alpha, int beta) {
    final player = (leader + trickCount) % _numPlayers;
    final nsToMove = player % 2 == 0;

    if (trickCount == 0) {
      final tricksLeft = _cardsPerHand();
      if (tricksLeft == 0) return 0;
      if (tricksLeft == 1) return _lastTrickWinnerNS() ? 1 : 0;
      // Transposition table over (hands, leader). Alpha-beta results are
      // only bounds when the search fails high or low, so entries store a
      // (lower, upper) pair, plus the best move for ordering, packed into
      // one int.
      final key = _positionHash(player);
      int lower = 0, upper = tricksLeft;
      int ttMove = -1;
      final cached = debugDisableTT ? null : _transposition[key];
      if (cached != null) {
        lower = (cached >> 8) & 0xff;
        upper = cached & 0xff;
        ttMove = (cached >> 16) - 1;
        if (lower == upper) return lower;
        if (lower >= beta) return lower;
        if (upper <= alpha) return upper;
        if (lower > alpha) alpha = lower;
        if (upper < beta) beta = upper;
      }
      final result = _searchMoves(player, nsToMove, alpha, beta, ttMove);
      if (result <= alpha) {
        if (result < upper) upper = result;
      } else if (result >= beta) {
        if (result > lower) lower = result;
      } else {
        lower = result;
        upper = result;
      }
      _transposition[key] =
          ((_bestMoveOut + 1) << 16) | (lower << 8) | upper;
      return result;
    }
    return _searchMoves(player, nsToMove, alpha, beta, -1);
  }

  int _bestMoveOut = -1;

  int _searchMoves(int player, bool nsToMove, int alpha, int beta, int ttMove) {
    final moves = _candidateMoves(player);
    if (ttMove >= 0) {
      final idx = moves.indexOf(ttMove);
      if (idx > 0) {
        moves.removeAt(idx);
        moves.insert(0, ttMove);
      }
    }
    int best = nsToMove ? -1 : 1 << 20;
    int bestMove = moves.isEmpty ? -1 : moves[0];
    for (int i = 0; i < moves.length; i++) {
      final move = moves[i];
      final suit = move >> 4;
      final rank = move & 15;
      final value = _playAndSearch(player, suit, rank, alpha, beta);
      if (nsToMove) {
        if (value > best) {
          best = value;
          bestMove = move;
        }
        if (best > alpha) alpha = best;
      } else {
        if (value < best) {
          best = value;
          bestMove = move;
        }
        if (best < beta) beta = best;
      }
      if (alpha >= beta) break;
    }
    _bestMoveOut = bestMove;
    return best;
  }

  int _playAndSearch(int player, int suit, int rank, int alpha, int beta) {
    holdings[player * 4 + suit] &= ~(1 << rank);
    trickSuits[trickCount] = suit;
    trickRanks[trickCount] = rank;
    trickCount++;

    int value;
    if (trickCount == 4) {
      final winnerOffset = _trickWinnerOffset();
      final winner = (leader + winnerOffset) % _numPlayers;
      final winnerNS = winner % 2 == 0;
      final savedLeader = leader;
      // The child search reuses the trick slots for its own tricks, so
      // they must be restored for sibling moves that will re-read them.
      final s0 = trickSuits[0], s1 = trickSuits[1];
      final s2 = trickSuits[2], s3 = trickSuits[3];
      final r0 = trickRanks[0], r1 = trickRanks[1];
      final r2 = trickRanks[2], r3 = trickRanks[3];
      trickCount = 0;
      leader = winner;
      // Note: a negative child alpha is fine (values are >= 0, so a
      // fail-low simply can't happen). Clamping it to 0 would create a
      // degenerate alpha == beta window in which a single-child cutoff
      // gets misrecorded as a valid bound in the transposition table.
      final childAlpha = winnerNS ? alpha - 1 : alpha;
      final childBeta = winnerNS ? beta - 1 : beta;
      value = (winnerNS ? 1 : 0) + _search(childAlpha, childBeta);
      leader = savedLeader;
      trickCount = 4;
      trickSuits[0] = s0;
      trickSuits[1] = s1;
      trickSuits[2] = s2;
      trickSuits[3] = s3;
      trickRanks[0] = r0;
      trickRanks[1] = r1;
      trickRanks[2] = r2;
      trickRanks[3] = r3;
    } else {
      value = _search(alpha, beta);
    }

    trickCount--;
    holdings[player * 4 + suit] |= 1 << rank;
    return value;
  }

  /// Winner offset within the current (full) trick.
  int _trickWinnerOffset() {
    int best = 0;
    for (int i = 1; i < 4; i++) {
      final bs = trickSuits[best];
      final s = trickSuits[i];
      if (s == bs) {
        if (trickRanks[i] > trickRanks[best]) best = i;
      } else if (trump >= 0 && s == trump) {
        best = i;
      }
    }
    return best;
  }

  bool _lastTrickWinnerNS() {
    // Play out the final trick directly: each player has exactly one card.
    final savedCount = trickCount;
    for (int i = trickCount; i < 4; i++) {
      final p = (leader + i) % _numPlayers;
      for (int s = 0; s < 4; s++) {
        final h = holdings[p * 4 + s];
        if (h != 0) {
          trickSuits[i] = s;
          trickRanks[i] = _lowestBit(h);
          break;
        }
      }
    }
    trickCount = 4;
    final winner = (leader + _trickWinnerOffset()) % _numPlayers;
    trickCount = savedCount;
    return winner % 2 == 0;
  }

  /// Winner offset among the cards played to the trick so far.
  int _partialWinnerOffset() {
    int best = 0;
    for (int i = 1; i < trickCount; i++) {
      final bs = trickSuits[best];
      final s = trickSuits[i];
      if (s == bs) {
        if (trickRanks[i] > trickRanks[best]) best = i;
      } else if (trump >= 0 && s == trump) {
        best = i;
      }
    }
    return best;
  }

  /// Testing hook for [_candidateMoves].
  List<int> debugCandidateMoves(int player) => _candidateMoves(player);

  /// Plays a card without searching (testing hook).
  void debugPlay(int suit, int rank) {
    final player = (leader + trickCount) % _numPlayers;
    holdings[player * 4 + suit] &= ~(1 << rank);
    trickSuits[trickCount] = suit;
    trickRanks[trickCount] = rank;
    trickCount++;
    if (trickCount == 4) {
      final winner = (leader + _trickWinnerOffset()) % _numPlayers;
      trickCount = 0;
      leader = winner;
    }
  }

  /// Legal moves for [player], one per equivalence class, encoded as
  /// (suit << 4) | rank, in a search-friendly order.
  List<int> _candidateMoves(int player) {
    final moves = <int>[];
    if (debugSimpleMovegen) {
      if (trickCount > 0) {
        final ledSuit = trickSuits[0];
        final h = holdings[player * 4 + ledSuit];
        if (h != 0) {
          for (int r = 12; r >= 0; r--) {
            if (h & (1 << r) != 0) moves.add((ledSuit << 4) | r);
          }
          return moves;
        }
      }
      for (int s = 0; s < 4; s++) {
        final h = holdings[player * 4 + s];
        for (int r = 12; r >= 0; r--) {
          if (h & (1 << r) != 0) moves.add((s << 4) | r);
        }
      }
      return moves;
    }
    if (trickCount > 0) {
      final ledSuit = trickSuits[0];
      final winnerOffset = _partialWinnerOffset();
      final winnerSeat = (leader + winnerOffset) % _numPlayers;
      final partnerWinning = winnerSeat % 2 == player % 2;
      final winnerSuit = trickSuits[winnerOffset];
      final winnerRank = trickRanks[winnerOffset];
      final h = holdings[player * 4 + ledSuit];
      if (h != 0) {
        _addSuitMoves(moves, player, ledSuit, h);
        if (moves.length <= 1) return moves;
        // The led-suit card that must be beaten, if beating is possible at
        // all (a ruff elsewhere in the trick can't be beaten by following).
        final needed = winnerSuit == ledSuit ? winnerRank : 99;
        // Find the cheapest class that beats, and the lowest class.
        int cheapestWinner = -1;
        int lowest = moves[0];
        for (final m in moves) {
          final r = m & 15;
          if ((lowest & 15) > r) lowest = m;
          if (r > needed &&
              (cheapestWinner == -1 || (cheapestWinner & 15) > r)) {
            cheapestWinner = m;
          }
        }
        if (!debugNoLastSeatReduction && trickCount == 3) {
          // Last to play: only three plays can matter — win (or overtake
          // partner) as cheaply as possible, duck with the lowest, or
          // unblock by throwing the highest. Higher winners are dominated
          // by the cheapest winner; if the highest card doesn't win, it's
          // the strongest unblock.
          final highest = moves[0];
          final reduced = <int>[];
          if (cheapestWinner >= 0) reduced.add(cheapestWinner);
          reduced.add(lowest);
          if (highest != lowest && !reduced.contains(highest)) {
            reduced.add(highest);
          }
          return reduced;
        }
        // Second/third seat: try the cheapest winning card first, then the
        // lowest, then the rest from the top.
        final ordered = <int>[];
        if (!partnerWinning && cheapestWinner >= 0) {
          ordered.add(cheapestWinner);
        }
        if (!ordered.contains(lowest)) ordered.add(lowest);
        for (final m in moves) {
          if (!ordered.contains(m)) ordered.add(m);
        }
        return ordered;
      }
      // Void in the led suit: ruffs (cheapest winning ruff first when the
      // opponents hold the trick), then discards from low to high.
      final ordered = <int>[];
      if (trump >= 0 && ledSuit != trump) {
        final trumps = holdings[player * 4 + trump];
        if (trumps != 0) {
          final tMoves = <int>[];
          _addSuitMoves(tMoves, player, trump, trumps);
          final needed = winnerSuit == trump ? winnerRank : -1;
          int cheapestRuff = -1;
          for (final m in tMoves) {
            final r = m & 15;
            if (r > needed && (cheapestRuff == -1 || (cheapestRuff & 15) > r)) {
              cheapestRuff = m;
            }
          }
          if (!partnerWinning && cheapestRuff >= 0) ordered.add(cheapestRuff);
          moves.addAll(tMoves);
        }
      }
      for (int s = 0; s < 4; s++) {
        if (trump >= 0 && s == trump) continue;
        final hs = holdings[player * 4 + s];
        if (hs != 0) _addSuitMoves(moves, player, s, hs);
      }
      // Low first for the remainder.
      moves.sort((a, b) => (a & 15).compareTo(b & 15));
      for (final m in moves) {
        if (!ordered.contains(m)) ordered.add(m);
      }
      return ordered;
    }
    // Leading: try suits where we hold the highest remaining card first —
    // cash-out lines give the earliest cutoffs.
    final rest = <int>[];
    for (int s = 0; s < 4; s++) {
      final h = holdings[player * 4 + s];
      if (h == 0) continue;
      int allSuit = 0;
      for (int p = 0; p < _numPlayers; p++) {
        allSuit |= holdings[p * 4 + s];
      }
      final suitMoves = <int>[];
      _addSuitMoves(suitMoves, player, s, h);
      if (_highestBit(h) == _highestBit(allSuit)) {
        moves.add(suitMoves[0]);
        rest.addAll(suitMoves.skip(1));
      } else {
        rest.addAll(suitMoves);
      }
    }
    moves.addAll(rest);
    return moves;
  }

  /// Adds one representative per equivalence class: ranks are equivalent
  /// when no other hand holds a rank strictly between them.
  void _addSuitMoves(List<int> moves, int player, int suit, int hand) {
    if (debugNoEquivalenceClasses) {
      for (int r = 12; r >= 0; r--) {
        if (hand & (1 << r) != 0) moves.add((suit << 4) | r);
      }
      return;
    }
    int others = 0;
    for (int p = 0; p < _numPlayers; p++) {
      if (p != player) others |= holdings[p * 4 + suit];
    }
    // Also cards currently on the table block equivalence.
    for (int i = 0; i < trickCount; i++) {
      if (trickSuits[i] == suit) others |= 1 << trickRanks[i];
    }
    // Walk from the top; start a new class when a gap contains an
    // opponent-held rank. Emit the *highest* card of each class first
    // (helps cutoffs: winning moves early), but play the lowest member so
    // equal classes cost the cheapest card. Since class members are
    // interchangeable, use the lowest rank of each class.
    int remaining = hand;
    while (remaining != 0) {
      final top = _highestBit(remaining);
      int low = top;
      // Extend downward while the next lower held rank has no opposing
      // rank in between.
      while (low > 0) {
        int gapMask = 0;
        int r = low - 1;
        bool extended = false;
        while (r >= 0) {
          final bit = 1 << r;
          if (hand & bit != 0) {
            if (others & gapMask == 0) {
              low = r;
              extended = true;
            }
            break;
          }
          gapMask |= bit;
          r--;
        }
        if (!extended) break;
      }
      moves.add((suit << 4) | low);
      // Clear all bits from `low` up to `top`.
      final classMask = ((1 << (top + 1)) - 1) & ~((1 << low) - 1);
      remaining &= ~classMask;
    }
  }

  int _positionHash(int leaderPlayer) {
    // FNV-style hash over the holdings and leader. Collisions are
    // possible in principle; the 64-bit space makes them negligible for
    // per-position tables that live for a single solve.
    int h = 0xcbf29ce484222325;
    for (final m in holdings) {
      h ^= m;
      h *= 0x100000001b3;
      h &= 0x7fffffffffffffff;
    }
    h ^= leaderPlayer;
    h *= 0x100000001b3;
    return h & 0x7fffffffffffffff;
  }
}

/// Reference implementation: plain minimax over every legal card, no
/// transposition table, no equivalence classes, no move reductions. Far too
/// slow for real use; exists to validate [DDSolver] in tests.
class DDReferenceSolver {
  final List<int> holdings;
  final int trump;
  int leader;
  final List<int> trickSuits = List.filled(4, 0);
  final List<int> trickRanks = List.filled(4, 0);
  int trickCount = 0;

  DDReferenceSolver._(this.holdings, this.trump, this.leader);

  static DDReferenceSolver fromHands(
      List<List<PlayingCard>> hands, Suit? trumpSuit, int leader) {
    final holdings = List.filled(16, 0);
    for (int p = 0; p < _numPlayers; p++) {
      for (final c in hands[p]) {
        holdings[p * 4 + c.suit.index] |= 1 << c.rank.index;
      }
    }
    return DDReferenceSolver._(
        holdings, trumpSuit == null ? -1 : trumpSuit.index, leader);
  }

  int solve() {
    int total = 0;
    for (final h in holdings) {
      total += _popCount(h);
    }
    if ((total + trickCount) == 0) return 0;
    return _search();
  }

  int _search() {
    final player = (leader + trickCount) % _numPlayers;
    int cards = 0;
    for (int s = 0; s < 4; s++) {
      cards += _popCount(holdings[player * 4 + s]);
    }
    if (cards == 0) return 0;

    final moves = <int>[];
    if (trickCount > 0) {
      final ledSuit = trickSuits[0];
      final h = holdings[player * 4 + ledSuit];
      if (h != 0) {
        for (int r = 0; r < 13; r++) {
          if (h & (1 << r) != 0) moves.add((ledSuit << 4) | r);
        }
      }
    }
    if (moves.isEmpty) {
      for (int s = 0; s < 4; s++) {
        final h = holdings[player * 4 + s];
        for (int r = 0; r < 13; r++) {
          if (h & (1 << r) != 0) moves.add((s << 4) | r);
        }
      }
    }

    final nsToMove = player % 2 == 0;
    int best = nsToMove ? -1 : 1 << 20;
    for (final move in moves) {
      final suit = move >> 4;
      final rank = move & 15;
      holdings[player * 4 + suit] &= ~(1 << rank);
      trickSuits[trickCount] = suit;
      trickRanks[trickCount] = rank;
      trickCount++;
      int value;
      if (trickCount == 4) {
        int w = 0;
        for (int i = 1; i < 4; i++) {
          final bs = trickSuits[w];
          final s = trickSuits[i];
          if (s == bs) {
            if (trickRanks[i] > trickRanks[w]) w = i;
          } else if (trump >= 0 && s == trump) {
            w = i;
          }
        }
        final winner = (leader + w) % _numPlayers;
        final savedLeader = leader;
        // Child tricks reuse the slots; restore them for later siblings.
        final s0 = trickSuits[0], s1 = trickSuits[1];
        final s2 = trickSuits[2], s3 = trickSuits[3];
        final r0 = trickRanks[0], r1 = trickRanks[1];
        final r2 = trickRanks[2], r3 = trickRanks[3];
        trickCount = 0;
        leader = winner;
        value = (winner % 2 == 0 ? 1 : 0) + _search();
        leader = savedLeader;
        trickCount = 4;
        trickSuits[0] = s0;
        trickSuits[1] = s1;
        trickSuits[2] = s2;
        trickSuits[3] = s3;
        trickRanks[0] = r0;
        trickRanks[1] = r1;
        trickRanks[2] = r2;
        trickRanks[3] = r3;
      } else {
        value = _search();
      }
      trickCount--;
      holdings[player * 4 + suit] |= 1 << rank;
      if (nsToMove) {
        if (value > best) best = value;
      } else {
        if (value < best) best = value;
      }
    }
    return best;
  }
}

int _popCount(int x) {
  int count = 0;
  while (x != 0) {
    x &= x - 1;
    count++;
  }
  return count;
}

int _highestBit(int x) {
  int b = 0;
  while (x > 1) {
    x >>= 1;
    b++;
  }
  return b;
}

int _lowestBit(int x) {
  int b = 0;
  while (x & 1 == 0) {
    x >>= 1;
    b++;
  }
  return b;
}
