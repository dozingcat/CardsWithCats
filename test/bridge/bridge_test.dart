import "dart:convert";
import "dart:math";

import "package:flutter_test/flutter_test.dart";
import "package:cards_with_cats/cards/card.dart";
import "package:cards_with_cats/bridge/bridge.dart";

const cb = ContractBid.fromString;

void main() {
  group("Serialization", () {
    test("Converts initial match to and from JSON", () {
      final rng = Random(17);
      final match = BridgeMatch(rng);
      final json = match.toJson();
      print(jsonEncode(json));
      final parsedMatch = BridgeMatch.fromJson(json, rng);
      expect(parsedMatch != null, true);
    });
  });

  group("Contract scoring", () {
    // Complete scoring table: https://web2.acbl.org/documentLibrary/play/InstantScorer.pdf
    test("2H nonvul", () {
      final contract = Contract(
          declarer: 0, bid: ContractBid(2, Suit.hearts), isVulnerable: false);

      expect(contract.scoreForTricksTaken(8), 110);
      expect(contract.scoreForTricksTaken(9), 140);
      expect(contract.scoreForTricksTaken(10), 170);

      expect(contract.scoreForTricksTaken(7), -50);
      expect(contract.scoreForTricksTaken(6), -100);
      expect(contract.scoreForTricksTaken(5), -150);
      expect(contract.scoreForTricksTaken(4), -200);
    });

    test("4C vul", () {
      final contract = Contract(
          declarer: 0, bid: ContractBid(4, Suit.clubs), isVulnerable: true);

      expect(contract.scoreForTricksTaken(10), 130);
      expect(contract.scoreForTricksTaken(11), 150);
      expect(contract.scoreForTricksTaken(13), 190);

      expect(contract.scoreForTricksTaken(9), -100);
      expect(contract.scoreForTricksTaken(8), -200);
      expect(contract.scoreForTricksTaken(7), -300);
      expect(contract.scoreForTricksTaken(6), -400);
    });

    test("1NT nonval", () {
      final contract =
          Contract(declarer: 0, bid: ContractBid(1, null), isVulnerable: false);

      expect(contract.scoreForTricksTaken(7), 90);
      expect(contract.scoreForTricksTaken(8), 120);
      expect(contract.scoreForTricksTaken(10), 180);

      expect(contract.scoreForTricksTaken(6), -50);
      expect(contract.scoreForTricksTaken(5), -100);
      expect(contract.scoreForTricksTaken(4), -150);
      expect(contract.scoreForTricksTaken(3), -200);
    });

    test("4S vul", () {
      final contract = Contract(
          declarer: 0, bid: ContractBid(4, Suit.spades), isVulnerable: true);

      expect(contract.scoreForTricksTaken(10), 620);
      expect(contract.scoreForTricksTaken(11), 650);

      expect(contract.scoreForTricksTaken(9), -100);
      expect(contract.scoreForTricksTaken(8), -200);
    });

    test("5D nonvul", () {
      final contract = Contract(
          declarer: 0, bid: ContractBid(5, Suit.diamonds), isVulnerable: false);

      expect(contract.scoreForTricksTaken(11), 400);
      expect(contract.scoreForTricksTaken(12), 420);

      expect(contract.scoreForTricksTaken(10), -50);
      expect(contract.scoreForTricksTaken(9), -100);
    });

    test("3NT vul", () {
      final contract =
          Contract(declarer: 0, bid: ContractBid(3, null), isVulnerable: true);

      expect(contract.scoreForTricksTaken(9), 600);
      expect(contract.scoreForTricksTaken(10), 630);
      expect(contract.scoreForTricksTaken(13), 720);

      expect(contract.scoreForTricksTaken(8), -100);
      expect(contract.scoreForTricksTaken(7), -200);
    });

    test("6S nonvul", () {
      final contract = Contract(
          declarer: 0, bid: ContractBid(6, Suit.spades), isVulnerable: false);

      expect(contract.scoreForTricksTaken(12), 980);
      expect(contract.scoreForTricksTaken(13), 1010);

      expect(contract.scoreForTricksTaken(11), -50);
      expect(contract.scoreForTricksTaken(10), -100);
    });

    test("7d vul", () {
      final contract = Contract(
          declarer: 0, bid: ContractBid(7, Suit.diamonds), isVulnerable: true);

      expect(contract.scoreForTricksTaken(13), 2140);

      expect(contract.scoreForTricksTaken(12), -100);
      expect(contract.scoreForTricksTaken(11), -200);
    });

    test("1h doubled nonvul", () {
      final contract = Contract(
          declarer: 0,
          bid: ContractBid(1, Suit.hearts),
          isVulnerable: false,
          doubled: DoubledType.doubled);

      expect(contract.scoreForTricksTaken(7), 160);
      expect(contract.scoreForTricksTaken(8), 260);
      expect(contract.scoreForTricksTaken(9), 360);

      expect(contract.scoreForTricksTaken(6), -100);
      expect(contract.scoreForTricksTaken(5), -300);
      expect(contract.scoreForTricksTaken(4), -500);
      expect(contract.scoreForTricksTaken(3), -800);
    });

    test("2c doubled vul", () {
      final contract = Contract(
          declarer: 0,
          bid: ContractBid(2, Suit.clubs),
          isVulnerable: true,
          doubled: DoubledType.doubled);

      expect(contract.scoreForTricksTaken(8), 180);
      expect(contract.scoreForTricksTaken(9), 380);
      expect(contract.scoreForTricksTaken(10), 580);

      expect(contract.scoreForTricksTaken(7), -200);
      expect(contract.scoreForTricksTaken(6), -500);
      expect(contract.scoreForTricksTaken(5), -800);
      expect(contract.scoreForTricksTaken(4), -1100);
    });

    test("2c doubled vul", () {
      final contract = Contract(
          declarer: 0,
          bid: ContractBid(2, Suit.clubs),
          isVulnerable: true,
          doubled: DoubledType.doubled);

      expect(contract.scoreForTricksTaken(8), 180);
      expect(contract.scoreForTricksTaken(9), 380);
      expect(contract.scoreForTricksTaken(10), 580);

      expect(contract.scoreForTricksTaken(7), -200);
      expect(contract.scoreForTricksTaken(6), -500);
      expect(contract.scoreForTricksTaken(5), -800);
      expect(contract.scoreForTricksTaken(4), -1100);
    });

    test("2s doubled vul", () {
      final contract = Contract(
          declarer: 0,
          bid: ContractBid(2, Suit.spades),
          isVulnerable: true,
          doubled: DoubledType.doubled);

      expect(contract.scoreForTricksTaken(8), 670);
      expect(contract.scoreForTricksTaken(9), 870);
      expect(contract.scoreForTricksTaken(10), 1070);

      expect(contract.scoreForTricksTaken(7), -200);
      expect(contract.scoreForTricksTaken(6), -500);
      expect(contract.scoreForTricksTaken(5), -800);
      expect(contract.scoreForTricksTaken(4), -1100);
    });

    test("6c doubled nonval", () {
      final contract = Contract(
          declarer: 0,
          bid: ContractBid(6, Suit.clubs),
          isVulnerable: false,
          doubled: DoubledType.doubled);

      expect(contract.scoreForTricksTaken(12), 1090);
      expect(contract.scoreForTricksTaken(13), 1190);

      expect(contract.scoreForTricksTaken(11), -100);
      expect(contract.scoreForTricksTaken(10), -300);
      expect(contract.scoreForTricksTaken(9), -500);
      expect(contract.scoreForTricksTaken(8), -800);
    });

    test("1c redoubled nonval", () {
      final contract = Contract(
          declarer: 0,
          bid: ContractBid(1, Suit.clubs),
          isVulnerable: false,
          doubled: DoubledType.redoubled);

      expect(contract.scoreForTricksTaken(7), 230);
      expect(contract.scoreForTricksTaken(8), 430);
      expect(contract.scoreForTricksTaken(9), 630);

      expect(contract.scoreForTricksTaken(6), -200);
      expect(contract.scoreForTricksTaken(5), -600);
      expect(contract.scoreForTricksTaken(4), -1000);
      expect(contract.scoreForTricksTaken(3), -1600);
    });

    test("1nt redoubled vul", () {
      final contract = Contract(
          declarer: 0,
          bid: ContractBid(1, null),
          isVulnerable: true,
          doubled: DoubledType.redoubled);

      expect(contract.scoreForTricksTaken(7), 760);
      expect(contract.scoreForTricksTaken(8), 1160);
      expect(contract.scoreForTricksTaken(13), 3160);

      expect(contract.scoreForTricksTaken(6), -400);
      expect(contract.scoreForTricksTaken(5), -1000);
      expect(contract.scoreForTricksTaken(4), -1600);
      expect(contract.scoreForTricksTaken(3), -2200);
    });

    test("7nt redoubled vul", () {
      final contract = Contract(
          declarer: 0,
          bid: ContractBid(7, null),
          isVulnerable: true,
          doubled: DoubledType.redoubled);

      expect(contract.scoreForTricksTaken(13), 2980);

      expect(contract.scoreForTricksTaken(12), -400);
      expect(contract.scoreForTricksTaken(11), -1000);
      expect(contract.scoreForTricksTaken(10), -1600);
      expect(contract.scoreForTricksTaken(9), -2200);
      expect(contract.scoreForTricksTaken(0), -7600);
    });
  });

  group("Contract from bids", () {
    test("Single bid", () {
      final bids = [
        PlayerBid(2, BidAction.contract(1, Suit.hearts)),
        PlayerBid(3, BidAction.pass()),
        PlayerBid(0, BidAction.pass()),
      ];

      expect(isBiddingOver(bids), false);
      bids.add(PlayerBid(1, BidAction.pass()));
      expect(isBiddingOver(bids), true);
      final contract = contractFromBids(
        bids: bids,
        vulnerability: Vulnerability.ewOnly,
      );
      expect(contract.declarer, 2);
      expect(contract.bid, ContractBid(1, Suit.hearts));
      expect(contract.isVulnerable, false);
    });

    test("Competitive bids", () {
      final bids = [
        PlayerBid(3, BidAction.pass()),
        PlayerBid(0, BidAction.contract(1, Suit.spades)),
        PlayerBid(1, BidAction.contract(2, Suit.diamonds)),
        PlayerBid(2, BidAction.contract(2, Suit.spades)),
        PlayerBid(3, BidAction.contract(3, Suit.diamonds)),
        PlayerBid(0, BidAction.pass()),
        PlayerBid(1, BidAction.pass()),
      ];

      expect(isBiddingOver(bids), false);
      bids.add(PlayerBid(2, BidAction.pass()));
      expect(isBiddingOver(bids), true);
      final contract = contractFromBids(
        bids: bids,
        vulnerability: Vulnerability.ewOnly,
      );
      expect(contract.declarer, 1);
      expect(contract.bid, ContractBid(3, Suit.diamonds));
      expect(contract.isVulnerable, true);
    });

    test("Doubled", () {
      final bids = [
        PlayerBid(0, BidAction.contract(1, Suit.hearts)),
        PlayerBid(1, BidAction.pass()),
        PlayerBid(2, BidAction.contract(2, Suit.hearts)),
        PlayerBid(3, BidAction.contract(3, Suit.spades)),
        PlayerBid(0, BidAction.contract(4, Suit.hearts)),
        PlayerBid(1, BidAction.contract(4, Suit.spades)),
        PlayerBid(2, BidAction.pass()),
        PlayerBid(3, BidAction.pass()),
      ];

      expect(isBiddingOver(bids), false);
      expect(canCurrentBidderDouble(bids), true);
      expect(canCurrentBidderRedouble(bids), false);

      bids.add(PlayerBid(0, BidAction.double()));
      expect(isBiddingOver(bids), false);
      expect(canCurrentBidderDouble(bids), false);
      expect(canCurrentBidderRedouble(bids), true);

      bids.add(PlayerBid(1, BidAction.pass()));
      expect(isBiddingOver(bids), false);
      expect(canCurrentBidderDouble(bids), false);
      expect(canCurrentBidderRedouble(bids), false);

      bids.add(PlayerBid(2, BidAction.pass()));
      expect(isBiddingOver(bids), false);
      expect(canCurrentBidderDouble(bids), false);
      expect(canCurrentBidderRedouble(bids), true);

      expect(isBiddingOver(bids), false);
      bids.add(PlayerBid(3, BidAction.pass()));
      expect(isBiddingOver(bids), true);
      final contract = contractFromBids(
        bids: bids,
        vulnerability: Vulnerability.ewOnly,
      );
      expect(contract.declarer, 3);
      expect(contract.bid, ContractBid(4, Suit.spades));
      expect(contract.doubled, DoubledType.doubled);
      expect(contract.isVulnerable, true);
    });

    test("Contract in opponent's opened suit", () {
      final bids = [
        PlayerBid(0, BidAction.contract(1, Suit.clubs)),
        PlayerBid(1, BidAction.double()),
        PlayerBid(2, BidAction.pass()),
        PlayerBid(3, BidAction.contract(1, Suit.spades)),
        PlayerBid(0, BidAction.pass()),
        PlayerBid(1, BidAction.contract(2, Suit.clubs)),
        PlayerBid(2, BidAction.pass()),
        PlayerBid(3, BidAction.pass()),
        PlayerBid(0, BidAction.pass()),
      ];

      final contract = contractFromBids(
        bids: bids,
        vulnerability: Vulnerability.neither,
      );
      expect(contract.declarer, 1);
      expect(contract.bid, ContractBid(2, Suit.clubs));
      expect(contract.doubled, DoubledType.none);
      expect(contract.isVulnerable, false);
    });
  });

  group("Match", () {
    void passOutRound(BridgeRound round) {
      for (int i = 0; i < 4; i++) {
        round.addBid(PlayerBid(round.currentBidder(), BidAction.pass()));
      }
    }

    void bidAndPlayOutRound(BridgeRound round, Random rng) {
      round.addBid(
          PlayerBid(round.currentBidder(), BidAction.contract(1, Suit.clubs)));
      for (int i = 0; i < 3; i++) {
        round.addBid(PlayerBid(round.currentBidder(), BidAction.pass()));
      }
      while (!round.isOver()) {
        final legal = round.legalPlaysForCurrentPlayer();
        round.playCard(legal[rng.nextInt(legal.length)]);
      }
    }

    test("Match lasts 4 rounds with rotating dealer", () {
      final match = BridgeMatch(Random(17));
      expect(match.numRounds, 4);
      final startDealer = match.currentRound.dealer;
      const expectedVulnerabilities = [
        Vulnerability.neither,
        Vulnerability.nsOnly,
        Vulnerability.ewOnly,
        Vulnerability.both,
      ];
      for (int i = 0; i < 4; i++) {
        expect(match.currentRoundNumber, i + 1);
        expect(match.currentRound.dealer, (startDealer + i) % 4);
        expect(match.currentRound.vulnerability, expectedVulnerabilities[i]);
        expect(match.duplicateRound.vulnerability, expectedVulnerabilities[i]);
        expect(match.isMatchOver(), false);
        passOutRound(match.currentRound);
        passOutRound(match.duplicateRound);
        expect(match.numCompletedRounds, i + 1);
        match.finishRound();
      }
      expect(match.isMatchOver(), true);
      expect(match.numCompletedRounds, 4);
      expect(match.currentRoundNumber, 4);
      expect(match.previousRounds.length, 4);
      expect(match.previousDuplicateRounds.length, 4);
    });

    test("Starting dealer varies with rng", () {
      final dealers = <int>{};
      for (int seed = 0; seed < 20; seed++) {
        dealers.add(BridgeMatch(Random(seed)).currentRound.dealer);
      }
      expect(dealers, {0, 1, 2, 3});
    });

    test("Single-round match ends after one round", () {
      final match = BridgeMatch(Random(17), numRounds: 1);
      expect(match.numRounds, 1);
      expect(match.currentRoundNumber, 1);
      expect(match.isMatchOver(), false);
      passOutRound(match.currentRound);
      passOutRound(match.duplicateRound);
      expect(match.isMatchOver(), true);
      match.finishRound();
      expect(match.previousRounds.length, 1);
      expect(match.currentRoundNumber, 1);
    });

    test("Single-round match vulnerability varies with rng", () {
      final vulnerabilities = <Vulnerability>{};
      for (int seed = 0; seed < 30; seed++) {
        vulnerabilities.add(
            BridgeMatch(Random(seed), numRounds: 1).currentRound.vulnerability);
      }
      expect(vulnerabilities, Vulnerability.values.toSet());
    });

    test("8-round match repeats the vulnerability cycle", () {
      final match = BridgeMatch(Random(17), numRounds: 8);
      final startDealer = match.currentRound.dealer;
      for (int i = 0; i < 8; i++) {
        expect(match.currentRound.dealer, (startDealer + i) % 4);
        expect(match.currentRound.vulnerability,
            Vulnerability.values[i % 4]);
        passOutRound(match.currentRound);
        passOutRound(match.duplicateRound);
        match.finishRound();
      }
      expect(match.isMatchOver(), true);
      expect(match.previousRounds.length, 8);
    });

    test("finishRound throws if the round is not over", () {
      final match = BridgeMatch(Random(17));
      expect(() => match.finishRound(), throwsException);
    });

    test("IMP total compares each round to its duplicate", () {
      final rng = Random(42);
      final match = BridgeMatch(rng);

      bidAndPlayOutRound(match.currentRound, rng);
      // Duplicate round hasn't finished; no IMPs yet.
      expect(match.netImpsForPlayer0(), 0);
      bidAndPlayOutRound(match.duplicateRound, rng);

      final expectedImps = impsForScoreDifference(
          match.currentRound.contractScoreForPlayer(0) -
              match.duplicateRound.contractScoreForPlayer(0));
      expect(match.netImpsForPlayer0(), expectedImps);

      // Total persists after the round is archived and a new one dealt.
      match.finishRound();
      expect(match.netImpsForPlayer0(), expectedImps);
      expect(match.currentRound.isOver(), false);

      // A second finished round adds its IMPs to the total.
      bidAndPlayOutRound(match.currentRound, rng);
      bidAndPlayOutRound(match.duplicateRound, rng);
      final round2Imps = impsForScoreDifference(
          match.currentRound.contractScoreForPlayer(0) -
              match.duplicateRound.contractScoreForPlayer(0));
      expect(match.netImpsForPlayer0(), expectedImps + round2Imps);
    });

    test("Serialization preserves rounds and IMP total", () {
      final rng = Random(23);
      final match = BridgeMatch(rng);
      bidAndPlayOutRound(match.currentRound, rng);
      bidAndPlayOutRound(match.duplicateRound, rng);
      match.finishRound();
      bidAndPlayOutRound(match.currentRound, rng);
      bidAndPlayOutRound(match.duplicateRound, rng);

      final restored =
          BridgeMatch.fromJson(jsonDecode(jsonEncode(match.toJson())), rng);
      expect(restored.numRounds, match.numRounds);
      expect(restored.previousRounds.length, 1);
      expect(restored.previousDuplicateRounds.length, 1);
      expect(restored.currentRoundNumber, 2);
      expect(restored.numCompletedRounds, 2);
      expect(restored.currentRound.vulnerability, Vulnerability.nsOnly);
      expect(restored.duplicateRound.vulnerability, Vulnerability.nsOnly);
      expect(restored.netImpsForPlayer0(), match.netImpsForPlayer0());
    });

    test("Contract vulnerability follows round vulnerability", () {
      final rng = Random(7);
      final match = BridgeMatch(rng);
      for (int i = 0; i < 4; i++) {
        // The declarer is the dealer, who opens 1C in bidAndPlayOutRound.
        final dealer = match.currentRound.dealer;
        bidAndPlayOutRound(match.currentRound, rng);
        final contract = match.currentRound.contract!;
        expect(contract.declarer, dealer);
        expect(contract.isVulnerable,
            match.currentRound.vulnerability.isPlayerVulnerable(dealer));
        bidAndPlayOutRound(match.duplicateRound, rng);
        match.finishRound();
      }
    });

    test("Reads legacy JSON without duplicate rounds", () {
      final match = BridgeMatch(Random(5));
      final json = jsonDecode(jsonEncode(match.toJson()));
      json.remove("numRounds");
      json.remove("previousDuplicateRounds");
      json.remove("duplicateRound");

      final restored = BridgeMatch.fromJson(json, Random(5));
      expect(restored.numRounds, 4);
      expect(restored.previousDuplicateRounds, isEmpty);
      expect(restored.duplicateRound.isOver(), false);
      expect(restored.netImpsForPlayer0(), 0);
    });
  });
}
