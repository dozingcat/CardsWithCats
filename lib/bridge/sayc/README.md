# SAYC Bidding Engine

A rules-based contract bridge bidding engine implementing a Standard American
(SAYC-style) system with two-over-one responses showing 10+ points.

**Scope:**
- Uncontested auctions through opener's third call (five calls deep, six for
  Blackwood/Gerber placement): openings, responses, rebids, Stayman/transfer
  machinery, invitation accept/decline, and slam conventions.
- Two rounds of competitive auctions: overcalls, takeout and negative
  doubles, advances (including penalty passes), reopening and sandwich
  seats, and both sides' second calls in competition.
- A constraint-based fallback bidder for everything else, so `selectSaycBid`
  always returns a call.

## Architecture

Every auction context is an ordered list of `SaycRule`s, each pairing a
candidate `BidAction` with the `BidMeaning` it shows and (when the public
meaning isn't the whole selection condition) a `require` predicate. A rule
matches a hand when the hand satisfies the meaning's constraints and the
predicate; `ignoreInfo: true` makes the predicate the sole selection
condition, used when the advertised range is narrower than the hands that
actually make the call (e.g. a "13-21" opening that a 23-point hand still
makes).

The same tables drive both directions:

- **Selection**: `selectSaycBid` returns the first rule the hand satisfies.
- **Interpretation**: `describeSaycCall` looks up what a call would show
  with no hand at all, merging (union) when a call has several meanings;
  `explainSaycAuction` interprets every call and intersects each seat's
  calls into a running constraint set.

Positions outside the rule tables (`saycRulesForAuction` returns null) go to
the fallback bidder: it accumulates everything partner has shown via the
interpretation layer, then bids game with 25+ combined points (preferring a
known 8-card fit, else 3NT with stoppers in the opponents' suits), competes
to the level of the combined trump count (law of total tricks), doubles for
penalty with a strong trump stack over their 2-level+ contract or when they
preempt into 23+ combined points, and otherwise passes. It never initiates
slams and labels its output with a "Fallback:" description.

### Adding a convention: continuations don't consult meanings

Selection routes **structurally**: the dispatcher and the continuation
tables branch on the raw shape of earlier calls (suit, level, position),
not on what those calls meant. They never call `describeSaycCall`. So a new
conventional call is only half-defined by its rule — the tables for the
following calls will otherwise pattern-match its shape into some existing
natural branch and misplay it with confidence. (When splinters were added,
`1H-3S` was correctly *described* as a splinter while opener's rebid table
simultaneously treated it as a natural spade suit and "raised" the
singleton.) The interpretation layer and the continuation tables stay
consistent only by discipline; only the fallback bidder actually bids from
accumulated meanings.

Checklist for a new convention:
1. Add the rule (its `BidMeaning` doubles as the selection condition;
   ordering in the table sets priority).
2. Teach partner's next-call table to recognize the shape (and the table
   after that, if the sequence continues — e.g. an ace-ask needs answer
   *and* placement handling).
3. Check whether the same shape means something else in competition
   (a double jump is a splinter uncontested but a natural free bid over an
   overcall — the `contested` flag on the rebid delegations exists for
   this).
4. Run self-play: misread conventions surface as quality findings
   (silly-strain contracts, missed games) even when every call is legal.

## API

```dart
import 'package:cards_with_cats/bridge/sayc/sayc_bidding.dart';

// History is a flat List<BidAction> starting with the DEALER's first call;
// seats are derived from list positions relative to the caller (the next
// call belongs to the caller). BridgeRound.bidHistory is already
// dealer-first: round.bidHistory.map((b) => b.action).toList().
final result = selectSaycBid(hand, history);  // never null
result.action                 // BidAction
result.meaning                // BidMeaning: what the call shows
result.meaning.hcp            // Range? (null = unspecified)
result.meaning.totalPoints    // Range? (HCP + length points)
result.meaning.balanced       // bool?
result.meaning.artificial     // true for Stayman, transfers, ...
result.meaning.suitLengths    // Map<Suit, Range>
result.meaning.summary()      // "13-15 total points, 4+ spades"

// Interpretation, no hand needed:
final meaning = describeSaycCall(history, BidAction.fromString("X"));
// -> "8+ total points, 4+ hearts, artificial" for 1D-(1S)-X, or null when
//    the call has no defined meaning / the position isn't in the tables.

final ex = explainSaycAuction(history);
ex.calls[i].meaning           // per-call BidMeaning? (null = undefined)
ex.players[seat]              // accumulated constraints, seat 0 = dealer

saycRulesForAuction(history)  // raw candidate rules; null = fallback
                              // territory; throws StateError if the
                              // auction is already over
```

`parseHand` accepts 13 cards (`"AS QS 3S ..."`) or four suit groups, spades
first with `-` for a void (`"A2 AKJT Q32 9876"`); `handGroupString` formats
the reverse. `HandAnalysis` precomputes hcp/totalPoints/isBalanced/
hasStopper/aces for a hand. The `vulnerability` parameter is accepted and
reserved (e.g. for preempt aggressiveness, double-vs-bid-on) but not yet
consulted.

## System rules implemented

### Openings
- 5-card majors; better minor (4-4 opens 1D, 3-3 opens 1C; 1D can be 3 cards
  only with exactly 4=4=3=2).
- 1NT = 15-17 balanced (may contain a 5-card major); 2NT = 20-21 balanced.
- 2C = strong and artificial, 22+ HCP.
- Weak twos (2D/2H/2S) = 6-card suit, 5-10 HCP; 3-level = 7-card suit,
  4-level = 8+; preempts take priority over shape-based light openings.
- One-level suit openings need 13+ total points (HCP + length points).

### Responses
- To one of a major: single raise 6-10 with 3+ trumps (raises take priority
  over new suits on minimum hands), limit raise 11-12, splinter (double jump
  in a new suit, e.g. 1H-3S or 1S-4D) = game-forcing raise with 4+ trumps,
  12-15, and a singleton or void in the bid suit, Jacoby 2NT = 13+ with
  4+ trumps (game-forcing, and the route for 16+ hands even with shortness);
  1S over 1H = 4+ spades, 6+; two-over-one = 10+ points, forcing (2H over 1S
  shows 5+ hearts); 1NT = 6-9, no fit. Opposite a splinter, opener signs off
  in game with 13-15 and bids Blackwood with 16+.
- To one of a minor: 4-card majors up the line (longer major first, 5-5 bids
  spades); 1D over 1C with 4+ diamonds; raises need 4+ support and deny a
  4-card major (6-10 / 11-12); 2NT = 13-15 balanced, 3NT = 16-18 balanced;
  two-over-one in the other minor = 10+.
- To 1NT: Jacoby transfers with any 5-card major (any strength), Stayman with
  a 4-card major and 8+ HCP, 2NT = 8-9, 3NT = 10-15, quantitative 4NT =
  16-17, Gerber 4C = 18+.
- To 2NT: Jacoby transfers (3D/3H) with any 5-card major, Stayman 3C with a
  4-card major and 5+ HCP, Gerber 4C = 13+, quantitative 4NT = 11-12,
  3NT = 5-10.
- To 2C: positives with 8+ HCP — a good 5+ card suit (two of the top three
  honors) at its cheapest non-2D level (2H/2S/3C/3D), else 2NT if balanced;
  2D waiting otherwise.
- To weak twos: preemptive raise with 3+ trumps, game with 15+ and 3+
  trumps or 16+ and a doubleton (the 8-card fit beats 3NT), 3NT to play
  with 16+ and no fit; otherwise pass. Over 3-level preempts: game with 15+
  and a fit, 3NT with 16+.

### Opener rebids
- After a new-suit response: raise partner's major with 4 trumps (13-15
  single, 16-18 jump, 19+ game); over a minor response show a 4-card major
  first; NT rebids show 12-14 (cheapest) or 18-19 (jump) balanced; 6-card
  suit rebids (13-15 cheap, 16+ jump); second suits at the cheapest level,
  with reverses requiring 17+ and jump shifts showing 18+; otherwise rebid
  the suit.
