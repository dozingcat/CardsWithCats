import "package:flutter_test/flutter_test.dart";
import "package:cards_with_cats/cards/card.dart";
import "package:cards_with_cats/cards/round.dart";
import "package:cards_with_cats/cards/trick.dart";
import "package:cards_with_cats/hearts/hearts.dart";

const c = SuitedCard.cardsFromString;

void main() {
  test("Leads", () {
    final rules = HeartsRuleSet();
    final hand = c("AS QH 4C");
    final currentTrick = TrickInProgress<SuitedCard>(0);

    final prevTricksNoHearts = [Trick(0, c("8S 7S 6S 5S"), 0)];
    expect(legalPlays(hand, currentTrick, prevTricksNoHearts, rules), c("AS 4C"));

    final prevTricksWithHearts = [Trick(0, c("8S 7S KH 5S"), 0)];
    expect(legalPlays(hand, currentTrick, prevTricksWithHearts, rules), c("AS QH 4C"));
  });
  
  test("Follows", () {
    final rules = HeartsRuleSet();
    final hand = c("AS 2S QH 4C");
    // Need a previous trick to not trigger the "no points on first trick" rule.
    final prevTricks = [Trick(0, c("2C JC QC KC"), 3)];

    final spadeLead = TrickInProgress(0, c("3S KH"));
    expect(legalPlays(hand, spadeLead, prevTricks, rules), c("AS 2S"));

    final diamondLead = TrickInProgress(0, c("3D KH"));
    expect(legalPlays(hand, diamondLead, prevTricks, rules), c("AS 2S QH 4C"));
  });

  test("First trick 2c lead", () {
    final rules = HeartsRuleSet();
    final hand = c("AS 2S QH 3C 2C");
    final firstTrick = TrickInProgress<SuitedCard>(0);
    expect(legalPlays(hand, firstTrick, [], rules), c("2C"));
  });

  test("First trick follow", () {
    final rules = HeartsRuleSet();
    final hand = c("AS 2S AC QH 3C");
    final firstTrick = TrickInProgress(0, c("2C JC"));
    expect(legalPlays(hand, firstTrick, [], rules), c("AC 3C"));
  });

  test("First trick no points", () {
    final rules = HeartsRuleSet();
    final hand = c("AS QS 7S 7H 7D");
    final firstTrick = TrickInProgress(0, c("2C JC"));
    expect(legalPlays(hand, firstTrick, [], rules), c("AS 7S 7D"));

    rules.pointsOnFirstTrick = true;
    expect(legalPlays(hand, firstTrick, [], rules), c("AS QS 7S 7H 7D"));
  });

  test("First trick hand has only points", () {
    final rules = HeartsRuleSet();
    final hand = c("AH TH QS 7H");
    final firstTrick = TrickInProgress(0, c("2C JC"));
    expect(legalPlays(hand, firstTrick, [], rules), c("AH TH QS 7H"));
  });

  test("Trick points", () {
    final rules = HeartsRuleSet();
    rules.jdMinus10 = false;
    final tricks = [
      Trick(0, c("2C AC KC QC"), 1),
      Trick(1, c("3D 6D QS 5D"), 2),
      Trick(2, c("4D JD AH KD"), 1),
    ];
    expect(pointsForTricks(tricks, rules), [0, 1, 13, 0]);

    rules.jdMinus10 = true;
    expect(pointsForTricks(tricks, rules), [0, -9, 13, 0]);
  });

  test("Shooting points", () {
    final rules = HeartsRuleSet();
    rules.moonShooting = MoonShooting.opponentsPlus26;
    rules.jdMinus10 = false;
    final tricks = [
      Trick(0, c("2C AC KC QC"), 1),
      Trick(1, c("AD QS JD JH"), 1),
      Trick(1, c("AH 2H 3H 4H"), 1),
      Trick(1, c("KH 5H 6H 7H"), 1),
      Trick(1, c("QH 8H 9H TH"), 1),
    ];
    expect(pointsForTricks(tricks, rules), [26, 0, 26, 26]);

    rules.jdMinus10 = true;
    expect(pointsForTricks(tricks, rules), [26, -10, 26, 26]);

    rules.moonShooting = MoonShooting.disabled;
    rules.jdMinus10 = false;
    expect(pointsForTricks(tricks, rules), [0, 26, 0, 0]);

    rules.jdMinus10 = true;
    expect(pointsForTricks(tricks, rules), [0, 16, 0, 0]);
  });

  group("All points taken", () {
    HeartsRound playingRound(List<String> hands, {bool jdMinus10 = false, String currentTrick = ""}) {
      return HeartsRound()
        ..rules = (HeartsRuleSet()..jdMinus10 = jdMinus10)
        ..status = HeartsRoundStatus.playing
        ..players = [...hands.map((h) => HeartsPlayer(c(h)))]
        ..initialScores = [0, 0, 0, 0]
        ..passDirection = 0
        ..currentTrick = TrickInProgress(1, c(currentTrick))
        ..previousTricks = [Trick(0, c("2C 3C 4C 5C"), 3)];
    }

    test("No point cards in hands", () {
      expect(playingRound(["2D 3S", "4D 5S", "6D 7S", "8D 9S"]).allPointsTakenAndTricksRemaining(), true);
      expect(playingRound(["2D 3S", "4D 5S", "6D 7S", "8D 2H"]).allPointsTakenAndTricksRemaining(), false);
      expect(playingRound(["2D 3S", "4D 5S", "6D QS", "8D 9S"]).allPointsTakenAndTricksRemaining(), false);
    });

    test("J♦ counts if it's -10 points", () {
      final hands = ["2D 3S", "4D 5S", "6D 7S", "JD 9S"];
      expect(playingRound(hands).allPointsTakenAndTricksRemaining(), true);
      expect(playingRound(hands, jdMinus10: true).allPointsTakenAndTricksRemaining(), false);
    });

    test("Point cards in the current trick", () {
      final round = playingRound(["2D 3S", "4D", "6D 7S", "8D 9S"], currentTrick: "2H");
      expect(round.allPointsTakenAndTricksRemaining(), false);
    });

    test("Requires 2 tricks remaining", () {
      expect(playingRound(["2D", "4D", "6D", "8D"]).allPointsTakenAndTricksRemaining(), false);
      expect(playingRound(["2D", "4D", "6D", "8D"]).allPointsTakenAndTricksRemaining(minRequiredTricks: 1), true);
      expect(playingRound(["", "", "", ""]).allPointsTakenAndTricksRemaining(minRequiredTricks: 0), false);
    });

    test("Play out remaining tricks", () {
      final round = playingRound(["2D 3S", "4D 5S", "6D 7S", "8D 9S"]);
      final pointsBefore = round.pointsTaken();
      playOutRemainingTricks(round);
      expect(round.isOver(), true);
      expect(round.previousTricks.length, 3);
      expect(round.pointsTaken(), pointsBefore);
    });
  });
}
