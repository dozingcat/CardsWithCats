#!/bin/bash
# Build an installable Cards With Cats Flatpak bundle from the current source.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APP_ID=io.github.crhy.CardsWithCats
PREBUILT="$ROOT/flatpak/prebuilt"
BUNDLE="$ROOT/build/CardsWithCats.flatpak"

"$ROOT/scripts/build-linux-in-sdk.sh"

install -d "$PREBUILT"
rm -rf "$PREBUILT/data" "$PREBUILT/lib"
install -m755 "$ROOT/build/linux/x64/release/bundle/CardsWithCats" "$PREBUILT/CardsWithCats"
cp -a "$ROOT/build/linux/x64/release/bundle/data" "$PREBUILT/data"
cp -a "$ROOT/build/linux/x64/release/bundle/lib" "$PREBUILT/lib"
install -m644 "$ROOT/flatpak/$APP_ID.desktop" "$PREBUILT/$APP_ID.desktop"
install -m644 "$ROOT/flatpak/$APP_ID.metainfo.xml" "$PREBUILT/$APP_ID.metainfo.xml"
install -m644 "$ROOT/flatpak/$APP_ID.png" "$PREBUILT/$APP_ID.png"

flatpak-builder --force-clean \
  --repo="$ROOT/build/flatpak-repo" \
  "$ROOT/build/flatpak-target" \
  "$ROOT/flatpak/$APP_ID.yml"
flatpak build-bundle "$ROOT/build/flatpak-repo" "$BUNDLE" "$APP_ID"

echo "Bundle ready: $BUNDLE"