- After raises: pass minimums, invite with 16-18, bid game with 19+ (accept
  a limit raise with 14+).
- After Jacoby 2NT: 4M minimum, 3M with extras.
- After 1NT openings: Stayman answers (2D/2H/2S, hearts first with both),
  transfer completions, invitation accepted with 16+; the post-transfer 2NT
  invite is accepted with any 4 trumps (9-card fit), and a minimum with 3
  trumps declines into 3M rather than passing. After 2NT openings the
  same structures one level higher (3D/3H/3S Stayman answers, transfer
  completions); responder continues game-going (raise the found fit, 3NT
  choice-of-games with five, 4M with six) and opener corrects with a fit.
- After 2C-2D: 2NT = 22-24 balanced, 3NT = 25-27, otherwise longest suit.
- After a positive response to 2C: raise the suit with 3+ support
  (game-forcing; responder then signs off in game or bids Blackwood with
  10+), else cheapest NT with 22-24 balanced, else a natural 5+ suit; over
  the 2NT positive, 3NT with 22-24 and 6NT with 25+.

### Responder rebids
- 1NT auctions: raise Stayman-found fits (invite 8-9, game 10+), retreat to
  2NT/3NT without a fit; after a transfer, pass 0-7, invite with 8-9 (2NT
  with five trumps, 3M with six), and bid game with 10+ (3NT choice-of-games
  with five trumps, 4M with six).
