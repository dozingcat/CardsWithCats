import 'dart:math';

import "package:flutter_test/flutter_test.dart";
import "package:cards_with_cats/cards/card.dart";
import 'package:cards_with_cats/cards/rollout.dart';
import 'package:cards_with_cats/cards/trick.dart';
import "package:cards_with_cats/hearts/hearts.dart";
import "package:cards_with_cats/hearts/hearts_ai.dart";

const c = PlayingCard.cardsFromString;

void main() {
  test("Match equity", () {
    // Match is won or lost.
    expect(matchEquityForScores([50, 60, 100, 60], 100, 0), 1.0);
    expect(matchEquityForScores([50, 60, 100, 60], 100, 1), 0.0);

    // All players including winner are over the limit.
    expect(matchEquityForScores([104, 103, 102, 101], 100, 3), 1.0);
    expect(matchEquityForScores([104, 103, 102, 101], 100, 2), 0.0);

    // Ties.
    expect(matchEquityForScores([50, 60, 100, 50], 100, 3), 0.5);
    expect(matchEquityForScores([0, 0, 0, 0], 100, 3), 0.25);

    // Slightly improving score should increase equity.
    {
      final e1 = matchEquityForScores([50, 60, 70, 80], 100, 0);
      final e2 = matchEquityForScores([51, 59, 70, 80], 100, 0);
      expect(e2, greaterThan(0.25));
      expect(e1, greaterThan(e2));
    }

    // Sum of equities should be near 1.
    {
      final scores = [80, 70, 60, 50];
      final p0 = matchEquityForScores(scores, 100, 0);
      final p1 = matchEquityForScores(scores, 100, 1);
      final p2 = matchEquityForScores(scores, 100, 2);
      final p3 = matchEquityForScores(scores, 100, 3);
      expect(p0, lessThan(p1));
      expect(p1, lessThan(0.25));
      expect(p2, greaterThan(0.25));
      expect(p3, greaterThan(p2));
      expect(p0 + p1 + p2 + p3, closeTo(1.0, 0.01));
    }
  });

  test("Pass high cards", () {
    final req = CardsToPassRequest(
        rules: HeartsRuleSet(),
        scoresBeforeRound: [0, 0, 0, 0],
        hand: c("JS 5S 4S 3S 8H 5H 3H AD KD TD 7C 6C 4C"),
        direction: 1,
        numCards: 3,
    );
    expect(chooseCardsToPass(req), c("AD KD TD"));
  });

  test("Pass bad spades", () {
    final req = CardsToPassRequest(
      rules: HeartsRuleSet(),
      scoresBeforeRound: [0, 0, 0, 0],
      hand: c("AS QS JS AH 8H 2H 6D 5D 4D 3D 6C 5C 4C"),
      direction: 1,
      numCards: 3,
    );
    expect(chooseCardsToPass(req), c("AS QS AH"));
  });

  test("Keep spades above queen passing right", () {
    final req = CardsToPassRequest(
      rules: HeartsRuleSet(),
      scoresBeforeRound: [0, 0, 0, 0],
      hand: c("AS QS JS AH 8H 2H 6D 5D 4D 3D 6C 5C 4C"),
      direction: 3,
      numCards: 3,
    );
    expect(chooseCardsToPass(req), c("QS AH 8H"));
  });

  test("Pass high spades right without queen", () {
    final req = CardsToPassRequest(
      rules: HeartsRuleSet(),
      scoresBeforeRound: [0, 0, 0, 0],
      hand: c("AS KS JS AH 8H 2H 6D 5D 4D 3D 6C 5C 4C"),
      direction: 3,
      numCards: 3,
    );
    expect(chooseCardsToPass(req), c("AS KS AH"));
  });

  test("Dump queen", () {
    final rng = Random(17);
    final req = CardToPlayRequest(
        rules: HeartsRuleSet(),
        scoresBeforeRound: [0, 0, 0, 0],
        hand: c("KS QS JS TS AH 9H 6H 3H AD KD QD JD"),
        previousTricks: [Trick(0, c("2C QC KC AC"), 3)],
        currentTrick: TrickInProgress(3, c("4C")),
        passDirection: 0,
        passedCards: [],
        receivedCards: []);

    final avoidPointsCard = chooseCardAvoidingPoints(req, rng);
    expect(avoidPointsCard, c("QS")[0]);
    final mcCard = chooseCardMonteCarlo(req, makeMCParams(20, 50), chooseCardAvoidingPoints, rng);
    expect(mcCard, isIn(c("QS")));
  });

  test("Dump high spade", () {
    final rng = Random(17);
    final req = CardToPlayRequest(
        rules: HeartsRuleSet(),
        scoresBeforeRound: [0, 0, 0, 0],
        hand: c("KS JS AH 9H 6H 5H 4H 3H AD KD QD 2D"),
        previousTricks: [Trick(0, c("2C QC KC AC"), 3)],
        currentTrick: TrickInProgress(3, c("4C")),
        passDirection: 0,
        passedCards: [],
        receivedCards: []);

    // final avoidPointsCard = chooseCardAvoidingPoints(req, rng);
    // expect(avoidPointsCard, c("KS")[0]);
    expect(req.currentPlayerIndex(), 0);
    final mcCard = chooseCardMonteCarlo(req, makeMCParams(50, 20), chooseCardAvoidingPoints, rng);
    expect(mcCard, isIn(c("KS")));
  });

  test("Avoid queen", () {
    final rng = Random(17);
    final req = CardToPlayRequest(
        rules: HeartsRuleSet(),
        scoresBeforeRound: [0, 0, 0, 0],
        hand: c("KS 9S 2S KH 3H 2H 9D 8D 7D 9C 8C 3C"),
        previousTricks: [Trick(0, c("2C AC KC QC"), 1)],
        currentTrick: TrickInProgress(1, c("4S")),
        passDirection: 0,
        passedCards: [],
        receivedCards: []);
    expect(req.currentPlayerIndex(), 2);

    final mcCard = chooseCardMonteCarlo(req, makeMCParams(50, 20), chooseCardAvoidingPoints, rng);
    expect(mcCard, isIn(c("9S 2S")));
  });

  test("Play high spade if queen was passed right", () {
    final rng = Random(17);
    final req = CardToPlayRequest(
        rules: HeartsRuleSet(),
        scoresBeforeRound: [0, 0, 0, 0],
        hand: c("KS 9S 2S KH 3H 2H 9D 8D 7D 9C 8C 3C"),
        previousTricks: [Trick(0, c("2C AC KC QC"), 1)],
        currentTrick: TrickInProgress(1, c("4S 8S")),
        passDirection: 3,
        passedCards: c("AS QS QD"),
        receivedCards: c("KH 9C 8C"));

    final mcCard = chooseCardMonteCarlo(req, makeMCParams(50, 20), chooseCardAvoidingPoints, rng);
    expect(mcCard, isIn(c("KS")));
  });

  test("Take queen to avoid losing", () {
    // Player 0 has to take the queen, otherwise player 3 will go over the
    // point limit and player 1 will win.
    final rng = Random(17);
    final req = CardToPlayRequest(
        rules: HeartsRuleSet(),
        scoresBeforeRound: [20, 0, 40, 90],
        hand: c("AS 9S 2S KH 3H 2H 9D 8D 7D 9C 8C 3C"),
        previousTricks: [Trick(0, c("2C AC KC QC"), 1)],
        currentTrick: TrickInProgress(1, c("4S 8S QS")),
        passDirection: 0,
        passedCards: [],
        receivedCards: []);

    final mcCard = chooseCardMonteCarlo(req, makeMCParams(50, 20), chooseCardAvoidingPoints, rng);
    expect(mcCard, isIn(c("AS")));
  });

  test("Take jack of diamonds if minus 10", () {
    final rng = Random(17);
    final req = CardToPlayRequest(
        rules: HeartsRuleSet(),
        scoresBeforeRound: [0, 0, 0, 0],
        hand: c("AS JS 6S AH JH 6H AD JD 3D 2D 4C 3C"),
        previousTricks: [Trick(0, c("2C QC KC AC"), 3)],
        currentTrick: TrickInProgress(3, c("4D 8D KH")),
        passDirection: 0,
        passedCards: [],
        receivedCards: []);

    final mcCardNoJD =
        chooseCardMonteCarlo(req, makeMCParams(50, 20), chooseCardAvoidingPoints, rng);
    expect(mcCardNoJD, isIn(c("AD")));

    req.rules.jdMinus10 = true;
    final mcCardWithJD =
        chooseCardMonteCarlo(req, makeMCParams(50, 20), chooseCardAvoidingPoints, rng);
    expect(mcCardWithJD, isIn(c("JD")));
  });

  test("Don't expect opponent to drop jack of diamonds", () {
    final rng = Random(17);
    final req = CardToPlayRequest(
        rules: HeartsRuleSet()
          ..jdMinus10 = true,
        scoresBeforeRound: [0, 0, 0, 0],
        hand: c("AD TD 9D 8D JS TS 9S 8S KH 4H JC TC"),
        previousTricks: [Trick(0, c("2C QC KC AC"), 3)],
        currentTrick: TrickInProgress(3, []),
        passDirection: 0,
        passedCards: [],
        receivedCards: []);

    // Make sure that we don't model opponents as wanting to play JD
    // if we lead a higher diamond. A spade is the only reasonable lead.
    final mcCard = chooseCardMonteCarlo(req, makeMCParams(50, 20), chooseCardAvoidingPoints, rng);
    expect(mcCard, isIn(c("JS TS 9S 8S")));
  });

  test("Block shoot", () {
    final rng = Random(17);
    // Basic shooting defense. Contrived hand:
    // P0: ♠ ♥AQT954 ♦ ♣8765432
    // P1: ♠87532 ♥K73 ♦76542 ♣
    // P2 (shooter): ♠AKQJT ♥ ♦AKQJT ♣AJT
    // P3 (defender): ♠964 ♥J862 ♦983 ♣KQ9
    // P2 gets down to the AJ of clubs and P3 has Q9. When P2 plays the ace,
    // P3 must play the 9 so that the Q will take a heart on the last trick.
    final req = CardToPlayRequest(
        rules: HeartsRuleSet(),
        scoresBeforeRound: [0, 0, 0, 0],
        hand: c("QC 9C"),
        previousTricks: [
          Trick(0, c("2C 7D TC KC"), 3),
          Trick(3, c("9S 4H 8S AS"), 2),
          Trick(2, c("AD 3D AH 5D"), 2),
          Trick(2, c("KD 8D QH 6D"), 2),
          Trick(2, c("QD 9D TH 4D"), 2),
          Trick(2, c("JD JH 9H 2D"), 2),
          Trick(2, c("TD 8H 5H KH"), 2),
          Trick(2, c("KS 6S 8C 7S"), 2),
          Trick(2, c("QS 4S 7C 5S"), 2),
          Trick(2, c("JS 6H 6C 3S"), 2),
          Trick(2, c("TS 2H 5C 2S"), 2),
        ],
        currentTrick: TrickInProgress(2, c("AC")),
        passDirection: 0,
        passedCards: [],
        receivedCards: []);

    final mcCard = chooseCardMonteCarlo(req, makeMCParams(50, 20), chooseCardAvoidingPoints, rng);
    expect(mcCard, isIn(c("9C")));
  });
}

MonteCarloParams makeMCParams(int hands, int rollouts) =>
    MonteCarloParams(maxRounds: hands, rolloutsPerRound: rollouts);
