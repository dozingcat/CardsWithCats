# Bridge card-play AI

How the play AI works, what was tried while improving it, and the measured
results. The bidding engine is documented separately in `sayc/README.md`.

## Architecture

Card play is Monte Carlo over hidden information, in three layers:

1. **Deal sampling** (`BiddingDealFilter`, `possibleRound` in
   `bridge_ai.dart`): unknown hands are dealt randomly, consistent with
   basic play constraints (suit voids shown by discards, seen cards) *and*
   with the auction. `explainSaycAuction` turns every call each seat made
   into accumulated constraints (HCP range, suit lengths, balance);
   sampled deals are rejection-tested against them, reconstructing each
   hidden seat's original 13 cards (current sample plus cards already
   played). After 100 failed attempts the most-satisfying sample is used.
2. **Candidate reduction** (`cardsToConsiderPlaying`): cards that are
   interchangeable for trick-taking purposes (touching ranks, or ranks
   whose gaps have all been played) evaluate as a single candidate, the
   cheapest of the group.
3. **Evaluation** (`chooseCardMonteCarloDD`): each candidate play is tried
   on each sampled deal; the position is played forward with the cheap
   heuristic policy until at most K tricks remain (default 8), and the
   remainder is solved *exactly* with the double-dummy solver. The
   declarer's total tricks convert to a contract score, averaged across
   deals. Exact equity ties break toward the lowest card.

### The double-dummy solver (`dd_solver.dart`)

Bitmask hands; zero-window alpha-beta with a binary search over the trick
target; transposition table at trick boundaries storing (lower, upper)
bound pairs plus the best move for ordering; equivalence-class move
generation; an exact last-seat reduction (win as cheaply as possible, duck
with the lowest, or unblock with the highest). Validated by fuzzing
against an unpruned reference solver (`DDReferenceSolver`).

Timing on random deals: ~1ms at 6 tricks remaining, ~12ms at 8, ~34ms at
9, ~1-7s at 10-12 (desktop M4, JIT). Three throughput features matter in
MCDD use: solves of the same sampled deal share a transposition table
(candidates converge into the same endgames), quick-trick bounds prune
cash-out positions without search (5x at depth 9+), and
`solveWithNodeLimit` abandons pathological positions so a latency budget
is a guarantee, not a hope (the sampled deal is then discarded to avoid
biasing equities).

### The heuristic policy (`heuristic_play.dart`)

A rule-based policy covering standard technique: sequence and fourth-best
leads (no unsupported honor leads, no underleading aces against suit
contracts), second hand low with honor covers, third hand high with
lowest-of-equals (using the visible dummy to judge when partner's card
holds), fourth hand wins as cheaply as possible, ruffs, guarded-honor
discards, declarer trump drawing and master cashing. It is the preroll
policy for MCDD and is available standalone as the `heuristic` strategy.

## The comparison harness

`scripts/bridge_play_compare.dart` plays duplicate boards: each board is
bid once by the SAYC engine, then played in two rooms with the strategies'
sides swapped, and scored by IMPs exactly as a team-of-four match. Both
rooms share RNG seeds (common random numbers), so identical strategies
score exactly zero and shared noise cancels. Strategy specs are documented
in `play_strategies.dart`:

    dart run scripts/bridge_play_compare.dart --deals 100 \
        mcdd:rounds=10:dd=7 mc:rollout=random:rounds=20:rpr=10

## What was tried, and what it measured

All numbers are IMPs per board with standard errors, seed 42 unless noted.
"Old AI" is what the app shipped with: `chooseCardMonteCarlo` with
uniformly random rollouts (20 deals x 10 rollouts) and no bidding
inference.

| Comparison | Boards | IMPs/board |
|---|---|---|
| maxtricks (legacy positional policy) vs random play | 20 | +3.9 +/- 1.3 |
| old AI vs pure random play | 20 | +10.3 +/- 0.8 |
| MC with maxtricks rollouts vs old AI | 100 | +1.38 +/- 0.50 |
| heuristic policy standalone vs maxtricks | 100 | +2.32 +/- 0.61 |
| MC with *deterministic* heuristic rollouts vs old AI | 100 | **-1.37 +/- 0.56** |
| ... with eps=0.2 noise | 100 | +0.40 +/- 0.51 |
| **MCDD (rounds=10, dd=7, bid) vs old AI** | 100 | **+2.28 +/- 0.53** |
| MCDD vs MC with maxtricks rollouts (seed 42; pooled with the seed-43 run below: ~+0.8 +/- 0.3) | 100 | +1.58 +/- 0.48 |
| MCDD without bidding inference vs with | 100 | -0.66 +/- 0.48 |
| maxtricks MC with bidding inference vs without | 100 | -0.03 +/- 0.49 |
| MCDD rounds=20/dd=8 vs rounds=10/dd=7 (~8x compute) | 60 | +0.25 +/- 0.59 |
| MCDD dd=6 vs dd=7, equal rounds, 300 boards seed 43 | 300 | **-0.73 +/- 0.27** |
| MCDD dd=7 vs maxtricks MC, seed 43 | 200 | +0.47 +/- 0.33 |
| MCDD dd=6 vs maxtricks MC, seed 43 | 200 | -0.11 +/- 0.34 |

Two negative results shaped the final design:

