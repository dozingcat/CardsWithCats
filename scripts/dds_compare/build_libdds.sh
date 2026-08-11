#!/bin/sh
# Builds libdds (dds-bridge/dds v2.9.0) as a dynamic library for use via
# Dart FFI (lib/bridge/dds_ffi.dart). Usage:
#   sh scripts/dds_compare/build_libdds.sh [output-dir]
# Clones the source into a temporary directory if a checkout isn't given
# via DDS_SRC, and writes libdds.dylib (macOS) or libdds.so (Linux) into
# the output dir (default: native/).
set -e
OUT_DIR="${1:-native}"
mkdir -p "$OUT_DIR"
if [ -z "$DDS_SRC" ]; then
  DDS_SRC="$(mktemp -d)/dds"
  echo "Cloning dds v2.9.0 into $DDS_SRC"
  git clone -q --depth 1 --branch v2.9.0 https://github.com/dds-bridge/dds.git "$DDS_SRC"
fi
case "$(uname)" in
  Darwin) LIB="libdds.dylib"; SHARED="-dynamiclib" ;;
  *) LIB="libdds.so"; SHARED="-shared -fPIC" ;;
esac
echo "Building $OUT_DIR/$LIB"
SCRIPT_DIR="$(dirname "$0")"
clang++ -O2 -std=c++11 -DDDS_THREADS_STL \
  -I"$DDS_SRC/include" -I"$DDS_SRC/src" \
  $SHARED "$DDS_SRC"/src/*.cpp "$SCRIPT_DIR/dds_shim.cpp" \
  -o "$OUT_DIR/$LIB"
echo "Done: $OUT_DIR/$LIB"
