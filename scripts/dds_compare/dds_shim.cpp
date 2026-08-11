// Small shim compiled into our libdds build (see build_libdds.sh) to make
// the library safe to use from multiple Dart isolates in one process:
// - DdsEnsureInit initializes thread memory exactly once process-wide
//   (calling SetMaxThreads again from a later isolate resets state under
//   in-flight or subsequent solves; GetDDSInfo can't be used to probe
//   because it crashes on an uninitialized library).
// - DdsNextThreadIndex hands out round-robin thread indices, so isolates
//   created within a window of DDS_SHIM_THREADS of each other never share
//   an index. Concurrent solves are safe as long as no more than
//   DDS_SHIM_THREADS isolates are in flight at once.

#include <atomic>
#include <mutex>

#include "dll.h"

#define DDS_SHIM_THREADS 16

extern "C" void DdsEnsureInit() {
  static std::once_flag flag;
  std::call_once(flag, [] { SetMaxThreads(DDS_SHIM_THREADS); });
}

extern "C" int DdsNextThreadIndex() {
  static std::atomic<int> counter{0};
  return counter.fetch_add(1) % DDS_SHIM_THREADS;
}