- **Better rollout policies barely help, and deterministic ones hurt.**
  A deterministic rollout policy evaluates one biased line per sampled
  deal (and makes rollouts-per-round pure waste); adding noise repairs the
  bias but the net gain over random rollouts was within noise at 7x the
  cost. The deeper problem is *follow-up competence bias*: a candidate is
  credited only with what the rollout policy can realize afterwards, so
  plays whose payoff requires a correct continuation (finesses,
  establishment, endplays) are systematically under-valued no matter how
  good the policy is on average.
- **Exact evaluation is what actually fixes it.** Solving the endgame
  double-dummy rewards the *potential* of a position rather than what a
  mediocre policy extracts from it. This is the GIB-style architecture.

Bid-aware sampling and exact evaluation compound rather than add:
attached to the old rollout-based MC, bidding inference measured exactly
zero (-0.03 +/- 0.49), while inside MCDD it is worth ~+0.7 — sharper
deal samples only pay off when the evaluator is accurate enough to
exploit the difference.

Scaling is steeply diminishing: quadrupling sampled deals *and* moving
the solve boundary a trick earlier (~8x compute) added +0.25 +/- 0.59.
Most of the value is in the architecture, not the knob settings, so the
app spends its budget on more sampled deals at the cheap dd=7 boundary.

### The reported blunder

`scripts/k432_check.dart` reconstructs the reported bug: a defender
holding K432 of spades under dummy's AQ5. The old AI rated the king lead
within ~11 points of its best option — noise level, so on some seeds it
led the king. MCDD rates the king lead ~110 points worse than the best
play and never chooses it; exact ties break toward the lowest card, so it
also never wastes an honor between equals.

## App configuration

`computeCard` in `bridge_ui.dart` runs `chooseCardMonteCarloDD` with up
to 50 sampled deals, double-dummy solving from 7 tricks out, and a 2.2s
time budget (the old Monte Carlo remains as a defensive fallback). It
beat the previously shipped configuration by +2.83 +/- 1.00 IMPs/board
(12 boards, 8 wins 1 loss 3 ties) and averages ~150ms per play (max
~2.2s) on a desktop M4. The budget is enforced between candidates as
well as between sampled deals, so slow devices degrade to fewer sampled
deals rather than longer thinks; if no sampled deal completes at all,
the move falls back to the heuristic policy.

dd=6 was tried as a ~4x cheaper alternative and initially looked like a
wash in 100-board comparisons, but a 300-board head-to-head measured it
-0.73 +/- 0.27 behind dd=7 — it gives back most of MCDD's edge over a
maxtricks-rollout MC (dd=6 measured dead even with maxtricks on 200
boards; dd=7 measured +0.5 to +0.8 pooled across seeds). Moral: with
~+/-0.5-IMP error bars at 100 boards, differences under ~1 IMP need
200-300+ boards to resolve. If a low-end device needs a cheaper config,
cut `maxRounds` before cutting `ddTricksLimit`.

## The honor-waste guard

Double-dummy evaluation is blind to the main real-world cost of leading
an unsupported high honor: every sampled declarer already knows where it
is, so the lead is rarely punished and sometimes shows a small spurious
edge that a non-clairvoyant declarer would never realize (the classic
GIB-family artifact — `scripts/lead_scan.dart` measured unsupported K/Q
leads on ~7% of defender leads, several into a higher visible dummy
honor). When the equity-best play is a lead of an effectively
unsupported K or Q with a lower card available, MCDD instead plays the
best-scoring candidate that doesn't match that pattern, unless the honor
is decisively better: by more than a margin (5 points/deal for declarer,
18 for defenders, whose honor locations are the ones DD leaks) AND by a
statistically significant paired difference across the sampled deals.
Genuine coups clear that bar (verified examples: cashing a king before
dummy's ace gets ruffed; leading Q from QT65 to pin dummy's singleton
jack) and are still made.

Calibration was delicate and measured (200 boards each):
- Broadly preferring the heuristic's card on any near-tie: -0.86 IMPs/bd.
- Guard deferring to the heuristic's (cross-suit) lead: -0.32.
- Guard deferring to low card of the same suit: -0.10 +/- 0.16, cutting
  flagged unsupported-honor leads ~75% at 10 sampled deals, ~40% at 50.
- Guard deferring to the next-best-scoring non-artifact candidate:
  **+0.05 +/- 0.20** (exactly free), cutting flagged leads 100% at 10
  sampled deals and ~67% at 50 (the survivors carry decisive DD edges
  over every alternative). Shipped.

Lesson: suppress only the exact artifact pattern and fall back along the
measured-equity ranking, not to conventional play; every deferral to the
heuristic's judgment costs measurable equity.

## Known limitations / future ideas

- Double-dummy defenders "see" declarer's cards within each sampled deal
  (standard for this architecture); genuinely deceptive plays are neither
  made nor anticipated. The honor-waste guard above patches the most
  visible symptom; second-hand and discard honor waste are not guarded.
- The solver could be pushed further with partition search or
  finer-grained quick-trick bounds (partner entries, ruff counting);
  that would let the preroll boundary move later.
- Deal sampling is rejection-based; heavily constrained auctions
  occasionally fall back to best-effort samples. Weighted dealing (deal
  honors to fit HCP windows directly) would raise the hit rate.
- Opening leads are made before dummy is visible with no bidding-free
  information; lead conventions live in the heuristic policy, not MCDD
  candidates.
