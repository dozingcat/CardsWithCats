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
}
