/// Dart FFI binding to the dds-bridge/dds double-dummy solver (v2.9.0),
/// used as an optional fast backend for MCDD's exact evaluations. Build
/// the library with cpp/build_libdds.sh; it is loaded
/// from the platform default location when present (macOS: bundled in
/// Contents/Frameworks by a Runner build phase; Android: libdds.so from
/// jniLibs; Linux: libdds.so from the bundle's lib/ directory, built by
/// linux/CMakeLists.txt), and the DDS_LIB environment variable overrides
/// the path for
/// development. When no library can be loaded, callers fall back to the
/// pure-Dart DDSolver. Each isolate loads independently.
///
/// Threading: DDS is thread-safe only when concurrent calls use distinct
/// thread indices, and its memory must be initialized exactly once per
/// process. Both are handled by a shim compiled into our libdds build
/// (cpp/dds_shim.cpp): once-only init via std::call_once
/// and exclusive acquire/release thread-index slots. Every solve
/// brackets its SolveBoard call with acquire/release (safe: the native
/// call is synchronous, so an isolate can't abandon a held slot); if all
/// slots are busy, solve() returns null and the caller falls back to the
/// pure-Dart solver.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

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
typedef _ReleaseC = Void Function(Int32);
typedef _ReleaseDart = void Function(int);
typedef _SolveBoardC = Int32 Function(
    _DdsDeal, Int32, Int32, Int32, Pointer<_DdsFutureTricks>, Int32);
typedef _SolveBoardDart = int Function(
    _DdsDeal, int, int, int, Pointer<_DdsFutureTricks>, int);

// compute() spawns a fresh isolate per call and statics are per-isolate, so
// every worker re-runs the load below. That is cheap — isolates share the
// process, so dlopen just refcounts an already-mapped library and the shim's
// DdsEnsureInit is std::call_once — but it would repeat the status message
// once per AI card play, so only the root isolate logs.
bool get _isRootIsolate => Isolate.current.debugName == "main";

int _ddsSuit(Suit s) => 3 - s.index;
int _ddsRank(Rank r) => r.index + 2;

class DdsBackend {
  final _SolveBoardDart _solveBoard;
  final _IntDart _acquireThreadIndex;
  final _ReleaseDart _releaseThreadIndex;
  int nodesSearched = 0;

  DdsBackend._(this._solveBoard, this._acquireThreadIndex,
      this._releaseThreadIndex);

  static DdsBackend? _instance;
  static bool _loadAttempted = false;

  /// The process-wide backend, or null when unavailable. Loads lazily on
  /// first use: the DDS_LIB environment variable if set, otherwise the
  /// platform's default bundled location.
  static DdsBackend? get instance {
    if (!_loadAttempted) {
      _loadAttempted = true;
      final envPath = Platform.environment["DDS_LIB"];
      if (envPath != null && envPath.isNotEmpty) {
        _instance = _tryLoad(envPath, verbose: true);
      } else if (Platform.isAndroid) {
        // The loader resolves bare names against the app's jniLibs.
        _instance = _tryLoad("libdds.so", verbose: false);
      } else if (Platform.isMacOS) {
        final path = "${File(Platform.resolvedExecutable).parent.path}"
            "/../Frameworks/libdds.dylib";
        if (File(path).existsSync()) {
          _instance = _tryLoad(path, verbose: false);
        }
      } else if (Platform.isLinux) {
        final path = "${File(Platform.resolvedExecutable).parent.path}"
            "/lib/libdds.so";
        if (File(path).existsSync()) {
          _instance = _tryLoad(path, verbose: false);
        }
      }
    }
    return _instance;
  }

  static DdsBackend? _tryLoad(String path, {required bool verbose}) {
    try {
      final lib = DynamicLibrary.open(path);
      if (_isRootIsolate) {
        print("DDS backend loaded from $path");
      }
      // These come from dds_shim.cpp in our libdds build: process-wide
      // once-only initialization and exclusive thread-index slots (see
      // the threading note above).
      final ensureInit = lib.lookupFunction<_VoidC, _VoidDart>("DdsEnsureInit");
      final acquire =
          lib.lookupFunction<_IntC, _IntDart>("DdsAcquireThreadIndex");
      final release = lib
          .lookupFunction<_ReleaseC, _ReleaseDart>("DdsReleaseThreadIndex");
      final solveBoard =
          lib.lookupFunction<_SolveBoardC, _SolveBoardDart>("SolveBoard");
      ensureInit();
      return DdsBackend._(solveBoard, acquire, release);
    } catch (e) {
      if (verbose && _isRootIsolate) {
        // DDS_LIB was set explicitly, so a failure is worth reporting.
        // Common causes: a relative path (the app's working directory is
        // not the repo — use an absolute path) and the macOS app sandbox
        // blocking dlopen outside the bundle in sandboxed builds.
        print("DDS backend failed to load from $path: $e");
      }
      return null;
    }
  }

