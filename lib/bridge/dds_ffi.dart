/// Dart FFI binding to the dds-bridge/dds double-dummy solver (v2.9.0),
/// used as an optional fast backend for MCDD's exact evaluations. Build
/// the library with scripts/dds_compare/build_libdds.sh; it is loaded
/// from the platform default location when present (macOS: bundled in
/// Contents/Frameworks by a Runner build phase; Android: libdds.so from
/// jniLibs), and the DDS_LIB environment variable overrides the path for
/// development. When no library can be loaded, callers fall back to the
/// pure-Dart DDSolver. Each isolate loads independently.
///
/// Threading: DDS is thread-safe only when concurrent calls use distinct
/// thread indices, and its memory must be initialized exactly once per
/// process. Both are handled by a shim compiled into our libdds build
/// (scripts/dds_compare/dds_shim.cpp): once-only init via std::call_once
/// and exclusive acquire/release thread-index slots. Every solve
/// brackets its SolveBoard call with acquire/release (safe: the native
/// call is synchronous, so an isolate can't abandon a held slot); if all
/// slots are busy, solve() returns null and the caller falls back to the
/// pure-Dart solver.
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
typedef _ReleaseC = Void Function(Int32);
typedef _ReleaseDart = void Function(int);
typedef _SolveBoardC = Int32 Function(
    _DdsDeal, Int32, Int32, Int32, Pointer<_DdsFutureTricks>, Int32);
typedef _SolveBoardDart = int Function(
    _DdsDeal, int, int, int, Pointer<_DdsFutureTricks>, int);

int _ddsSuit(Suit s) => 3 - s.index;
int _ddsRank(Rank r) => r.index + 2;

class DdsBackend {
  final _SolveBoardDart _solveBoard;
  final _IntDart _acquireThreadIndex;
  final _ReleaseDart _releaseThreadIndex;
  final Pointer<_DdsDeal> _deal;
  final Pointer<_DdsFutureTricks> _fut;
  int nodesSearched = 0;

  DdsBackend._(this._solveBoard, this._acquireThreadIndex,
      this._releaseThreadIndex, this._deal, this._fut);

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
      }
    }
    return _instance;
  }

  static DdsBackend? _tryLoad(String path, {required bool verbose}) {
    try {
      final lib = DynamicLibrary.open(path);
      print("DDS backend loaded from $path");
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
      return DdsBackend._(
        solveBoard,
        acquire,
        release,
        calloc<_DdsDeal>(),
        calloc<_DdsFutureTricks>(),
      );
    } catch (e) {
      if (verbose) {
        // DDS_LIB was set explicitly, so a failure is worth reporting.
        // Common causes: a relative path (the app's working directory is
        // not the repo — use an absolute path) and the macOS app sandbox
        // blocking dlopen outside the bundle in sandboxed builds.
        print("DDS backend failed to load from $path: $e");
      }
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
    final threadIndex = _acquireThreadIndex();
    if (threadIndex < 0) {
      return null; // all DDS slots busy; caller falls back
    }
    final int res;
    try {
      res = _solveBoard(deal, -1, 1, 1, _fut, threadIndex);
    } finally {
      _releaseThreadIndex(threadIndex);
    }
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
