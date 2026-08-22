# Changelog

All notable changes to the Scum game mode of Cards With Cats.

## 0.3.0

Playtest refinements across visibility, input, sound, and AI judgment.

- **Selection**: when exactly one play is available it is selected automatically, so committing it is always a single tap on Play (#5).
- **Input reliability**: card taps are no longer swallowed while AI turns resolve, fixing plays that seemed to need a second tap (#6).
- **Layout**: Play moved to the left edge and Pass to the right edge, directly above the hand; played sets fan out more tightly (#7).
- **Flatpak layout**: the play piles now form an evenly spaced ring around the center of the table with the side seats pulled in toward the middle (#9).
- **Sound**: the flatpak ships with pulseaudio access so cat sounds play, and a volume slider was added to Preferences (#8).
- **AI judgment**: the cats no longer lead or beat with high quads (or high pairs/triples) while deep in cards; power hands are split and saved for decisive moments (#10).

## 0.2.0 — Initial release

The first complete release of four-player Scum against three AI cats.

### Gameplay
- Four-player Scum with table ranks **President, Vice President, Vice Scum, and Scum**. The opening round has no ranks — everyone is a Citizen, a random player leads, and no cards are exchanged.
- Standard 52-card deck, 2 through Ace, Aces high, deuces low; suits never matter.
- Lead singles, pairs, triples, or quads. Beat a play with the same number of cards at a higher rank, or pass. The last play wins the trick and leads next.
- An ace ends the trick immediately: nothing can beat it.
- A turn with no legal play passes automatically.
- Before each round after the first, cards are traded: Scum must pass their two highest cards to the President (who gives any two back), and Vice Scum must pass their highest card to the Vice President (who gives any one back). Finish order sets the next round's ranks.
- Matches are eight rounds scored 3/2/1/0 by finish position.

### AI opponents
- The three cats count cards, shed low leads, preserve sets and high cards for control, block rivals close to going out, take cheap beats aggressively, and spend unbeatable plays only when the rest of their hand can follow them out.

### Interface
- Rank-sorted hand: aces on the left down to twos on the right.
- Every seat shows its current rank and card count.
- Tap a card to select all copies of that rank; tap a selected card again to peel off just that one so partial sets stay playable.
- Play/Pass buttons float mid-table, clear of your hand and the played cards; played sets render small so they never cover anything.
- Trade selection works like Hearts passing; forced passes need no input.
- End-of-round tally shows finish order, roles, round points, and running totals in a compact, opaque dialog.
- Match state is saved automatically and survives app restarts.

## 0.1.x alphas

Rapid playtest iterations leading up to 0.2.0:

- **0.1.0-alpha** — first playable build: engine, trading rules, AI cats, Android APK.
- **0.1.1-alpha** — Citizen opening round with no exchange; far more aggressive cats (capped overtaking-risk penalty, cheap-beat bonuses, ace discipline); action buttons moved off the hand; fixed president/vice-president trade selection; badges show only the rank name.
- **0.1.2-alpha** — opponents show card counts; hand sorted by rank instead of suit; buttons clear of hand and plays; trade selections written into the round (the real #2 fix); automatic passing; ace ends tricks; whole-rank tap selection.
- **0.1.3-alpha** — played cards shrunk to a fraction of hand size; bottom pile biased away from the hand; action row positioned between play piles clear of the top badge.
- **0.1.4-alpha** — end-of-round tally fits any screen with compact labels and an opaque background; player badge moved to the bottom-right corner; "Play set" renamed to Play.
