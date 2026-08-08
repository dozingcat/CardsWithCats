import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/trick.dart';
import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/bridge_ai.dart';
import 'package:cards_with_cats/bridge/heuristic_play.dart';

List<PlayingCard> parseHand(String s) {
  // "KQJ52 743 862 95" -> spades, hearts, diamonds, clubs; "-" for void.
  final groups = s.split(" ");
  final suits = [Suit.spades, Suit.hearts, Suit.diamonds, Suit.clubs];
  final cards = <PlayingCard>[];
  for (int i = 0; i < 4; i++) {
    if (groups[i] == "-") continue;
    for (final ch in groups[i].split("")) {
      cards.add(PlayingCard.cardsFromString("$ch${suits[i].asciiChar}")[0]);
    }
  }
  return cards;
}

PlayingCard card(String s) => PlayingCard.cardsFromString(s)[0];

/// Builds a play request. The auction is a single contract bid by
/// `declarer` followed by three passes. `trickCards` are cards already
/// played to the current trick, led by `trickLeader`; the player to act
/// is `trickLeader + trickCards.length`. `dummyHand` is the dummy's
/// current cards as visible to the player to act.
CardToPlayRequest reqFor({
  required String hand,
  required String contract, // e.g. "3NT", "4H"
  required int declarer,
  String? dummyHand,
  List<Trick> previousTricks = const [],
  int? trickLeader,
  List<String> trickCards = const [],
}) {
  final bids = [
    PlayerBid(declarer, BidAction.fromString(contract)),
    for (int i = 1; i <= 3; i++)
      PlayerBid((declarer + i) % 4, BidAction.pass()),
  ];
  final trick = TrickInProgress(trickLeader ?? (declarer + 1) % 4);
  trick.cards.addAll(trickCards.map(card));
  return CardToPlayRequest(
    hand: parseHand(hand),
    dummyHand: dummyHand != null ? parseHand(dummyHand) : null,
    previousTricks: List.of(previousTricks),
    currentTrick: trick,
    bidHistory: bids,
    vulnerability: Vulnerability.neither,
  );
}

void main() {
  final rng = Random(17);

  group("opening leads", () {
    test("top of a sequence against notrump", () {
      final req = reqFor(
          hand: "KQJ52 743 862 95", contract: "3NT", declarer: 0);
      expect(chooseCardHeuristic(req, rng), card("KS"));
    });

    test("fourth best from length against notrump", () {
      final req = reqFor(
          hand: "K8532 743 862 95", contract: "3NT", declarer: 0);
      expect(chooseCardHeuristic(req, rng), card("3S"));
    });

    test("never leads an unsupported king from K432", () {
      final req = reqFor(
          hand: "K432 975 8632 92", contract: "4H", declarer: 0);
      final c = chooseCardHeuristic(req, rng);
      expect(c, isNot(card("KS")));
      expect(c.suit, isNot(Suit.hearts)); // no trump lead here either
    });

    test("ace from ace-king against a suit contract", () {
      final req = reqFor(
          hand: "AK32 975 8632 92", contract: "4H", declarer: 0);
      expect(chooseCardHeuristic(req, rng), card("AS"));
    });

    test("singleton against a suit contract", () {
      final req = reqFor(
          hand: "8532 975 96432 9", contract: "4H", declarer: 0);
      expect(chooseCardHeuristic(req, rng), card("9C"));
    });

    test("does not underlead an ace against a suit contract", () {
      final req = reqFor(
          hand: "A432 975 8632 92", contract: "4H", declarer: 0);
      final c = chooseCardHeuristic(req, rng);
      expect(c == card("2S") || c == card("3S") || c == card("4S"), false,
          reason: "led $c");
    });
  });

  group("following suit", () {
    test("second hand low", () {
      // Hero (seat 1) is declarer, playing second after seat 0's lead.
      final req = reqFor(
          hand: "Q73 975 8632 92",
          contract: "3NT",
          declarer: 1,
          dummyHand: "J98 KQJ AK54 AK3",
          trickLeader: 0,
          trickCards: ["4S"]);
      expect(chooseCardHeuristic(req, rng), card("3S"));
    });

    test("third hand high, lowest of touching honors", () {
      // Partner (seat 0) led low, dummy (seat 1) played the 8; hero is
      // third with KQ2 and beats the 8 as cheaply as possible.
      final req = reqFor(
          hand: "KQ2 975 8632 92",
          contract: "3NT",
          declarer: 3,
          dummyHand: "J9 KQJ AK54 AK3",
          trickLeader: 0,
          trickCards: ["4S", "8S"]);
      expect(chooseCardHeuristic(req, rng), card("QS"));
    });

    test("third hand stays low when partner's honor holds", () {
      // Partner (seat 2) led the queen (sequence lead); dummy (seat 3,
      // playing second) contributed the 5. Don't waste the king.
      final req = reqFor(
          hand: "K72 975 8632 92",
          contract: "3NT",
          declarer: 1,
          dummyHand: "J98 KQJ AK54 AK3",
          trickLeader: 2,
          trickCards: ["QS", "5S"]);
      expect(chooseCardHeuristic(req, rng), card("2S"));
    });

    test("fourth hand wins as cheaply as possible", () {
      // Hero (seat 3) is declarer playing last.
      final req = reqFor(
          hand: "KQ2 975 8632 92",
          contract: "3NT",
          declarer: 3,
          dummyHand: "J9 KQJ AK54 AK3",
          trickLeader: 0,
          trickCards: ["4S", "8S", "TS"]);
      expect(chooseCardHeuristic(req, rng), card("QS"));
    });

    test("fourth hand discards low when partner is winning", () {
      // Hero (seat 3) is declarer; dummy's ace is winning the trick.
      final req = reqFor(
          hand: "KQ2 975 8632 92",
          contract: "3NT",
          declarer: 3,
          dummyHand: "J98 KQ AK54 AK3",
          trickLeader: 0,
          trickCards: ["4H", "AH", "2H"]);
      expect(chooseCardHeuristic(req, rng), card("5H"));
    });

    test("ruffs when void and the opponents are winning", () {
      // Hero (seat 2) is void in spades; dummy's ace is winning.
      final req = reqFor(
          hand: "- 975 8632 965432",
          contract: "4H",
          declarer: 3,
          dummyHand: "J9 KQJ AK54 AK3",
          trickLeader: 0,
          trickCards: ["4S", "AS"]);
      expect(chooseCardHeuristic(req, rng), card("5H"));
    });
  });

  group("declarer play", () {
    test("draws trumps from the top", () {
      // Declarer (seat 0) won trick one and holds AKQ32 of trumps;
      // the opponents still hold trumps.
      final req = reqFor(
          hand: "AKQ32 97 863 92",
          contract: "4S",
          declarer: 0,
          dummyHand: "54 AK A542 A543",
          previousTricks: [
            Trick(1, [card("KH"), card("2H"), card("6H"), card("AH")], 0),
          ],
          trickLeader: 0,
          trickCards: []);
      expect(chooseCardHeuristic(req, rng), card("AS"));
    });
  });
}
