/// Scans AI-played deals for suspicious defensive leads: an unsupported
/// high honor (K or Q with no touching honor) led from length. Prints each
/// occurrence with the holding, the visible dummy's cards in the suit, and
/// what the heuristic policy would have led instead, plus a summary.
///
/// Usage: dart run scripts/lead_scan.dart [--deals N] [--seed N] [--dump]
library;

import 'dart:math';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/bridge_ai.dart';
import 'package:cards_with_cats/bridge/heuristic_play.dart';
import 'package:cards_with_cats/bridge/sayc/sayc_bidding.dart';
import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/rollout.dart';

String suitHolding(List<PlayingCard> hand, Suit s) {
  final cards = sortedCardsInSuit(hand, s);
  return cards.isEmpty ? "-" : cards.map((c) => c.rank.asciiChar).join();
}

void main(List<String> args) {
  int numDeals = 60;
  int seed = 7;
  int mcRounds = 10;
  double margin = 5;
  bool dump = false;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--deals":
        numDeals = int.parse(args[++i]);
      case "--seed":
        seed = int.parse(args[++i]);
      case "--rounds":
        mcRounds = int.parse(args[++i]);
      case "--margin":
        margin = double.parse(args[++i]);
      case "--dump":
        dump = true;
    }
  }

  int defenderLeads = 0;
  int suspiciousLeads = 0;
  int intoDummyHonor = 0;
  int heuristicAgreed = 0;

  for (int d = 0; d < numDeals; d++) {
    final rng = Random(seed * 100003 + d);
    final round = BridgeRound.deal(d % 4, rng)
      ..vulnerability = vulnerabilityForRoundIndex(d);
    bool ok = true;
    while (round.status == BridgeRoundStatus.bidding) {
      final seat = round.currentBidder();
      final history = [for (final b in round.bidHistory) b.action];
      BidAction call;
      try {
        call = selectSaycBid(round.players[seat].hand, history,
                vulnerability: round.vulnerability)
            .action;
      } catch (e) {
        ok = false;
        break;
      }
      if (!isLegalCall(call, history)) {
        ok = false;
        break;
      }
      round.addBid(PlayerBid(seat, call));
    }
    if (!ok || round.isPassedOut()) continue;

    final contract = round.contract!;
    while (!round.isOver()) {
      final req = CardToPlayRequest.fromRound(round);
      final seat = round.currentPlayerIndex();
      final isDefender = seat % 2 != contract.declarer % 2;
      final isLead = round.currentTrick.cards.isEmpty;
      final card = chooseCardMonteCarloDD(req, Random(seed + d),
              maxRounds: mcRounds,
              ddTricksLimit: 7,
              equityMargin: margin,
              defenderEquityMargin: margin == 0 ? 0 : 18)
          .bestCard;

      if (isDefender && isLead) {
        defenderLeads++;
        final holding = sortedCardsInSuit(req.hand, card.suit);
        final isKorQ = card.rank == Rank.king || card.rank == Rank.queen;
        // "Supported" honors use play-aware adjacency: K from KT after the
        // queen and jack have been played is a solid sequence.
        final groups = groupsOfEffectivelyIdenticalCards(
            holding, round.previousTricks);
        final group = groups.firstWhere((g) => g.contains(card));
        final hasTouching = group.length >= 2;
        final hasHigher =
            holding.any((c) => c.rank.index > card.rank.index);
        if (isKorQ && holding.length >= 2 && !hasTouching && !hasHigher) {
          suspiciousLeads++;
          final dummyCards = req.dummyHand == null
              ? "?"
              : suitHolding(req.dummyHand!, card.suit);
          final dummyHasHonor = req.dummyHand != null &&
              req.dummyHand!.any((c) =>
                  c.suit == card.suit &&
                  c.rank.index > card.rank.index);
          if (dummyHasHonor) intoDummyHonor++;
          final hCard = chooseCardHeuristic(req, Random(1));
          if (hCard == card) heuristicAgreed++;
          print("deal $d trick ${round.previousTricks.length + 1} "
              "seat $seat (${contract.bid} by ${"NESW"[contract.declarer]}): "
              "led $card from ${suitHolding(req.hand, card.suit)} "
              "dummy=$dummyCards heuristic=$hCard"
              "${dummyHasHonor ? '  [INTO DUMMY HONOR]' : ''}");
          if (dump) {
            print("  hands: ${[
              for (final p in round.players)
                PlayingCard.stringFromCards(p.hand)
            ]}");
            print("  auction: ${round.bidHistory.map((b) => b.action).join(' ')}");
            print("  tricks so far: ${round.previousTricks.map((t) => PlayingCard.stringFromCards(t.cards)).join(' | ')}");
          }
        }
      }
      round.playCard(card);
    }
  }
  print("");
  print("defender leads: $defenderLeads; unsupported K/Q honor leads: "
      "$suspiciousLeads ($intoDummyHonor into a higher dummy honor; "
      "heuristic agreed with $heuristicAgreed)");
}
