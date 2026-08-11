/// Dart FFI binding to the dds-bridge/dds double-dummy solver (v2.9.0),
/// used as an optional fast backend for MCDD's exact evaluations. Build
/// the library with scripts/dds_compare/build_libdds.sh and opt in by
/// setting the DDS_LIB environment variable to its path (each isolate
/// loads it independently; loading is a no-op when the variable is unset
/// or the library is missing, and callers fall back to the pure-Dart
/// DDSolver).
///
/// Threading: DDS is thread-safe only when concurrent calls use distinct
/// thread indices, and its memory must be initialized exactly once per
/// process. Both are handled by a shim compiled into our libdds build
/// (scripts/dds_compare/dds_shim.cpp): once-only init via std::call_once
/// and a round-robin atomic thread-index dispenser. Safe for up to 16
/// concurrently solving isolates; beyond that, indices can collide.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../cards/card.dart';

// DDS conventions: hands 0=N 1=E 2=S 3=W; suits 0=S 1=H 2=D 3=C;
// trump 0..3 as suits, 4 = notrump; ranks 2..14; card masks bits 2..14.

final class _DdsDeal extends Struct {
  @Int32()
  external int trump;
  @Int32()
  external int first;
  @Array(3)
  external Array<Int32> currentTrickSuit;
  @Array(3)
  external Array<Int32> currentTrickRank;
  @Array(4, 4)
  external Array<Array<Uint32>> remainCards;
}

final class _DdsFutureTricks extends Struct {
  @Int32()
  external int nodes;
  @Int32()
  external int cards;
  @Array(13)
  external Array<Int32> suit;
  @Array(13)
  external Array<Int32> rank;
  @Array(13)
  external Array<Int32> equals;
  @Array(13)
  external Array<Int32> score;
}

typedef _VoidC = Void Function();
typedef _VoidDart = void Function();
typedef _IntC = Int32 Function();
typedef _IntDart = int Function();
typedef _SolveBoardC = Int32 Function(
    _DdsDeal, Int32, Int32, Int32, Pointer<_DdsFutureTricks>, Int32);
typedef _SolveBoardDart = int Function(
    _DdsDeal, int, int, int, Pointer<_DdsFutureTricks>, int);

int _ddsSuit(Suit s) => 3 - s.index;
int _ddsRank(Rank r) => r.index + 2;

class DdsBackend {
  final _SolveBoardDart _solveBoard;
  final Pointer<_DdsDeal> _deal;
  final Pointer<_DdsFutureTricks> _fut;
  final int _threadIndex;
  int nodesSearched = 0;

  DdsBackend._(this._solveBoard, this._deal, this._fut, this._threadIndex);

  static DdsBackend? _instance;
  static bool _loadAttempted = false;

  /// The process-wide backend, or null when unavailable. Loads lazily
  /// from the DDS_LIB environment variable on first use.
  static DdsBackend? get instance {
    if (!_loadAttempted) {
      _loadAttempted = true;
      final path = Platform.environment["DDS_LIB"];
      if (path != null && path.isNotEmpty) {
        _instance = _tryLoad(path);
      }
    }
    return _instance;
  }

  static DdsBackend? _tryLoad(String path) {
    try {
      final lib = DynamicLibrary.open(path);
      // These come from dds_shim.cpp in our libdds build: process-wide
      // once-only initialization and a round-robin thread index, so
      // multiple isolates can use the library safely (see the threading
      // note above).
      final ensureInit = lib.lookupFunction<_VoidC, _VoidDart>("DdsEnsureInit");
      final nextThreadIndex =
          lib.lookupFunction<_IntC, _IntDart>("DdsNextThreadIndex");
      final solveBoard =
          lib.lookupFunction<_SolveBoardC, _SolveBoardDart>("SolveBoard");
      ensureInit();
      return DdsBackend._(
        solveBoard,
        calloc<_DdsDeal>(),
        calloc<_DdsFutureTricks>(),
        nextThreadIndex(),
      );
    } catch (e) {
      return null;
    }
  }

  /// North-South tricks from this position with optimal play, including
  /// the trick in progress — the same contract as [DDSolver.solve].
  /// Returns null on a DDS error.
  int? solve(List<List<PlayingCard>> hands, Suit? trump, int leader,
      List<PlayingCard> trickCards) {
    final deal = _deal.ref;
    deal.trump = trump == null ? 4 : _ddsSuit(trump);
    deal.first = leader;
    for (int i = 0; i < 3; i++) {
      deal.currentTrickSuit[i] = 0;
      deal.currentTrickRank[i] = 0;
    }
    for (int i = 0; i < trickCards.length; i++) {
      deal.currentTrickSuit[i] = _ddsSuit(trickCards[i].suit);
      deal.currentTrickRank[i] = _ddsRank(trickCards[i].rank);
    }
    int totalCards = trickCards.length;
    for (int h = 0; h < 4; h++) {
      for (int s = 0; s < 4; s++) {
        deal.remainCards[h][s] = 0;
      }
      for (final c in hands[h]) {
        deal.remainCards[h][_ddsSuit(c.suit)] |= 1 << _ddsRank(c.rank);
        totalCards++;
      }
    }
    final res = _solveBoard(deal, -1, 1, 1, _fut, _threadIndex);
    if (res != 1) {
      return null;
    }
    nodesSearched += _fut.ref.nodes;
    final score = _fut.ref.score[0];
    final mover = (leader + trickCards.length) % 4;
    final remainingTricks = totalCards ~/ 4;
    return mover % 2 == 0 ? score : remainingTricks - score;
  }
}
