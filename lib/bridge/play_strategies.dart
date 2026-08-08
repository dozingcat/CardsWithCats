/// Named card-play strategies for the bridge AI, used by the comparison
/// harness (scripts/bridge_play_compare.dart) and the app.
///
/// A strategy spec is a name optionally followed by colon-separated options:
///   random                     uniform random legal play
///   maxtricks                  cheap positional heuristic (legacy rollout fn)
///   heuristic                  rule-based policy (lib/bridge/heuristic_play)
///   mc                         Monte Carlo; options:
///     rollout=random|maxtricks|heuristic   rollout policy (default random)
///     eps=X                      probability of a random card per rollout
///                                play, to de-bias deterministic policies
///     rounds=N                   sampled deals (default 20)
///     rpr=N                      rollouts per sampled deal (default 10)
///     ms=N                       time budget in milliseconds (default none)
///     bid                        constrain sampled deals by the auction
///   mcdd                       Monte Carlo with exact endgame evaluation:
///                              heuristic preroll, then double-dummy solve.
///     rounds=N, ms=N, bid/nobid  as for mc (bid defaults ON here)
///     dd=K                       tricks left at which to solve (default 8)
/// Example: "mc:rollout=heuristic:eps=0.1:rounds=30:rpr=5:ms=2500"
library;

import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';

import '../cards/rollout.dart';
import 'bridge_ai.dart';
import 'heuristic_play.dart';

class PlayStrategy {
  final String name;
  final ChooseCardFn chooseCard;

  PlayStrategy(this.name, this.chooseCard);
}

ChooseCardFn _rolloutFnNamed(String name, double epsilon) {
  ChooseCardFn base;
  switch (name) {
    case "random":
      base = chooseCardRandom;
    case "maxtricks":
      base = chooseCardToMaximizeTricks;
    case "heuristic":
      base = chooseCardHeuristic;
    default:
      throw ArgumentError("Unknown rollout policy: $name");
  }
  if (epsilon <= 0) return base;
  return (req, rng) => rng.nextDouble() < epsilon
      ? chooseCardRandom(req, rng)
      : base(req, rng);
}

PlayStrategy makeStrategy(String spec) {
  final parts = spec.split(":");
  final name = parts[0];
  final options = <String, String>{};
  for (final p in parts.skip(1)) {
    final eq = p.indexOf("=");
    if (eq < 0) {
      options[p] = "";
    } else {
      options[p.substring(0, eq)] = p.substring(eq + 1);
    }
  }
  switch (name) {
    case "random":
      return PlayStrategy(spec, chooseCardRandom);
    case "maxtricks":
      return PlayStrategy(spec, chooseCardToMaximizeTricks);
    case "heuristic":
      return PlayStrategy(spec, chooseCardHeuristic);
    case "mc":
      final rolloutFn = _rolloutFnNamed(options["rollout"] ?? "random",
          double.parse(options["eps"] ?? "0"));
      final mcParams = MonteCarloParams(
        maxRounds: int.parse(options["rounds"] ?? "20"),
        rolloutsPerRound: int.parse(options["rpr"] ?? "10"),
        maxTimeMillis:
            options.containsKey("ms") ? int.parse(options["ms"]!) : null,
      );
      final useBid = options.containsKey("bid");
      PlayingCard choose(CardToPlayRequest req, Random rng) {
        return chooseCardMonteCarlo(req, mcParams, rolloutFn, rng,
                useBiddingInference: useBid)
            .bestCard;
      }
      return PlayStrategy(spec, choose);
    case "mcdd":
      final maxRounds = int.parse(options["rounds"] ?? "20");
      final ddLimit = int.parse(options["dd"] ?? "8");
      final ms = options.containsKey("ms") ? int.parse(options["ms"]!) : null;
      final useBid = !options.containsKey("nobid");
      PlayingCard choose(CardToPlayRequest req, Random rng) {
        return chooseCardMonteCarloDD(req, rng,
                maxRounds: maxRounds,
                ddTricksLimit: ddLimit,
                maxTimeMillis: ms,
                useBiddingInference: useBid)
            .bestCard;
      }
      return PlayStrategy(spec, choose);
    default:
      throw ArgumentError("Unknown strategy: $name");
  }
}
