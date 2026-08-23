#!/bin/sh
# Builds libdds (dds-bridge/dds v2.9.0 plus dds_shim.cpp) for use via Dart
# FFI (lib/bridge/dds_ffi.dart).
#
# Usage:
#   sh cpp/build_libdds.sh    # host build -> native/
#
# Builds from the vendored sources in third_party/dds (override with
# DDS_SRC to point at another checkout). The output is gitignored. App
# builds run this automatically: the macOS Runner's "Embed libdds"
# phase invokes it when sources are newer than the dylib, and Android
# and Linux compile the same sources themselves via
# android/app/CMakeLists.txt and linux/CMakeLists.txt. Run manually
# only for command-line use (DDS_LIB=native/libdds.dylib).
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MODE="${1:-host}"

if [ -z "$DDS_SRC" ]; then
  DDS_SRC="$REPO_DIR/third_party/dds"
fi

COMMON="-O2 -std=c++11 -DDDS_THREADS_STL -I$DDS_SRC/include -I$DDS_SRC/src"
SOURCES="$DDS_SRC/src/*.cpp $SCRIPT_DIR/dds_shim.cpp"

build_host() {
  OUT_DIR="$REPO_DIR/native"
  mkdir -p "$OUT_DIR"
  case "$(uname)" in
    Darwin) LIB="libdds.dylib"; SHARED="-dynamiclib" ;;
    *) LIB="libdds.so"; SHARED="-shared -fPIC" ;;
  esac
  echo "Building $OUT_DIR/$LIB"
  clang++ $COMMON $SHARED $SOURCES -o "$OUT_DIR/$LIB"
}

case "$MODE" in
  host|macos) build_host ;;
  *) echo "Unknown mode: $MODE" >&2; exit 1 ;;
esac
echo "Done"
