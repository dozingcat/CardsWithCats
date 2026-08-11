#!/bin/sh
# Builds libdds (dds-bridge/dds v2.9.0 plus dds_shim.cpp) for use via Dart
# FFI (lib/bridge/dds_ffi.dart).
#
# Usage:
#   sh scripts/dds_compare/build_libdds.sh           # host build -> native/
#   sh scripts/dds_compare/build_libdds.sh macos     # host build AND copy
#                                                    # where the macOS app
#                                                    # build phase finds it
#   sh scripts/dds_compare/build_libdds.sh android   # NDK cross-builds ->
#                                                    # android/app/src/main/jniLibs/<abi>/
#
# Builds from the vendored sources in third_party/dds (override with
# DDS_SRC to point at another checkout). Android needs ANDROID_NDK_HOME
# or an NDK under ~/Library/Android/sdk/ndk. Build outputs are
# gitignored; run this script locally before building the app with dds
# support.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
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

build_android() {
  if [ -z "$ANDROID_NDK_HOME" ]; then
    ANDROID_NDK_HOME="$(ls -d "$HOME"/Library/Android/sdk/ndk/* 2>/dev/null | sort -V | tail -1)"
  fi
  if [ -z "$ANDROID_NDK_HOME" ] || [ ! -d "$ANDROID_NDK_HOME" ]; then
    echo "Android NDK not found; set ANDROID_NDK_HOME" >&2
    exit 1
  fi
  TOOLCHAIN="$(ls -d "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin | head -1)"
  echo "Using NDK toolchain $TOOLCHAIN"
  for ABI_TRIPLE in \
      "arm64-v8a aarch64-linux-android21" \
      "armeabi-v7a armv7a-linux-androideabi21" \
      "x86_64 x86_64-linux-android21"; do
    set -- $ABI_TRIPLE
    ABI="$1"; TRIPLE="$2"
    OUT_DIR="$REPO_DIR/android/app/src/main/jniLibs/$ABI"
    mkdir -p "$OUT_DIR"
    echo "Building $OUT_DIR/libdds.so"
    "$TOOLCHAIN/clang++" --target="$TRIPLE" $COMMON -shared -fPIC \
      -static-libstdc++ $SOURCES -o "$OUT_DIR/libdds.so"
  done
}

case "$MODE" in
  host|macos) build_host ;;
  android) build_android ;;
  *) echo "Unknown mode: $MODE (use host, macos, or android)" >&2; exit 1 ;;
esac
echo "Done"
