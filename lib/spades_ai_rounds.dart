import 'dart:math';

import 'package:cards_with_cats/cards/rollout.dart';
import 'package:cards_with_cats/spades/spades.dart';
import 'package:cards_with_cats/spades/spades_ai.dart';

import 'cards/card.dart';

/*
Results of AIs playing against each other for 1000 matches.
20 rounds, 20 rollouts per hand for MC.
- chooseCardToMakeBids beats chooseCardRandom: 990-10
- MonteCarlo(random) beats chooseCardToMakeBids: 806-194.
- MonteCarlo(random) beats MonteCarlo(makeBids): 537-463
- MonteCarlo(random) with 50 rounds/50 rollouts beats 20/20: 534-466
- MonteCarlo(random) with 50 rounds/50 rollouts "loses" to 30/30: 496-504

So random meta-strategy for rollouts seem to be better than "smart",
and 30 rounds/30 rollouts is good enough.
 */

void main() {
  final rules = SpadesRuleSet();
  final teamMatchWins = List.filled(rules.numTeams, 0);
  final rng = Random();
  const numMatchesToPlay = 250;
  int totalRounds = 0;

  for (int matchNum = 1; matchNum <= numMatchesToPlay; matchNum++) {
    print("Match #$matchNum");
    SpadesMatch match = SpadesMatch(rules, rng);
    int roundNum = 0;
    while (!match.isMatchOver()) {
      roundNum += 1;
      totalRounds += 1;
      final round = match.currentRound;
      print("Round $roundNum (total $totalRounds), P${round.dealer} deals");
      for (int i = 0; i < rules.numPlayers; i++) {
        print("P$i: ${descriptionWithSuitGroups(round.players[i].hand)}");
      }
      List<int> otherBids = [];
      for (int notPlayerIndex = 0; notPlayerIndex < rules.numPlayers; notPlayerIndex++) {
        int pnum = (round.dealer + 1 + notPlayerIndex) % rules.numPlayers;
        final bidReq = BidRequest(
          rules: round.rules,
          scoresBeforeRound: round.initialScores,
          otherBids: otherBids,
          hand: round.players[pnum].hand,
        );
        final bid = chooseBid(bidReq);
        otherBids.add(bid);
        print("P$pnum bids $bid");
        round.setBidForPlayer(bid: bid, playerIndex: pnum);
      }
      while (!round.isOver()) {
        final result = computeCardToPlay(round, rng);
        print(
            "P${round.currentPlayerIndex()} plays ${result.bestCard.symbolString()} (${result.toString()})");
        round.playCard(result.bestCard);
        if (round.currentTrick.cards.isEmpty) {
          print("P${round.previousTricks.last.winner} takes the trick");
        }
      }
      print("Scores for round $roundNum: ${round.pointsTaken().map((s) => s.totalRoundPoints)}");
      match.finishRound();
      print("Scores for match: ${match.scores}");
    }
    print("Match over");
    final winner = match.winningTeam();
    print("Team $winner wins");
    teamMatchWins[winner!] += 1;
    print("Total wins: $teamMatchWins");
    print("====================================");
  }
}

final mcParams20 = MonteCarloParams(maxRounds: 20, rolloutsPerRound: 20);
final mcParams30 = MonteCarloParams(maxRounds: 30, rolloutsPerRound: 30);
final mcParams50 = MonteCarloParams(maxRounds: 50, rolloutsPerRound: 50);

ChooseCardFn makeMixedRandomMakeBidsFn(double randomProb) {
  return (req, rng) =>
      rng.nextDouble() < randomProb ? chooseCardToMakeBids(req, rng) : chooseCardRandom(req, rng);
}

MonteCarloResult computeCardToPlay(final SpadesRound round, Random rng) {
  final cardReq = CardToPlayRequest.fromRound(round);
  switch (round.currentPlayerIndex()) {
    case 0:
    case 2:
      // return MonteCarloResult.rolloutNotNeeded(bestCard: chooseCardToMakeBids(cardReq, rng));
      // return MonteCarloResult.rolloutNotNeeded(bestCard: chooseCardRandom(cardReq, rng));
      // return chooseCardMonteCarlo(cardReq, mcParams20, chooseCardToMakeBids, rng);
      return chooseCardMonteCarlo(cardReq, mcParams30, chooseCardRandom, rng);
    case 1:
    case 3:
      return chooseCardMonteCarlo(cardReq, mcParams50, chooseCardRandom, rng);
      // return MonteCarloResult.rolloutNotNeeded(bestCard: chooseCardToMakeBids(cardReq, rng));
    default:
      throw Exception("Bad player index: ${round.currentPlayerIndex()}");
  }
}
