# dds (vendored)

Bo Haglund's double dummy solver, vendored verbatim from
https://github.com/dds-bridge/dds at tag `v2.9.0`
(commit 8d75755c8df81999557758c9757514edb94017bc), so that app builds
with the native DD backend are hermetic.

Contents: `LICENSE` (Apache 2.0), `include/`, and the `.cpp`/`.h` files
from `src/`. Build-system files, Windows resources, and docs from the
upstream repository are omitted; **no source files are modified**.
Local additions live outside this directory: the isolate-safety shim is
`cpp/dds_shim.cpp`, and `cpp/build_libdds.sh`
builds the library for macOS (`native/`) and Android (`jniLibs/`).

Version note: v2.9.0 rather than the newer DDS3 line by choice — DDS3
uses the same search algorithm, and 2.9.0 is validated against our
pure-Dart solver and a brute-force reference on ~10,000 positions
(`scripts/dds_compare/dds_ffi_check.dart` re-verifies in minutes) and
builds with a single clang++ invocation on every platform we target.
