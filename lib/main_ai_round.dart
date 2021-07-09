
import 'dart:math';

import 'package:hearts/cards/rollout.dart';
import 'package:hearts/hearts/hearts.dart';
import 'package:hearts/hearts/hearts_ai.dart';

import 'cards/card.dart';

void main() {
  final rules = HeartsRuleSet();
  final victoryPoints = List.filled(rules.numPlayers, 0);
  final rng = Random();

  for (int matchNum = 1; matchNum <= 10; matchNum++) {
    print("Match #$matchNum");
    final matchPoints = List.filled(rules.numPlayers, 0);
    int roundNum = 0;
    while (matchPoints.every((p) => p < rules.pointLimit)) {
      roundNum += 1;
      final passDir = roundNum % 4;
      print("Round $roundNum");
      final round = HeartsRound.deal(rules, matchPoints, passDir, rng);
      for (int i = 0; i < rules.numPlayers; i++) {
        print("P$i: ${descriptionWithSuitGroups(round.players[i].hand)}");
      }
      if (passDir != 0) {
        print("Passing dir=$passDir");
        for (int i = 0; i < rules.numPlayers; i++) {
          final passReq = CardsToPassRequest(
              rules: rules,
              scoresBeforeRound: List.of(matchPoints),
              hand: round.players[i].hand,
              direction: passDir,
              numCards: rules.numPassedCards,
          );
          final cardsToPass = chooseCardsToPass(passReq);
          round.setPassedCardsForPlayer(i, cardsToPass);
          print("P$i passes $cardsToPass");
        }
        round.passCards();
        print("After passing:");
        for (int i = 0; i < rules.numPlayers; i++) {
          print("P$i: ${descriptionWithSuitGroups(round.players[i].hand)}");
        }
      }
      else {
        print("No passing");
      }
      while (!round.isOver()) {
        final card = computeCardToPlay(round, rng);
        print("P${round.currentPlayerIndex()} plays ${card.symbolString()}");
        round.playCard(card);
        if (round.currentTrick.cards.isEmpty) {
          print("P${round.previousTricks.last.winner} takes the trick");
        }
      }
      final roundPoints = round.pointsTaken();
      print("Scores for round $roundNum: $roundPoints");
      for (int i = 0; i < rules.numPlayers; i++) {
        matchPoints[i] += roundPoints[i];
      }
      print("Scores for match: $matchPoints");
    }
    print("Match over");
    final vp = getVictoryPoints(matchPoints);
    print("Victory points for match: $vp");
    for (int i = 0; i < rules.numPlayers; i++) {
      victoryPoints[i] += vp[i];
    }
    print("Total victory points: $victoryPoints");
    print("====================================");
  }
}

final mcParams = MonteCarloParams(numHands: 50, rolloutsPerHand: 20);

PlayingCard computeCardToPlay(final HeartsRound round, Random rng) {
  final cardReq = CardToPlayRequest.fromRound(round);
  switch (round.currentPlayerIndex()) {
    case 0:
    case 2:
      return chooseCardAvoidingPoints(cardReq, rng);
    case 1:
      return chooseCardMonteCarlo(cardReq, mcParams, chooseCardRandom, rng);
    case 3:
      return chooseCardMonteCarlo(cardReq, mcParams, chooseCardAvoidingPoints, rng);
    default:
      throw Exception("Bad player index: ${round.currentPlayerIndex()}");
  }
}

List<int> getVictoryPoints(List<int> matchPoints) {
  int lowest = matchPoints[0];
  for (int i = 1; i < matchPoints.length; i++) {
    lowest = min(lowest, matchPoints[i]);
  }
  int numWinners = matchPoints.where((p) => p == lowest).length;
  return List.generate(matchPoints.length, (i) => matchPoints[i] == lowest ? 12 ~/ numWinners : 0);
}
