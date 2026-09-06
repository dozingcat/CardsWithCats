# Changelog

All notable changes to the Scum game mode of Cards With Cats.

## 0.4.2

Gameplay, layout and bot fixes from the 0.4.1 playtest.

- **Tricks finish on screen** (#14, #16): a completed trick now has a hold of
  its own between the last card landing and the trick being swept to the
  winner, so the play that ended it — often a bot's ace — is always visible
  first. The end-of-round summary waits for those animations instead of
  appearing the instant the last card is played, which used to hide the final
  trick of every hand.
- **No more auto-finishing** (#16): the "remaining tricks claimed" shortcut is
  gone. When the leader can no longer lose a trick the hand still plays out
  card by card, the way it would with real people at a table.
- **Hearts score beside every cat** (#18): each seat shows its total and the
  points it has picked up this round, with the current leader marked, so it is
  easy to see who is worth dumping points on without opening the overlay.
- **Layout** (#17): Scum role badges wrap "Vice President" onto two centered
  lines, sit outside the play area so a rank never covers a played card, and
  the player's own badge moved off the hand. Mood bubbles hang clear of the
  seat badges and no longer sit on top of the score summary. Hearts point-card
  tinting is a subtle wash rather than a solid fill, so an overlapping run of
  hearts no longer reads as one pink block. The score summary itself is opaque.
- **Cat reactions** (#19): the cats react the moment a seat goes out rather
  than only at the end of the round — the new president grins, the vice
  president is pleased, and everyone still holding cards is annoyed about it.
  The finished table stays uncovered briefly so the reactions can be seen.
- **Scum trade prompt was cut off**: the "choose cards to give away" message
  ran off both edges of the screen, because the dialog was laid out at the full
  window width and then scaled up. It now wraps inside the window.
- **Scum totals were wrong**: the end-of-round summary showed each player's
  score from *before* the round it was summarizing, because the match totals
  are only folded forward when Continue is pressed. It now includes the round
  just played.
- **Smarter cats** (#12): the Scum bots now keep a reserve of high cards in
  proportion to the low cards they still have to shed, instead of spending an
  ace on a trick that did not need it. Measured over 12000 simulated rounds
  this improves their mean finish from 1.54 to 1.46 and drops last place from
  27.3% to 22.7%.

## 0.4.1

- Added the current main-menu and Scum screenshots to AppStream metadata so
  SpacedBazaar can show real game previews before installation.

## 0.4.0

- Renamed the app, repository, and Flatpak ID to **Cards With Cats**.
- Fixed the human Scum play pile overlapping and intercepting cards in the hand on desktop-sized Flatpak windows.
- Added a quick, smooth entrance for Scum plays and kept the human hand above table effects.
- Polished every game mode with a richer card table, clearer surfaces and controls, subtle card depth, and a refreshed main menu.
- Added real game screenshots and streamlined the project README.

## 0.3.3

- Added a rules summary for Scum to the About dialog, following the format of the other games.

## 0.3.2

- **Fixed a frozen table on new matches**: starting (or restarting) a match while the Start Match dialog was still open could leave the turn scheduler permanently disabled — a cat would be highlighted but nobody ever played. Turn scheduling now waits for the menu to close instead of bailing out.
- Added two safety nets so no bad state can freeze a round again: every AI move falls back to a legal play on error, and an activity watchdog resumes the turn engine if it ever stops making progress.

## 0.3.1

- Play moved to the right side of the table and Pass to the left — Play is hit far more often and most players are right-handed (#7 follow-up). Both buttons sit partway in from the edges rather than hugging the screen sides.

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
