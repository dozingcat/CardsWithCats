# Rook AI

How the Rook AI works, what was tried while building it, and the measured
results. All code is in `rook_ai.dart`; experiments use
`scripts/rook_selfplay.dart`.

## Measuring

`scripts/rook_selfplay.dart` plays duplicate games between two strategies:
every deal is played twice with the strategies swapping teams, and the
result is strategy A's round score differential per deal, summed over both
seatings, with a standard error. Strategies are comma separated options:

    dart run scripts/rook_selfplay.dart --a=bid=sim,play=mc30 --b=bid=sim --deals=500 --workers=8

- `bid`: `never`, `min` (bid 70 if nobody has bid, otherwise pass), `sim`
  (simulation based, below), with `minDiff`, `bidDeals`, `partnerBonus`,
  `outbidMargin`.
- `play`: `random`, `heuristic`, `mcN` (Monte Carlo with N sampled deals).
- Heuristic play options `hjoker`, `hpull`, `hsmear`, `hsafe`, `hmasters`,
  `hrisky`; discard options `dpoints`, `dace`, `dvoids`, `dhigh`.
- `--noPointDiscards` uses the house rule that counters can't be discarded.

Heuristic-only runs take a few seconds per thousand deals; Monte Carlo runs
take minutes. Keep `--workers` at 10 or fewer.

## Architecture

- **Heuristic play** (`chooseCardHeuristic`) only looks at what the player
  can see. It's both the cheap player and the Monte Carlo rollout policy.
  - Leading: the declaring team pulls trump while unseen trumps remain
    (master trump if held, otherwise a low trump if holding two or more),
    then leads side suit masters (preferring counters), then the lowest
    value card.
  - Partner winning: smear the biggest counter if partner's card can't be
    beaten (or we're last), otherwise a 5 if we have one.
  - Otherwise: win as cheaply as possible if the trick has points or we're
    last (with the most points when last), use the Rook to capture 10+
    points, else dump the lowest value card.
- **Monte Carlo play** (`chooseCardMonteCarlo`): hidden cards (other hands,
  and the nest unless we're the declarer) are dealt randomly, respecting
  hand sizes and known voids (`knownVoids`: failing to follow suit with
  anything but the Rook; since the Rook is a trump, a player who failed to
  follow a trump lead can't hold it). Each legal card is tried on each deal
  and played out with the heuristic; the card with the best total team
  score differential wins. The app uses 100 deals capped at 2 seconds.
- **Discards and trump** (`chooseDiscardsAndTrump`): trump is the suit with
  the best length plus high card score. Discards keep trumps and side aces,
  empty short side suits, and mildly prefer discarding counters.
- **Bidding** (`chooseBid`): simulate winning the bid with this hand
  (random other hands and nest, heuristic discards, heuristic play) to get a
  distribution of points taken, then find the highest bid whose expected
  score differential is at least `minExpectedDifferential` (-70). Bid the
  next increment if it's within that limit; never outbid partner.

Because making the bid scores the points taken, not the bid, a higher bid
never helps by itself: it only wins the auction (nest and trump choice) at
the cost of a bigger loss when set. So the threshold is really "how much
worse than average can declaring be before letting the opponents declare is
better", and since the declaring team averages about 100 of the 120 points
in self-play, it's strongly negative.

## Results

Differentials are per deal, both seatings combined, ± one standard error.

**Play** (both sides bid with `min`):

| A vs B | Result |
|---|---|
| heuristic vs random | +90.0 ± 2.0 |
| mc30 vs heuristic | +34.1 ± 4.0 |
| mc30 vs heuristic, with `sim` bidding | +44.5 ± 5.5 |
| mc30 vs heuristic, no point discards | +37.3 ± 5.6 |
| mc100 vs mc30, with `sim` bidding | +4.6 ± 6.2 (not significant) |

**Heuristic play options**, each vs the defaults at the time:

| Change | Result | Kept |
|---|---|---|
| Don't pull trump | -17.0 ± 1.4 | pull |
| Don't smear to partner | -14.9 ± 0.9 | smear |
| Rook captures at 0 / 5 / 20 points (vs 10) | -11.7 / -0.3 / -4.0 | 10 |
| Only win with cards that can't be beaten | -5.0 ± 0.6 | no |
| Lead side masters before pulling trump | -9.4 ± 1.0 | no |
| Smear a 5 when partner might lose the trick | +1.4 ± 0.4 | yes |
| Count the nest in the last trick | 0 (every player has one card) | no |

**Discards** (official rules):

| Change | Result | Kept |
|---|---|---|
| Neutral about discarding counters (vs keeping them) | +22.2 ± 1.1 | |
| Prefer discarding counters (-300) | +24.7 ± 1.2 | yes |
| ... and don't protect side aces | -10.7 vs the above | no |
| Don't try to create voids | -2.8 ± 0.7 | no |
| Trump by length only / double high card weight | +0.8 / -1.9 | no change |
| Choose among discard candidates by simulation (40 / 100 deals) | +1.3 ± 1.1 / +0.9 ± 1.0 | no, removed |

Burying counters works because the declaring team usually wins the last
trick and takes the nest.

**Bidding threshold** (`minDiff`, `sim` vs `sim`, heuristic play unless
noted):

| A vs B | Result |
|---|---|
| sim vs min | +59 to +62 for minDiff -40 to 0 |
| -20 vs 0 | +10.0 ± 2.0 |
| -40 vs -20 | +7.6 ± 2.2 |
| -60 vs -40 | +11.4 ± 2.6 |
| -80 vs -60 | +0.8 ± 3.0 |
| -100 vs -60 | -13.0 ± 3.6 |
| -60 vs -40, no point discards | +6.6 ± 2.5 |
| -80 vs -60, no point discards | +0.8 ± 2.9 |
| -60 vs -40, mc30 play | +9.7 ± 4.1 |
| -80 vs -60, mc30 play | +8.6 ± 4.6 |
| partner bid bonus 20 / 40 | +1.3 ± 2.9 / -13.0 ± 3.6 (same as a lower threshold) |
| outbid partner with a 15 / 5 point margin | -3.6 ± 2.3 / -16.5 ± 2.7 |

The default is -70: -60 is clearly better than -40, and with Monte Carlo
play slightly more aggressive looked better. In AI-vs-AI auctions this
pushes winning bids to about 95-100 with 60-75% made.

## Ideas not yet tried

- Use the auction when sampling hidden hands for Monte Carlo play (bidders
  hold strong hands), as the bridge AI does.
- Defenders leading 5s or low cards in suits the declarer is likely void
  in, to force out trumps (suggested by strategy sources).
- Bidding with Monte Carlo play in the simulations, or a fast evaluation
  formula fit to the simulation results.
- Match score awareness (bid more or less aggressively near 300).

Published strategy for this exact game (41 cards, Rook high, 120 points) is
sparse; most online advice is for the 180-point game with 1s and a low
Rook. The ideas that do carry over (pull trump, smear counters to partner,
bury counters when you expect the last trick, create voids) all tested as
improvements here.
