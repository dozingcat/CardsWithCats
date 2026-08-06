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

Timing on random deals: ~1ms at 6 tricks remaining, ~25ms at 8, ~200ms at
9, seconds beyond. The default preroll boundary of 8 keeps worst-case
per-play cost well inside an interactive budget.

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
| MCDD (rounds=10, dd=7, bid) vs old AI | 100 | TBD_HEADLINE |
| MCDD without bidding inference vs with | 100 | TBD_BID |
| MCDD rounds=20/dd=8 vs rounds=10/dd=7 | 60 | TBD_SCALING |

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

### The reported blunder

`scripts/k432_check.dart` reconstructs the reported bug: a defender
holding K432 of spades under dummy's AQ5. The old AI rated the king lead
within ~11 points of its best option — noise level, so on some seeds it
led the king. MCDD rates the king lead ~110 points worse than the best
play and never chooses it; exact ties break toward the lowest card, so it
also never wastes an honor between equals.

## App configuration

`computeCard` in `bridge_ui.dart` uses TBD_APP_CONFIG.

## Known limitations / future ideas

- Double-dummy defenders "see" declarer's cards within each sampled deal
  (standard for this architecture); genuinely deceptive plays are neither
  made nor anticipated.
- The solver could be pushed 1-2 tricks deeper with stronger move
  ordering (winner ordering at lead nodes, quick-trick bounds); that
  would let the preroll boundary move later or rounds increase.
- Deal sampling is rejection-based; heavily constrained auctions
  occasionally fall back to best-effort samples. Weighted dealing (deal
  honors to fit HCP windows directly) would raise the hit rate.
- Opening leads are made before dummy is visible with no bidding-free
  information; lead conventions live in the heuristic policy, not MCDD
  candidates.
