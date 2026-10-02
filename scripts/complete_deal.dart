/// Finds a full deal on which the SAYC engine, bidding all four seats,
/// produces a given auction prefix: the unknown hands are dealt at random
/// from the remaining cards until every seat's engine call matches. This
/// proves an auction position is reachable in AI-only play (the engine
/// itself makes every earlier call), and prints the deal in a form that
/// can be pasted into a test.
///
///   dart run scripts/complete_deal.dart "<dealer-first prefix>" \
///       <seat0 hand|_> <seat1 hand|_> <seat2 hand|_> <seat3 hand|_> \
///       [--tries N] [--seed N]
///
/// Seat 0 is the dealer. Hands use suit groups, spades first, '-' for a
/// void, quoted ("AKQJ432 AKJ2 K2 -"); "_" (or a quoted "?") leaves a seat
/// to be found.
/// Example (find the West overcaller and both East-West/partner hands):
///
///   dart run scripts/complete_deal.dart "1S 2C 2S pass 4NT pass" \
///       "AKQJ432 AKJ2 K2 -" _ _ _
library;

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/sayc/sayc_bidding.dart';
import 'package:cards_with_cats/cards/card.dart';

List<BidAction> parseHistory(String s) {
  final trimmed = s.trim();
  if (trimmed.isEmpty) return [];
  return trimmed.split(RegExp(r"[,\s]+")).map(BidAction.fromString).toList();
}

/// Whether the engine, holding [hand] in [seat], makes every call that
/// [history] gives that seat.
bool seatMatches(List<PlayingCard> hand, int seat, List<BidAction> history) {
  for (int i = seat; i < history.length; i += 4) {
    if (selectSaycBid(hand, history.sublist(0, i)).action != history[i]) {
      return false;
    }
  }
  return true;
}

void main(List<String> args) {
  int tries = 2000000;
  int seed = 1;
  final positional = <String>[];
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--tries":
        tries = int.parse(args[++i]);
      case "--seed":
        seed = int.parse(args[++i]);
      default:
        positional.add(args[i]);
    }
  }
  if (positional.length != 5) {
    stderr.writeln("Usage: complete_deal <history> <hand0|_> <hand1|_> "
        "<hand2|_> <hand3|_> [--tries N] [--seed N]");
    exit(64);
  }
  final history = parseHistory(positional[0]);
  final fixed = <int, List<PlayingCard>>{
    for (int s = 0; s < 4; s++)
      if (positional[s + 1] != "?" && positional[s + 1] != "_") s: parseHand(positional[s + 1]),
  };
  for (final entry in fixed.entries) {
    if (!seatMatches(entry.value, entry.key, history)) {
      print("Seat ${entry.key}'s given hand doesn't make its calls:");
      for (int i = entry.key; i < history.length; i += 4) {
        final r = selectSaycBid(entry.value, history.sublist(0, i));
        print("  after '${history.sublist(0, i).join(' ')}': engine "
            "${r.action} (${r.meaning.description}), auction ${history[i]}");
      }
      exit(1);
    }
  }
  final used = {for (final h in fixed.values) ...h};
  final remaining =
      standardDeckCards().where((c) => !used.contains(c)).toList();
  final open = [for (int s = 0; s < 4; s++) if (!fixed.containsKey(s)) s];
  // The last open seat gets whatever is left, so make it the seat with
  // the fewest non-pass calls (its constraints are most likely to hold).
  int nonPass(int s) => [
        for (int i = s; i < history.length; i += 4)
          if (history[i].bidType != BidType.pass) i
      ].length;
  open.sort((a, b) => nonPass(b).compareTo(nonPass(a)));

  final rng = Random(seed);
  for (int t = 0; t < tries; t++) {
    final deck = [...remaining]..shuffle(rng);
    final hands = Map<int, List<PlayingCard>>.from(fixed);
    bool ok = true;
    for (int k = 0; k < open.length; k++) {
      final h = deck.sublist(k * 13, (k + 1) * 13);
      if (!seatMatches(h, open[k], history)) {
        ok = false;
        break;
      }
      hands[open[k]] = h;
    }
    if (!ok) continue;
    final deal = [for (int s = 0; s < 4; s++) hands[s]!];
    print("Found after ${t + 1} tries:");
    for (int s = 0; s < 4; s++) {
      print('  "${handGroupString(deal[s])}",');
    }
    final full = [...history];
    while (full.length < 60 &&
        !(full.length >= 4 &&
            full.sublist(full.length - 3).every((c) => c.bidType == BidType.pass))) {
      final r = selectSaycBid(deal[full.length % 4], full);
      if (full.length >= history.length) {
        print("  seat ${full.length % 4}: ${r.action}  (${r.meaning.description})");
      }
      full.add(r.action);
    }
    print("Full auction: ${full.join(' ')}");
    return;
  }
  print("No deal found in $tries tries");
  exit(1);
}
