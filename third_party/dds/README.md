# dds (vendored)

Bo Haglund's double dummy solver, vendored from
https://github.com/dds-bridge/dds at tag `v2.9.0`
(commit 8d75755c8df81999557758c9757514edb94017bc), so that app builds
with the native DD backend are hermetic.

Contents: `LICENSE` (Apache 2.0), `include/`, and the `.cpp`/`.h` files
from `src/`. Build-system files, Windows resources, and docs from the
upstream repository are omitted.

**Local patches** (one; marked inline with a `LOCAL PATCH` comment, so
`git diff` against upstream stays readable): `System::GetHardware` in
`src/System.cpp` reads free memory from `/proc/meminfo` instead of
`popen("free -k | tail -n+3 | head -n1 | awk '{print $NF}'")`.
Upstream's command reads the `-/+ buffers/cache` line that procps
dropped in 3.3.10, so on a current distribution line 3 is `Swap:` and
the command returns free *swap* — zero on a machine without swap.
`SetResources` then budgets zero memory, configures zero threads, and
the first solve aborts the whole process with `Memory::GetPtr: 0 vs.
0`.

Android is unaffected by the original bug, since toybox's `free` still
prints the old three-line layout and the parse lands on the field
upstream intended — but that is coincidence, not a contract, and the
patch applies there too (Android compiles this same `__linux__`
branch). It changes nothing in practice for Android builds: both
figures sit far above the 256 MB that `DdsEnsureInit` already caps
`SetResources` at.

Other local additions live outside this directory: the isolate-safety
shim is `cpp/dds_shim.cpp`, and `cpp/build_libdds.sh`
builds the library for macOS (`native/`) and Android (`jniLibs/`).

Version note: v2.9.0 rather than the newer DDS3 line by choice — DDS3
uses the same search algorithm, and 2.9.0 is validated against our
pure-Dart solver and a brute-force reference on ~10,000 positions
(`scripts/dds_compare/dds_ffi_check.dart` re-verifies in minutes) and
builds with a single clang++ invocation on every platform we target.
