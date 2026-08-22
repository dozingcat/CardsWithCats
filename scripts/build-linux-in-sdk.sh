#!/bin/bash
# Builds the Flutter Linux release bundle inside the Freedesktop SDK
# sandbox, so machines without GTK3/clang/ninja development packages can
# still produce binaries that match the Flatpak runtime exactly.
#
# Requires: flatpak, the org.freedesktop.Sdk//<ver> runtime, and a Flutter SDK.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FLUTTER=${FLUTTER_SDK:-$HOME/development/flutter}
SDK_VERSION=${SDK_VERSION:-25.08}

if [ ! -x "$FLUTTER/bin/flutter" ]; then
    echo "Flutter SDK not found at $FLUTTER (override with FLUTTER_SDK=...)" >&2
    exit 1
fi

mkdir -p "$ROOT/build"

# Some flatpak builds mishandle trailing arguments on runtime refs, so the
# inner build script is piped in on stdin instead of passed as an argument.
cat <<EOF | flatpak run --user \
    --filesystem="$ROOT" \
    --filesystem="$FLUTTER" \
    --share=network \
    --command=bash \
    org.freedesktop.Sdk//$SDK_VERSION
set -euo pipefail
export PATH="/usr/lib/sdk/llvm20/bin:$FLUTTER/bin:\$PATH"
export HOME="$ROOT/build/sdk-home"
export XDG_CONFIG_HOME="\$HOME/.config"
mkdir -p "\$HOME"
git config --global --add safe.directory "$FLUTTER" || true
git config --global --add safe.directory "$ROOT" || true
cd "$ROOT"
flutter config --no-analytics >/dev/null
flutter pub get
flutter build linux --release
echo "Bundle ready: $ROOT/build/linux/x64/release/bundle"
EOF
