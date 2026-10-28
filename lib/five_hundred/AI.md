# 500 AI

How the 500 AI works, what was tried while building it, and the measured
results. All code is in `five_hundred_ai.dart`; experiments use
`scripts/five_hundred_selfplay.dart`.

## Measuring

`scripts/five_hundred_selfplay.dart` plays duplicate games between two
strategies: every deal is played twice with the strategies swapping teams,
and the result is strategy A's round score differential per deal, summed over
both seatings, with a standard error. Strategies are comma separated options:

    dart run scripts/five_hundred_selfplay.dart --a=bid=sim,play=mc30 --b=bid=sim --deals=1000 --workers=8

- `bid`: `never`, `simple` (the original placeholder: 0.75 per trump, 1 per
  side ace, 2 for partner), `sim` (simulation based, below), with `minDiff`,
  `bidDeals` (default 100 here for speed; the app uses 300), `bidAuction` (attempts to deal consistently with the bids, 0
  to ignore them), `outbidPartner=1`.
- `play`: `random`, `heuristic`, `mcN` (Monte Carlo with N sampled deals),
  with `playAuction`.
- Heuristic play options `hpull`, `hsafe`, `hruff`, `h2low`; discard options
  `dvoids`, `dking`.

Heuristic-only runs take about a minute per thousand deals (most of it is
bidding simulations); Monte Carlo runs take several minutes. Keep
`--workers` at 10 or fewer.

## Architecture

- **Heuristic play** (`chooseCardHeuristic`) only looks at what the player
  can see. It's both the cheap player and the Monte Carlo rollout policy.
  - Leading: the declaring team pulls trump while unseen trumps remain
    (highest master trump, otherwise a low trump if holding two or more),
    then leads side suit masters, then the lowest card. The joker isn't led
    in no trump unless it's the only card; if it is, it's led as the suit
    with the most unseen cards.
  - Following: play low if partner is winning or we can't win. Otherwise win
    as cheaply as possible (non-trumps before trumps, lowest rank).
- **Monte Carlo play** (`chooseCardMonteCarlo`): hidden cards (other hands,
  and the discards unless we're the declarer) are dealt randomly, respecting
  hand sizes and known voids (`knownVoids`: failing to follow suit, where the
  left bower and joker belong to the trump suit; in no trump, playing the
  joker shows a void in the led suit). Each candidate play is
  tried on each deal and played out with the heuristic; the one with the best
  total team score differential wins. Leading the joker in no trump is four
  candidates, one per suit. The app uses 100 deals capped at 2 seconds.
- **Discards** (`chooseDiscards`): keep the joker, trumps, side aces, and
  kings with at least one other card in the suit; otherwise discard from the
  shortest side suits first (creating voids in a trump contract).
- **Bidding** (`chooseBid`): for each trump suit and no trump, simulate
  winning the bid with this hand (other hands and kitty dealt randomly but
  consistent with the bids so far, heuristic discards, heuristic play) to
  get a distribution of tricks taken. That gives the expected score
  differential of every possible bid. Bid the legal bid with the highest
  expectation if it's at least `minExpectedDifferential` (30), so the AI
  bids naturally and jumps straight to the contract it expects to do best
  in. Never outbid partner.
- **Auction inference** (`isHandConsistentWithBid`): a suit bid at level L
  shows at least min(L - 3, 5) trumps, and a no trump bid shows at least two
  of the aces and joker. These are about the 10th percentile of what the AI's
  own bids hold (suit bids of 7: median 5 trumps; 8: median 5; no trump:
  median 2-3 aces). Bidding simulations try up to 50 deals to satisfy them,
  then give up and use the last deal. Monte Carlo play can do the same
  (`auctionAttempts`), but it didn't help, so it's off.

Unlike Rook, a made bid scores the bid's value, not the tricks taken, so
higher contracts are worth more and underbidding loses points. That's why
the AI bids the contract with the best expectation rather than the cheapest
one that wins the auction, and why the threshold is positive: letting the
opponents have a low contract costs relatively little.

## Results

Differentials are per deal, both seatings combined, ± one standard error.

**Play and bidding vs the placeholders:**

| A vs B | Result |
|---|---|
| heuristic vs random play (placeholder bidding) | +106.4 ± 2.7 |
| sim bidding vs placeholder bidding, minDiff -100 / -50 / 0 / 30 / 60 / 100 | -4.2 / +13.0 / +38.3 / +39.8 / +33.4 / +16.2 (± 3-5) |
| mc30 vs heuristic play | +44.5 ± 7.0 |

With minDiff 30, sim bidding declared 53% of deals, at 7.0 tricks on
average, making 78%. Every suit bid it made was 7 or more: the 6 level
scores too little to be the best expectation.

**Heuristic play options**, each vs the defaults at the time:

| Change | Result | Kept |
|---|---|---|
| Don't pull trump | -81.8 ± 4.6 | pull |
| Only win with unbeatable cards (ruffing anyway) | -12.2 ± 3.2 | no |
| ... and don't ruff | -10.5 ± 3.1 vs the above | |
| Second hand low | -6.5 ± 3.2 | no |

**Discards:**

| Change | Result | Kept |
|---|---|---|
| Don't try to create voids | -6.4 ± 3.3 | no |
| Keep kings only with two or more guards | -1.3 ± 3.0 | no change |

**Bidding:**

| Change | Result | Kept |
|---|---|---|
| Deal consistently with the bids, vs ignoring them | +6.5 ± 3.0 | yes |
| Allow outbidding partner | +3.4 ± 3.1 | no (not significant) |
| 300 vs 100 simulated deals per trump suit | +7.3 ± 2.7 | yes, 300 in the app |
| minDiff 0 / 60 vs 30, mc30 play (800 deals) | +6.3 ± 5.9 / -16.9 ± 5.7 | 30 |

Timing on a Mac: a bid with 300 deals per trump suit takes about 200ms, and
a Monte Carlo play with 100 deals averages 30ms (at most about 200ms).

**Monte Carlo play:**

| Change | Result | Kept |
|---|---|---|
| Deal consistently with the bids (20 attempts), mc30 | -7.4 ± 5.4 | no |

## Ideas not yet tried

- Defender heuristics from the strategy sources: lead partner's bid suit,
  hold the joker in no trump until it sets the contract, keep guards.
- Better no trump heuristics: run long suits, lose losers early.
- Inferences from passes (a player who passed doesn't have a strong hand),
  and from partner's bid when choosing discards (keep partner's suit).
- Bidding simulations with Monte Carlo play, or a correction for how much
  better Monte Carlo play does than the heuristic it simulates with.
- Match score awareness: bid more or less aggressively near 500 or -500,
  and tactical bids to push the opponents up.
- Misère bids.

Published strategy is thin. The most useful sources were Bryce Francis's
play500.com (Australian, mixed with a bidding convention system that the AI
ignores) and Andrew Blucher's "How to play 500" (Monash, archived). Their
main points: count sure tricks plus one for the kitty and one for partner;
never discard trumps and void side suits; draw trumps from the top; second
hand low and third hand high on defence; hold the joker in no trump. The
first three are what the AI does (pulling trump and creating voids both
measured as large gains); second hand low measured as a loss here.
