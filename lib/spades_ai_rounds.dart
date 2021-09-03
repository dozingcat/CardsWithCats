
import 'dart:math';

import 'package:hearts/cards/rollout.dart';
import 'package:hearts/spades/spades.dart';
import 'package:hearts/spades/spades_ai.dart';

import 'cards/card.dart';

void main() {
  final rules = SpadesRuleSet();
  final teamMatchWins = List.filled(rules.numTeams, 0);
  final rng = Random();
  final numMatchesToPlay = 100;
  int totalRounds = 0;

  for (int matchNum = 1; matchNum <= numMatchesToPlay; matchNum++) {
    print("Match #$matchNum");
    SpadesMatch match = SpadesMatch(rules, rng);
    int roundNum = 0;
    while (!match.isMatchOver()) {
      roundNum += 1;
      totalRounds += 1;
      print("Round $roundNum (total $totalRounds)");
      final round = match.currentRound;
      for (int i = 0; i < rules.numPlayers; i++) {
        print("P$i: ${descriptionWithSuitGroups(round.players[i].hand)}");
      }
      for (int i = 0; i < rules.numPlayers; i++) {
        final bidReq = BidRequest(
          rules: round.rules,
          hand: round.players[i].hand,
          scoresBeforeRound: round.initialScores,
        );
        final bid = chooseBid(bidReq);
        print("P$i bids $bid");
        round.setBidForPlayer(bid: bid, playerIndex: i);
      }
      while (!round.isOver()) {
        final card = computeCardToPlay(round, rng);
        print("P${round.currentPlayerIndex()} plays ${card.symbolString()}");
        round.playCard(card);
        if (round.currentTrick.cards.isEmpty) {
          print("P${round.previousTricks.last.winner} takes the trick");
        }
      }
      print("Scores for round $roundNum: ${round.pointsTaken()}");
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

final mcParams = MonteCarloParams(numHands: 50, rolloutsPerHand: 20);

PlayingCard computeCardToPlay(final SpadesRound round, Random rng) {
  final cardReq = CardToPlayRequest.fromRound(round);
  switch (round.currentPlayerIndex()) {
    case 0:
    case 2:
      // return chooseCardRandom(cardReq, rng);
      return chooseCardMonteCarlo(cardReq, mcParams, chooseCardRandom, rng);
      // return chooseCardToMakeBids(cardReq, rng);
    case 1:
    case 3:
      // return chooseCardRandom(cardReq, rng);
      // return chooseCardMonteCarlo(cardReq, mcParams, chooseCardToMakeBids, rng);
      return chooseCardToMakeBids(cardReq, rng);
    default:
      throw Exception("Bad player index: ${round.currentPlayerIndex()}");
  }
}
