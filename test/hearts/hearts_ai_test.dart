import "package:flutter_test/flutter_test.dart";
import "package:hearts/cards/card.dart";
import "package:hearts/hearts/hearts.dart";
import "package:hearts/hearts/hearts_ai.dart";

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
}