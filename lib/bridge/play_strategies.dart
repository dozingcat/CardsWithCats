/// Named card-play strategies for the bridge AI, used by the comparison
/// harness (scripts/bridge_play_compare.dart) and the app.
///
/// A strategy spec is a name optionally followed by colon-separated options:
///   random                     uniform random legal play
///   maxtricks                  cheap positional heuristic (legacy rollout fn)
///   mc                         Monte Carlo; options:
///     rollout=random|maxtricks   policy used inside rollouts (default random)
///     rounds=N                   sampled deals (default 20)
///     rpr=N                      rollouts per sampled deal (default 10)
///     ms=N                       time budget in milliseconds (default none)
/// Example: "mc:rollout=maxtricks:rounds=30:rpr=5:ms=2500"
library;

import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';

import '../cards/rollout.dart';
import 'bridge_ai.dart';

class PlayStrategy {
  final String name;
  final ChooseCardFn chooseCard;

  PlayStrategy(this.name, this.chooseCard);
}

ChooseCardFn _rolloutFnNamed(String name) {
  switch (name) {
    case "random":
      return chooseCardRandom;
    case "maxtricks":
      return chooseCardToMaximizeTricks;
    default:
      throw ArgumentError("Unknown rollout policy: $name");
  }
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
    case "mc":
      final rolloutFn = _rolloutFnNamed(options["rollout"] ?? "random");
      final mcParams = MonteCarloParams(
        maxRounds: int.parse(options["rounds"] ?? "20"),
        rolloutsPerRound: int.parse(options["rpr"] ?? "10"),
        maxTimeMillis:
            options.containsKey("ms") ? int.parse(options["ms"]!) : null,
      );
      PlayingCard choose(CardToPlayRequest req, Random rng) {
        return chooseCardMonteCarlo(req, mcParams, rolloutFn, rng).bestCard;
      }
      return PlayStrategy(spec, choose);
    default:
      throw ArgumentError("Unknown strategy: $name");
  }
}