- After opener raises responder's suit: pass 6-10, invite 11-12, game 13+;
  over a jump raise, game with 8+.
- After opener's 1NT rebid: pass 6-10, 2NT invite 11-12, 3NT 13+, with
  signoffs/invites/games in a 6-card major.
- After opener rebids its own suit or a second suit: weak hands pass, sign
  off in a 6-card suit, or give preference to opener's first suit; 11-12
  invites (raise with fit, else 2NT); 13+ bids game. A second-suit major is
  raised with 4-card support (6-9 cheap, 10-12 jump, 13+ game). Reverses are
  one-round forces: responder chooses game with 8+ and otherwise retreats as
  cheaply as possible. Jump shifts force to game: any 4-card fit for the
  second suit raises (3+ with a point to spare after a 1NT response), a
  preference to opener's first suit needs a doubleton, and with no fit or
  tolerance responder retreats to notrump — never a singleton "preference";
  opener drives any below-game retreat on to game.
- Two-over-one auctions: opener's minimum rebids may be passed with 10-11;
  12+ drives to game.
- After 2C-2D: raise opener's major to game with 3+ support, mark time with
  the cheapest notrump without support, 3NT over 2NT with 3+ HCP.
- After a 2C positive: opposite a raise, Blackwood with 10+ else game;
  opposite a notrump rebid, 6NT with 11+ HCP (33+ combined) else game;
  opposite opener's own suit, raise a major to game with 3+ support else
  3NT.

### Slam bidding
- Gerber 4C over 1NT (18+ HCP) and 2NT (13+) openings: answers 4D/4H/4S/4NT
  = 0-4/1/2/3 aces; the asker bids 6NT missing at most one ace, else signs
  off in 4NT.
- Quantitative 4NT: over 1NT = 16-17 (opener accepts with 17), over 2NT =
  11-12 (accepts with 21), and over opener's notrump rebids (accepts at the
  top of the shown range). Also after Stayman/transfer sequences.
- Blackwood 4NT after suit agreement (currently launched from Jacoby 2NT
  sequences: 16+ opposite extras, 18+ opposite a minimum): answers
  5C/5D/5H/5S = 0-4/1/2/3 aces; the asker bids six missing at most one ace,
  else stops at five. No 5NT king-ask or grand-slam machinery; the ambiguous
  0-or-4 answers are disambiguated from the asker's own aces.

### Opener's third call
- Accepts or declines responder's invitations based on the top of the range
  already shown (e.g. 13-14 of a 12-14 1NT rebid, 14-15 of a 13-15 raise),
  passes signoffs and game placements, corrects Stayman 3NT to a known 4-4
  spade fit, completes transfer choice-of-games sequences with a 3-card
  fit, and enforces the 2C game force (never passing responder's 2NT below
  game). 3NT accepts remain stopper-blind (a known simplification).

### Competitive bidding
- Direct-seat actions over their opening: simple overcalls (5+ suit, 8-16 at
  the one level, 10-16 at the two level), weak jump overcalls (6+ suit,
  5-9), 1NT overcall = 15-18 balanced with a stopper (2NT over a weak two),
  and takeout doubles (opening values with shortness and support for the
  unbid suits, or 17+ any shape). Doubles of 1-3 level openings are always
  takeout; trump-stack hands trap-pass and convert partner's reopening
  double. Over 4-level preempts a double is optional/penalty-leaning (4+
  cards with 6+ HCP in their suit, 12+ points). Balancing seat is treated
  like direct seat.
