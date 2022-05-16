import 'dart:math';

import 'package:args/args.dart';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/rollout.dart';
import 'package:cards_with_cats/hearts/hearts.dart';
import 'package:cards_with_cats/hearts/hearts_ai.dart' as hearts_ai;
import 'package:cards_with_cats/spades/spades.dart';
import 'package:cards_with_cats/spades/spades_ai.dart' as spades_ai;


void main(List<String> args) {
  final parser = ArgParser()
        ..addOption("seed", help: "Random number generator seed", defaultsTo: "17")
        ..addOption("game", help: "'hearts' or 'spades'", defaultsTo: "hearts", allowed: ["hearts", "spades"]);
  final parsedArgs = parser.parse(args);

  final seed = int.parse(parsedArgs["seed"]);
  Random rng = Random(seed);

  final game = parsedArgs["game"];
  final results = (game == "spades") ? runSpades(rng, 5) : runHearts(rng, 5);

  double totalSeconds = 0.0;
  int totalCards = 0;
  int totalRollouts = 0;
  int totalRounds = 0;
  for (final r in results) {
    totalSeconds += r.elapsedMillis / 1000.0;
    totalCards += r.numRolloutCardsPlayed;
    totalRollouts += r.numRollouts;
    totalRounds += r.numRounds;
  }
  double cardsPerSecond = totalCards / totalSeconds;
  double rolloutsPerSecond = totalRollouts / totalSeconds;
  double roundsPerSecond = totalRounds / totalSeconds;
  print("");
  print("Cards/sec: ${cardsPerSecond.toStringAsFixed(0)}");
  print("Rollouts/sec: ${rolloutsPerSecond.toStringAsFixed(0)}");
  print("Rounds/sec: ${roundsPerSecond.toStringAsFixed(1)}");
}

List<MonteCarloResult> runHearts(Random rng, int iterations) {
  HeartsRound round = HeartsRound.deal(HeartsRuleSet(), List.filled(4, 0), 0, rng);
  for (int i = 0; i < 4; i++) {
    print(descriptionWithSuitGroups(round.players[i].hand));
  }
  // Play first trick with 2C lead.
  for (int i = 0; i < 4; i++) {
    final req = hearts_ai.CardToPlayRequest.fromRound(round);
    final card = hearts_ai.chooseCardAvoidingPoints(req, rng);
    round.playCard(card);
  }
  print("First round: ${round.previousTricks[0].cards}");
  int p = round.currentPlayerIndex();
  print("Computing play for P$p: ${descriptionWithSuitGroups(round.players[p].hand)}");
  final req = hearts_ai.CardToPlayRequest.fromRound(round);
  final mcParams = MonteCarloParams(maxRounds: 100000, rolloutsPerRound: 20, maxTimeMillis: 2000);
  final results = <MonteCarloResult>[];
  final seeds = List.generate(iterations, (int _) => rng.nextInt(1 << 32));
  for (int i = 0; i < iterations; i++) {
    final result = hearts_ai.chooseCardMonteCarlo(req, mcParams, hearts_ai.chooseCardAvoidingPoints, Random(seeds[i]));
    print(result);
    results.add(result);
  }
  return results;
}

List<MonteCarloResult> runSpades(Random rng, int iterations) {
  final rules = SpadesRuleSet();
  SpadesRound round = SpadesRound.deal(SpadesRuleSet(), List.filled(2, 0), 0, rng);
  for (int i = 0; i < 4; i++) {
    print(descriptionWithSuitGroups(round.players[i].hand));
  }
  final otherBids = <int>[];
  for (int p = 0; p < 4; p++) {
    int pnum = (round.dealer + 1 + p) % rules.numPlayers;
    final bidReq = spades_ai.BidRequest(
      rules: round.rules,
      scoresBeforeRound: round.initialScores,
      otherBids: otherBids,
      hand: round.players[pnum].hand,
    );
    final bid = spades_ai.chooseBid(bidReq);
    otherBids.add(bid);
    print("P$pnum bids $bid");
    round.setBidForPlayer(bid: bid, playerIndex: pnum);
  }

  int p = round.currentPlayerIndex();
  print("Computing play for P$p: ${descriptionWithSuitGroups(round.players[p].hand)}");
  final req = spades_ai.CardToPlayRequest.fromRound(round);
  final mcParams = MonteCarloParams(maxRounds: 100000, rolloutsPerRound: 20, maxTimeMillis: 2000);
  final results = <MonteCarloResult>[];
  final seeds = List.generate(iterations, (int _) => rng.nextInt(1 << 32));
  for (int i = 0; i < iterations; i++) {
    final result = spades_ai.chooseCardMonteCarlo(req, mcParams, spades_ai.chooseCardRandom, Random(seeds[i]));
    print(result);
    results.add(result);
  }
  return results;
}