// Small shim compiled into our libdds build (see build_libdds.sh in
// this directory) to make
// the library safe to use from multiple Dart isolates in one process:
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
#ifdef __ANDROID__
    // On mobile, bound total memory: DDS otherwise sizes its per-thread
    // transposition tables from free RAM (up to 160MB per thread).
    SetResources(256, DDS_SHIM_MAX_THREADS);
#else
    SetMaxThreads(DDS_SHIM_MAX_THREADS);
#endif
    DDSInfo info;
    GetDDSInfo(&info);
    usableThreads = info.noOfThreads;
    if (usableThreads > DDS_SHIM_MAX_THREADS)
      usableThreads = DDS_SHIM_MAX_THREADS;
  });
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