- Advancing a forced takeout double includes the penalty pass: with 4+
  trumps (5+ HCP among them) and 8+ HCP, the double is converted rather
  than advanced. Advances never jump past game; a takeout double is
  answered in the best unbid suit (0-8 cheap, 9-11 jump, 12+ game);
  overcalls are raised with 3+ support on the 6-10/11-12/13+ ladder (13+
  without a stopper for notrump raises a minor overcall to 5m with 4+
  support; with only three, a cue bid of their suit shows a limit raise
  or better and the overcaller chooses 3NT with a stopper, signs off at
  the cheapest level with a minimum, or raises to game with 13+), and
  3NT needs only 12 opposite a sound overcall of a preempt; systems on
  over partner's 1NT overcall.
- Responder over an overcall: raises keep their uncontested meanings (major
  raises take priority over a negative double); negative doubles show 4+
  cards in the unbid major (exactly four at the one level — with five, bid
  the suit; both majors 4-4 when two are unbid), 6+ points at the one
  level, 8+ at the two level; free new suits are forcing (4+ at the one
  level, 5+/10+ at the two level, 5+/12+ at the three level); notrump bids
  show a stopper in their suit.
- Over RHO's takeout double: redouble = 10+ HCP without a fit, otherwise
  systems on.
- Opener after partner's negative double: bids the implied major with four
  (cheap/jump/game by strength), otherwise notrump with a stopper, a 6-card
  suit rebid, or a second suit.
- Reopening (pass-out) seat after an overcall of our opening: takeout
  double with at most two of their suit, a 6-card suit rebid, 1NT with
  18-19 and a stopper, a second suit, or a (possibly trap) pass.
- Sandwich/balancing seat with both opponents bidding: over a raised suit,
  sound overcalls and takeout doubles; over two different suits, a double
  showing 4+ in both unbid suits, a notrump overcall with both stoppers, or
  a sound suit overcall; over a notrump response (e.g. 1C-P-1NT), sound
  overcalls and a takeout double of the opening suit.
- Responder's second call in competition: after a negative double, opener's
  rebid is passed with a minimum, invited with 10-12, and raised to game
  with 13+; natural-bid sequences reuse the uncontested continuation logic
  (except 2NT, which stays natural in competition); when partner passes
  over LHO's bid, responder competes once more with 4 trumps or a 6-card
  suit; a reopening double by partner is passed for penalty with 4+ trumps
  and 8+ HCP, otherwise advanced like a takeout double.

### Known simplifications
- No suit-quality checks on preempts; no seat/vulnerability adjustments.
- 2C is HCP-only (no playing-trick evaluation); slam moves after a positive
  go through Blackwood or direct 6NT, never a quantitative raise.
- No 2NT feature-ask over weak twos.
- No preemptive jump raises and no strong jump shifts by responder
  (opener's jump-shift rebids exist; splinter responses to majors exist).
- Splinters apply only in uncontested auctions (the same double jump in
  competition is a natural free bid).
- Jacoby 2NT rebids don't show shortness; slam machinery is limited to
  Blackwood/Gerber ace-asks and quantitative 4NT (no king-asks, cue bids,
  or grand slams), and the fallback bidder never initiates a slam.
- Raise decisions use total points as a stand-in for support points.
- Responder's game bids in notrump don't check for stoppers (except in
  competition, where a stopper in the enemy suit is required); no
  new-minor-forcing/checkback after opener's 1NT rebid.
- No cue-bid raises, Jordan 2NT, Michaels/unusual 2NT, or conventional
  defenses to 1NT (natural 6-card overcalls and responder's penalty double
  only).
- The card-play AI does not yet use bidding inferences; feeding
  `explainSaycAuction`'s per-seat constraints into the Monte Carlo card
  distributions is a natural next step.

## Tools

```sh
flutter test test/bridge/sayc_bidding_test.dart   # 180 tests, includes a
                                                  # 150-deal self-play invariant

# Choose or interpret bids from the command line:
dart run scripts/bridge_cli.dart "A2 AKJT Q32 9876" "1H pass"
dart run scripts/bridge_cli.dart "1D 1S" --describe X
dart run scripts/bridge_cli.dart "1S pass 2S pass 3S" --explain

# Self-play over random deals (reproducible from seed + index): reports
# hard failures (exceptions, illegal calls, runaway auctions, bids below
# their own advertised minimums — all held at zero) and heuristic quality
# flags (thin/missed games, bad trump fits, light slams):
dart run scripts/bridge_selfplay.dart --deals 2000 --seed 7 [--category missed-game]
```
