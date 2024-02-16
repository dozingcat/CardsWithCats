import "package:flutter_test/flutter_test.dart";
import "package:cards_with_cats/cards/card.dart";
import "package:cards_with_cats/cards/trick.dart";
import "package:cards_with_cats/bridge/bridge.dart";

void main() {
  group("Contract scoring", () {
    // Complete scoring table: https://web2.acbl.org/documentLibrary/play/InstantScorer.pdf
    test("2H nonvul", () {
      final contract = Contract(
          declarer: 0,
          bid: ContractBid(2, Suit.hearts),
          vulnerability: Vulnerability.no);

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
          declarer: 0,
          bid: ContractBid(4, Suit.clubs),
          vulnerability: Vulnerability.yes);

      expect(contract.scoreForTricksTaken(10), 130);
      expect(contract.scoreForTricksTaken(11), 150);
      expect(contract.scoreForTricksTaken(13), 190);

      expect(contract.scoreForTricksTaken(9), -100);
      expect(contract.scoreForTricksTaken(8), -200);
      expect(contract.scoreForTricksTaken(7), -300);
      expect(contract.scoreForTricksTaken(6), -400);
    });

    test("1NT nonval", () {
      final contract = Contract(
          declarer: 0,
          bid: ContractBid(1, null),
          vulnerability: Vulnerability.no);

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
          declarer: 0,
          bid: ContractBid(4, Suit.spades),
          vulnerability: Vulnerability.yes);

      expect(contract.scoreForTricksTaken(10), 620);
      expect(contract.scoreForTricksTaken(11), 650);

      expect(contract.scoreForTricksTaken(9), -100);
      expect(contract.scoreForTricksTaken(8), -200);
    });

    test("5D nonvul", () {
      final contract = Contract(
          declarer: 0,
          bid: ContractBid(5, Suit.diamonds),
          vulnerability: Vulnerability.no);

      expect(contract.scoreForTricksTaken(11), 400);
      expect(contract.scoreForTricksTaken(12), 420);

      expect(contract.scoreForTricksTaken(10), -50);
      expect(contract.scoreForTricksTaken(9), -100);
    });

    test("3NT vul", () {
      final contract = Contract(
          declarer: 0,
          bid: ContractBid(3, null),
          vulnerability: Vulnerability.yes);

      expect(contract.scoreForTricksTaken(9), 600);
      expect(contract.scoreForTricksTaken(10), 630);
      expect(contract.scoreForTricksTaken(13), 720);

      expect(contract.scoreForTricksTaken(8), -100);
      expect(contract.scoreForTricksTaken(7), -200);
    });

    test("6S nonvul", () {
      final contract = Contract(
          declarer: 0,
          bid: ContractBid(6, Suit.spades),
          vulnerability: Vulnerability.no);

      expect(contract.scoreForTricksTaken(12), 980);
      expect(contract.scoreForTricksTaken(13), 1010);

      expect(contract.scoreForTricksTaken(11), -50);
      expect(contract.scoreForTricksTaken(10), -100);
    });

    test("7d vul", () {
      final contract = Contract(
          declarer: 0,
          bid: ContractBid(7, Suit.diamonds),
          vulnerability: Vulnerability.yes);

      expect(contract.scoreForTricksTaken(13), 2140);

      expect(contract.scoreForTricksTaken(12), -100);
      expect(contract.scoreForTricksTaken(11), -200);
    });

    test("1h doubled nonvul", () {
      final contract = Contract(
          declarer: 0,
          bid: ContractBid(1, Suit.hearts),
          vulnerability: Vulnerability.no,
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
          vulnerability: Vulnerability.yes,
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
          vulnerability: Vulnerability.yes,
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
          vulnerability: Vulnerability.yes,
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
          vulnerability: Vulnerability.no,
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
          vulnerability: Vulnerability.no,
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
          vulnerability: Vulnerability.yes,
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
          vulnerability: Vulnerability.yes,
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
        PlayerBid.contract(2, ContractBid(1, Suit.hearts)),
        PlayerBid.pass(3),
        PlayerBid.pass(0),
      ];

      expect(isBiddingOver(bids), false);
      bids.add(PlayerBid.pass(1));
      expect(isBiddingOver(bids), true);
      final contract = contractFromBids(
          bids: bids,
          northSouthVulnerable: Vulnerability.no,
          eastWestVulnerable: Vulnerability.yes,
      );
      expect(contract.declarer, 2);
      expect(contract.bid, ContractBid(1, Suit.hearts));
      expect(contract.vulnerability, Vulnerability.no);
    });

    test("Competitive bids", () {
      final bids = [
        PlayerBid.pass(3),
        PlayerBid.contract(0, ContractBid(1, Suit.spades)),
        PlayerBid.contract(1, ContractBid(2, Suit.diamonds)),
        PlayerBid.contract(2, ContractBid(2, Suit.spades)),
        PlayerBid.contract(3, ContractBid(3, Suit.diamonds)),
        PlayerBid.pass(0),
        PlayerBid.pass(1),
      ];

      expect(isBiddingOver(bids), false);
      bids.add(PlayerBid.pass(2));
      expect(isBiddingOver(bids), true);
      final contract = contractFromBids(
        bids: bids,
        northSouthVulnerable: Vulnerability.no,
        eastWestVulnerable: Vulnerability.yes,
      );
      expect(contract.declarer, 1);
      expect(contract.bid, ContractBid(3, Suit.diamonds));
      expect(contract.vulnerability, Vulnerability.yes);
    });

    test("Doubled", () {
      final bids = [
        PlayerBid.contract(0, ContractBid(1, Suit.hearts)),
        PlayerBid.pass(1),
        PlayerBid.contract(2, ContractBid(2, Suit.hearts)),
        PlayerBid.contract(3, ContractBid(3, Suit.spades)),
        PlayerBid.contract(0, ContractBid(4, Suit.hearts)),
        PlayerBid.contract(1, ContractBid(4, Suit.spades)),
        PlayerBid.pass(2),
        PlayerBid.pass(3),
        PlayerBid.double(0),
        PlayerBid.pass(1),
        PlayerBid.pass(2),
      ];

      expect(isBiddingOver(bids), false);
      bids.add(PlayerBid.pass(3));
      expect(isBiddingOver(bids), true);
      final contract = contractFromBids(
        bids: bids,
        northSouthVulnerable: Vulnerability.no,
        eastWestVulnerable: Vulnerability.yes,
      );
      expect(contract.declarer, 3);
      expect(contract.bid, ContractBid(4, Suit.spades));
      expect(contract.doubled, DoubledType.doubled);
      expect(contract.vulnerability, Vulnerability.yes);
    });
  });
}
