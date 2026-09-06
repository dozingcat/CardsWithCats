// Small shim compiled into our libdds build (see build_libdds.sh in
// this directory) to make the library safe to use from multiple
// Dart isolates in one process:
//
// - DdsEnsureInit initializes thread memory exactly once process-wide.
//   Calling SetMaxThreads again from a later isolate resets state under
//   in-flight or subsequent solves, and GetDDSInfo can't be used to probe
//   initialization because it crashes on an uninitialized library.
// - DdsAcquireThreadIndex / DdsReleaseThreadIndex hand out exclusive
//   thread indices, bounded by the number of threads DDS actually
//   configured (SetMaxThreads caps at the core count). Callers must
//   bracket every solve with acquire/release; when all slots are busy,
//   acquire returns -1 and the caller should fall back to another solver.
//   A round-robin dispenser is NOT sufficient: solves finish out of
//   order, so a slow caller can still hold an index when the counter
//   wraps around to it.

#include <atomic>
#include <mutex>

#include "dll.h"

#define DDS_SHIM_MAX_THREADS 16

static std::atomic<bool> slotBusy[DDS_SHIM_MAX_THREADS];
static int usableThreads = 0;

extern "C" void DdsEnsureInit() {
  static std::once_flag flag;
  std::call_once(flag, [] {
    // Bound total memory on every platform. DDS treats the figure as
    // +30% (166MB) and needs 30MB per small-table thread, so this
    // yields min(cores, 5) small threads. Each slot serves one caller
    // at a time, and the app runs at most three concurrent solves: the
    // AI for the player's round, the duplicate round replay, and the
    // fire-and-forget par calculation, which can still be running when
    // the next round starts.
    //
    // 128 rather than 256 also keeps DDS out of its large-table branch
    // on low-core devices. SetResources picks large tables whenever
    // cores * 160MB fits the budget, so with 256 a 2-core phone gets two
    // 160MB large tables and a 4-core phone one -- the wrong trade
    // exactly where memory is tightest. Benchmarking on an M4 Mac shows
    // small tables are at worst 10% slower, so nothing is lost.
    SetResources(128, DDS_SHIM_MAX_THREADS);
    DDSInfo info;
    GetDDSInfo(&info);
    usableThreads = info.noOfThreads;
    if (usableThreads > DDS_SHIM_MAX_THREADS)
      usableThreads = DDS_SHIM_MAX_THREADS;
  });
}

// True on the first call in the process and false afterwards, so a caller
// can log the library load exactly once no matter which isolate gets there
// first. Dart statics are per-isolate and every compute() isolate opens the
// library again, so the Dart side cannot answer this on its own.
extern "C" int DdsClaimFirstLoadLog() {
  static std::atomic<bool> claimed(false);
  bool expected = false;
  return claimed.compare_exchange_strong(expected, true) ? 1 : 0;
}

extern "C" int DdsAcquireThreadIndex() {
  for (int i = 0; i < usableThreads; i++) {
    bool expected = false;
    if (slotBusy[i].compare_exchange_strong(expected, true))
      return i;
  }
  return -1;
}

extern "C" void DdsReleaseThreadIndex(int i) {
  if (i >= 0 && i < DDS_SHIM_MAX_THREADS)
    slotBusy[i].store(false);
}
