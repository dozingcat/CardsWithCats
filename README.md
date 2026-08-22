# Scum With Cats

Play **Scum** — the classic climbing card game — against three computer-controlled cats, plus the original Hearts, Spades, and Oh Hell modes from [Cards With Cats](https://github.com/dozingcatsoftware/CardsWithCats).

Built with [Flutter](https://flutter.dev).

## The game

Four players: you versus three AI cats, seated as President, Vice President,
Vice Scum, and Scum. Lead singles, pairs, triples, or quads; beat the play
with the same count at a higher rank or pass; last play takes the trick and
leads next. Aces are high, deuces are low, suits don't matter.

Before each round the lowly trade with the mighty: Scum must pass their two
highest cards to the President (who gives any two back), and Vice Scum must
pass their highest card to the Vice President (who gives any one back).
First out of a round becomes the next President; matches run eight rounds
scored 3/2/1/0 by finish position.

The cats count cards, shed low leads, hoard sets for control, block rivals
about to go out, and know when an ace is worth spending.

## Install

### Android
Grab `app-std-release.apk` from the [releases page](https://github.com/crhy/ScumWithCats/releases) and open it on your phone (allow installs from your browser if asked). Debug builds use the `std` flavor: `flutter build apk --flavor std --release`.

### Linux (Flatpak)
Grab `ScumWithCats.flatpak` from the releases page and run:

```
flatpak install --user ./ScumWithCats.flatpak
flatpak run io.github.crhy.ScumWithCats
```

### Build from source
Requires the Flutter SDK. For the Linux binary on machines without GTK dev
headers, build inside the freedesktop SDK sandbox:

```
./scripts/build-linux-in-sdk.sh
flatpak-builder --user --install-deps-from=flathub build/flatpak flatpak/io.github.crhy.ScumWithCats.yml
```

See `CHANGELOG.md` for release history.

## Credits

Based on [Cards With Cats](https://github.com/dozingcatsoftware/cardswithcats) by Brian Nenninger:
- Cats by [AnnaliseArt on Pixabay](https://pixabay.com/illustrations/cats-hanging-cats-kitty-cat-paw-3611310/)
- Cat emojis from [Noto Emoji by Google](https://github.com/googlefonts/noto-emoji/)
- Thought bubble by [OpenClipart-Vectors on Pixabay](https://pixabay.com/vectors/balloon-bubble-speech-thought-150981/)
- Playing cards: \
https://totalnonsense.com/open-source-vector-playing-cards/ \
Copyright 2011,2024 – Chris Aguilar – conjurenation@gmail.com \
Licensed under: LGPL 3.0 – https://www.gnu.org/licenses/lgpl-3.0.html

Scum rules adapted from Bruce Gourley's party rules.