  /// DDS has room for only three cards in the trick in progress; a complete
  /// trick has to be resolved by the caller before solving.
  static void _checkTrickCards(List<PlayingCard> trickCards) {
    if (trickCards.length > 3) {
      throw ArgumentError(
          "Trick in progress can have at most 3 cards, got ${trickCards.length}");
    }
  }

  /// Fills [deal] with this position, returning the total
  /// number of cards still in play (hands plus the trick in progress).
  int _fillDeal(_DdsDeal deal, List<List<PlayingCard>> hands, Suit? trump,
      int leader, List<PlayingCard> trickCards) {
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
    return totalCards;
  }

  /// North-South tricks from this position with optimal play, including
  /// the trick in progress — the same contract as [DDSolver.solve].
  /// Returns null on a DDS error.
  int? solve(List<List<PlayingCard>> hands, Suit? trump, int leader,
      List<PlayingCard> trickCards) {
    _checkTrickCards(trickCards);
    final deal = calloc<_DdsDeal>();
    final fut = calloc<_DdsFutureTricks>();
    try {
      final totalCards = _fillDeal(deal.ref, hands, trump, leader, trickCards);
      final threadIndex = _acquireThreadIndex();
      if (threadIndex < 0) {
        return null; // all DDS slots busy; caller falls back
      }
      final int res;
      try {
        // solutions=1: only the best card's score is needed.
        res = _solveBoard(deal.ref, -1, 1, 1, fut, threadIndex);
      } finally {
        _releaseThreadIndex(threadIndex);
      }
      if (res != 1) {
        return null;
      }
      nodesSearched += fut.ref.nodes;
      final score = fut.ref.score[0];
      final mover = (leader + trickCards.length) % 4;
      final remainingTricks = totalCards ~/ 4;
      return mover % 2 == 0 ? score : remainingTricks - score;
    } finally {
      // SolveBoard takes the deal by value and only writes into `fut` for
      // the duration of the call, so neither buffer outlives this scope.
      calloc.free(deal);
      calloc.free(fut);
    }
  }

  /// Tricks taken by the side on play for each card that player can legally
  /// play, with optimal play by both sides afterwards. As with [solve] the
  /// count includes the trick in progress, so a card that wins the current
  /// trick is credited for it.
  ///
  /// One SolveBoard call evaluates every candidate, which is much cheaper
  /// than a [solve] per card. Note that the scores are from the perspective
  /// of the player on play, not of North-South as in [solve].
  ///
  /// [trickCards] holds at most three cards; with three, the player on play
  /// is the one completing the trick.
  ///
  /// Returns null on a DDS error or when all solver slots are busy.
  Map<PlayingCard, int>? solveAllCards(List<List<PlayingCard>> hands,
      Suit? trump, int leader, List<PlayingCard> trickCards) {
    _checkTrickCards(trickCards);
    final dealPtr = calloc<_DdsDeal>();
    final futPtr = calloc<_DdsFutureTricks>();
    try {
      _fillDeal(dealPtr.ref, hands, trump, leader, trickCards);
      final threadIndex = _acquireThreadIndex();
      if (threadIndex < 0) {
        return null; // all DDS slots busy; caller falls back
      }
      final int res;
      try {
        // solutions=3 scores every legal card rather than just the best one.
        // mode=1 searches even when only one card is playable, so that every
        // returned score is a real trick count rather than a -1 placeholder.
        res = _solveBoard(dealPtr.ref, -1, 3, 1, futPtr, threadIndex);
      } finally {
        _releaseThreadIndex(threadIndex);
      }
      if (res != 1) {
        return null;
      }
      final fut = futPtr.ref;
      nodesSearched += fut.nodes;
      if (fut.cards <= 0) {
        return null;
      }
      final result = <PlayingCard, int>{};
      for (int i = 0; i < fut.cards; i++) {
        final score = fut.score[i];
        if (score < 0) {
          return null; // DDS declined to score this card.
        }
        final suit = Suit.values[3 - fut.suit[i]];
        result[PlayingCard(Rank.values[fut.rank[i] - 2], suit)] = score;
        // DDS returns one entry per equivalence class; `equals` is a bit map
        // of the lower ranks in the same suit that play identically, with
        // bit 2 for the two through bit 14 for the ace.
        final equalRanks = fut.equals[i];
        for (int r = 2; r <= 14; r++) {
          if (equalRanks & (1 << r) != 0) {
            result[PlayingCard(Rank.values[r - 2], suit)] = score;
          }
        }
      }
      return result;
    } finally {
      calloc.free(dealPtr);
      calloc.free(futPtr);
    }
  }
}
