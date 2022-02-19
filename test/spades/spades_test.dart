import "package:flutter_test/flutter_test.dart";
import "package:cards_with_cats/cards/card.dart";
import "package:cards_with_cats/cards/trick.dart";
import "package:cards_with_cats/spades/spades.dart";

const c = PlayingCard.cardsFromString;

void main() {
  group("Scoring", () {
    late SpadesRound round;

    setUp(() {
      round = SpadesRound.fromJson({
        "rules": {
          "numPlayers": 4,
          "numTeams": 2,
          "removedCards": "",
          "pointLimit": 500,
          "spadeLeading": "always",
          "penalizeBags": true,
        },
        "status": "playing",
        "players": [
          {"hand": "", "bid": 4},
          {"hand": "", "bid": 3},
          {"hand": "", "bid": 2},
          {"hand": "", "bid": 2},
        ],
        "initialScores": [101, 209],
        "dealer": 2,
        "currentTrick": {"leader": 0, "cards": ""},
        "previousTricks": [
          {"leader": 3, "cards": "4S 9S QS 5S", "winner": 1},
          {"leader": 1, "cards": "2D AD 7D 6D", "winner": 2},
          {"leader": 2, "cards": "AH 9H 3H 7H", "winner": 2},
          {"leader": 2, "cards": "KC 9C 3C AC", "winner": 1},
          {"leader": 1, "cards": "AS TS 8S 6S", "winner": 1},
          {"leader": 1, "cards": "9D JD 4D 3D", "winner": 2},
          {"leader": 2, "cards": "5D TC KD TD", "winner": 0},
          {"leader": 0, "cards": "2C 4C 6C JC", "winner": 3},
          {"leader": 3, "cards": "4H QH TH 8H", "winner": 0},
          {"leader": 0, "cards": "KH 2S 6H 5H", "winner": 1},
          {"leader": 1, "cards": "3S 8D 7S JS", "winner": 0},
          {"leader": 0, "cards": "KS 5C QC 8C", "winner": 0},
          {"leader": 0, "cards": "7C QD JH 2H", "winner": 0},
        ],
      });
    });

    test("Bids made", () {
      final scores = round.pointsTaken();

      expect(scores[0].successfulBidPoints, 60);
      expect(scores[0].failedBidPoints, 0);
      expect(scores[0].successfulNilPoints, 0);
      expect(scores[0].failedNilPoints, 0);
      expect(scores[0].overtricks, 2);
      expect(scores[0].overtrickPenalty, 0);
      expect(scores[0].totalRoundPoints, 62);
      expect(scores[0].endingMatchPoints, 163);

      expect(scores[1].successfulBidPoints, 50);
      expect(scores[1].failedBidPoints, 0);
      expect(scores[1].successfulNilPoints, 0);
      expect(scores[1].failedNilPoints, 0);
      expect(scores[1].overtricks, 0);
      expect(scores[1].overtrickPenalty, 0);
      expect(scores[1].totalRoundPoints, 50);
      expect(scores[1].endingMatchPoints, 259);
    });

    test("Bid failed", () {
      round.players[3].bid = 3;
      final scores = round.pointsTaken();

      expect(scores[0].successfulBidPoints, 60);
      expect(scores[0].failedBidPoints, 0);
      expect(scores[0].successfulNilPoints, 0);
      expect(scores[0].failedNilPoints, 0);
      expect(scores[0].overtricks, 2);
      expect(scores[0].overtrickPenalty, 0);
      expect(scores[0].totalRoundPoints, 62);
      expect(scores[0].endingMatchPoints, 163);

      expect(scores[1].successfulBidPoints, 0);
      expect(scores[1].failedBidPoints, -60);
      expect(scores[1].successfulNilPoints, 0);
      expect(scores[1].failedNilPoints, 0);
      expect(scores[1].overtricks, 0);
      expect(scores[1].overtrickPenalty, 0);
      expect(scores[1].totalRoundPoints, -60);
      expect(scores[1].endingMatchPoints, 149);
    });

    test("Bid failed", () {
      round.players[3].bid = 3;
      final scores = round.pointsTaken();

      expect(scores[0].successfulBidPoints, 60);
      expect(scores[0].failedBidPoints, 0);
      expect(scores[0].successfulNilPoints, 0);
      expect(scores[0].failedNilPoints, 0);
      expect(scores[0].overtricks, 2);
      expect(scores[0].overtrickPenalty, 0);
      expect(scores[0].totalRoundPoints, 62);
      expect(scores[0].endingMatchPoints, 163);

      expect(scores[1].successfulBidPoints, 0);
      expect(scores[1].failedBidPoints, -60);
      expect(scores[1].successfulNilPoints, 0);
      expect(scores[1].failedNilPoints, 0);
      expect(scores[1].overtricks, 0);
      expect(scores[1].overtrickPenalty, 0);
      expect(scores[1].totalRoundPoints, -60);
      expect(scores[1].endingMatchPoints, 149);
    });

    test("Nil bid failed", () {
      round.players[1].bid = 4;
      round.players[3].bid = 0;
      round.initialScores = [100, 200];
      final scores = round.pointsTaken();

      expect(scores[0].successfulBidPoints, 60);
      expect(scores[0].failedBidPoints, 0);
      expect(scores[0].successfulNilPoints, 0);
      expect(scores[0].failedNilPoints, 0);
      expect(scores[0].overtricks, 2);
      expect(scores[0].overtrickPenalty, 0);
      expect(scores[0].totalRoundPoints, 62);
      expect(scores[0].endingMatchPoints, 162);

      expect(scores[1].successfulBidPoints, 40);
      expect(scores[1].failedBidPoints, 0);
      expect(scores[1].successfulNilPoints, 0);
      expect(scores[1].failedNilPoints, -100);
      expect(scores[1].overtricks, 1);
      expect(scores[1].overtrickPenalty, 0);
      expect(scores[1].totalRoundPoints, -59);
      expect(scores[1].endingMatchPoints, 141);
    });

    test("Nil bid succeded", () {
      round.players[1].bid = 4;
      round.players[3].bid = 0;
      // Make player 1 take the 8th trick so that player 3 makes nil.
      round.previousTricks[7] = Trick.fromJson({"leader": 0, "cards": "2C JC 4C 6C", "winner": 1});
      round.previousTricks[8] = Trick.fromJson({"leader": 1, "cards": "4H 8H TH QH", "winner": 0});

      round.initialScores = [100, 200];
      final scores = round.pointsTaken();

      expect(scores[0].successfulBidPoints, 60);
      expect(scores[0].failedBidPoints, 0);
      expect(scores[0].successfulNilPoints, 0);
      expect(scores[0].failedNilPoints, 0);
      expect(scores[0].overtricks, 2);
      expect(scores[0].overtrickPenalty, 0);
      expect(scores[0].totalRoundPoints, 62);
      expect(scores[0].endingMatchPoints, 162);

      expect(scores[1].successfulBidPoints, 40);
      expect(scores[1].failedBidPoints, 0);
      expect(scores[1].successfulNilPoints, 100);
      expect(scores[1].failedNilPoints, 0);
      expect(scores[1].overtricks, 1);
      expect(scores[1].overtrickPenalty, 0);
      expect(scores[1].totalRoundPoints, 141);
      expect(scores[1].endingMatchPoints, 341);
    });

    test("Bag penalty", () {
      round.initialScores = [109, 200];
      final scores = round.pointsTaken();

      expect(scores[0].successfulBidPoints, 60);
      expect(scores[0].failedBidPoints, 0);
      expect(scores[0].successfulNilPoints, 0);
      expect(scores[0].failedNilPoints, 0);
      expect(scores[0].overtricks, 2);
      expect(scores[0].overtrickPenalty, -110);
      expect(scores[0].totalRoundPoints, -48);
      expect(scores[0].endingMatchPoints, 61);

      expect(scores[1].successfulBidPoints, 50);
      expect(scores[1].failedBidPoints, 0);
      expect(scores[1].successfulNilPoints, 0);
      expect(scores[1].failedNilPoints, 0);
      expect(scores[1].overtricks, 0);
      expect(scores[1].overtrickPenalty, 0);
      expect(scores[1].totalRoundPoints, 50);
      expect(scores[1].endingMatchPoints, 250);
    });

    test("No bad penalty if rule disabled", () {
      round.rules.penalizeBags = false;
      round.initialScores = [100, 200];
      final scores = round.pointsTaken();

      expect(scores[0].successfulBidPoints, 60);
      expect(scores[0].failedBidPoints, 0);
      expect(scores[0].successfulNilPoints, 0);
      expect(scores[0].failedNilPoints, 0);
      expect(scores[0].overtricks, 0);
      expect(scores[0].overtrickPenalty, 0);
      expect(scores[0].totalRoundPoints, 60);
      expect(scores[0].endingMatchPoints, 160);

      expect(scores[1].successfulBidPoints, 50);
      expect(scores[1].failedBidPoints, 0);
      expect(scores[1].successfulNilPoints, 0);
      expect(scores[1].failedNilPoints, 0);
      expect(scores[1].overtricks, 0);
      expect(scores[1].overtrickPenalty, 0);
      expect(scores[1].totalRoundPoints, 50);
      expect(scores[1].endingMatchPoints, 250);

    });
  });
}