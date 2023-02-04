import 'dart:math';

import 'package:cards_with_cats/cards/rollout.dart';
import 'package:cards_with_cats/ohhell/ohhell.dart';
import 'package:cards_with_cats/ohhell/ohhell_ai.dart';

import 'cards/card.dart';

void main() {
  final rules = OhHellRuleSet();
  final victoryPoints = List.filled(rules.numPlayers, 0);
  final rng = Random();
  const numMatchesToPlay = 1;
  int totalRounds = 0;

  for (int matchNum = 1; matchNum <= numMatchesToPlay; matchNum++) {
    print("Match #$matchNum");
    OhHellMatch match = OhHellMatch(rules, rng);
    int roundNum = 0;
    while (!match.isMatchOver()) {
      roundNum += 1;
      totalRounds += 1;
      final round = match.currentRound;
      print("Round $roundNum (total $totalRounds)");
      print("Trump card is ${round.trumpCard.symbolString()}");
      for (int i = 0; i < rules.numPlayers; i++) {
        print("P$i: ${descriptionWithSuitGroups(round.players[i].hand)}");
      }
      List<int> otherBids = [];
      for (int notPlayerIndex = 0; notPlayerIndex < rules.numPlayers; notPlayerIndex++) {
        int pnum = (round.dealer + 1 + notPlayerIndex) % rules.numPlayers;
        final bidReq = BidRequest(
          rules: round.rules,
          scoresBeforeRound: round.initialScores,
          trumpCard: round.trumpCard,
          otherBids: otherBids,
          hand: round.players[pnum].hand,
        );
        final bid = chooseBid(bidReq, rng);
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
    final vp = getVictoryPoints(match);
    print("Victory points for match: $vp");
    for (int i = 0; i < rules.numPlayers; i++) {
      victoryPoints[i] += vp[i];
    }
    print("Total victory points: $victoryPoints");
    print("====================================");
  }
}

MonteCarloResult computeCardToPlay(final OhHellRound round, Random rng) {
  final req = CardToPlayRequest.fromRound(round);
  final card = chooseCardRandom(req, rng);
  return MonteCarloResult.rolloutNotNeeded(bestCard: card);
  /*
  switch (round.currentPlayerIndex()) {
    case 0:
    case 2:
    // return MonteCarloResult.rolloutNotNeeded(bestCard: chooseCardToMakeBids(cardReq, rng));
    // return MonteCarloResult.rolloutNotNeeded(bestCard: chooseCardRandom(cardReq, rng));
    // return chooseCardMonteCarlo(cardReq, mcParams20, chooseCardToMakeBids, rng);
      return chooseCardRandom(cardReq, rng);
    case 1:
    case 3:
      return chooseCardMonteCarlo(cardReq, mcParams30, chooseCardRandom, rng);
  // return MonteCarloResult.rolloutNotNeeded(bestCard: chooseCardToMakeBids(cardReq, rng));
    default:
      throw Exception("Bad player index: ${round.currentPlayerIndex()}");
  }
   */
}

List<int> getVictoryPoints(OhHellMatch match) {
  final winners = match.winningPlayers();
  return List.generate(
      match.rules.numPlayers, (i) => winners.contains(i) ? 12 ~/ winners.length : 0);
}
