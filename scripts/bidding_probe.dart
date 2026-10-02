/// Batch probe of the SAYC bidding engine: reads one position per line from
/// stdin and prints the engine's call and stated meaning, so many
/// hypotheses can be checked in one run (bridge_cli.dart starts a fresh
/// process per position).
///
///   dart run scripts/bidding_probe.dart < probes.txt
///
/// Line formats ('#' starts a note that is echoed with the result; a line
/// holding only a note prints it as a heading):
///
///   <hand> | <dealer-first history>             # note
///   auto: <hand0> / <hand1> / <hand2> / <hand3> [| <prefix>]   # note
///
/// Hands use suit groups, spades first, '-' for a void
/// ("AKQJ432 AKJ2 K2 -"). The first form shows the call of the player
/// next to bid; `auto:` bids all four seats (seat 0 deals) from the
/// optional prefix to the end of the auction.
library;

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/sayc/sayc_bidding.dart';

List<BidAction> parseHistory(String s) {
  final trimmed = s.trim();
  if (trimmed.isEmpty) return [];
  return trimmed.split(RegExp(r"[,\s]+")).map(BidAction.fromString).toList();
}

bool auctionOver(List<BidAction> history) =>
    history.length >= 4 &&
    history.sublist(history.length - 3).every((c) => c.bidType == BidType.pass);

void probeLine(String raw) {
  var line = raw;
  var note = "";
  final hashIndex = line.indexOf('#');
  if (hashIndex >= 0) {
    note = line.substring(hashIndex + 1).trim();
    line = line.substring(0, hashIndex);
  }
  if (line.trim().isEmpty) {
    if (note.isNotEmpty) print("## $note");
    return;
  }
  try {
    if (line.startsWith("auto:")) {
      final parts = line.substring(5).split('|');
      final hands = parts[0].split('/').map((h) => parseHand(h.trim())).toList();
      final history = parts.length > 1 ? parseHistory(parts[1]) : <BidAction>[];
      while (!auctionOver(history) && history.length < 60) {
        history.add(selectSaycBid(hands[history.length % 4], history).action);
      }
      print("[$note] ${history.join(' ')}");
      return;
    }
    final parts = line.split('|');
    final hand = parseHand(parts[0].trim());
    final history = parts.length > 1 ? parseHistory(parts[1]) : <BidAction>[];
    final result = selectSaycBid(hand, history);
    print("[$note] ${parts[0].trim()} | ${history.join(' ')} => "
        "${result.action}  -- ${result.meaning.summary()} "
        "(${result.meaning.description})");
  } catch (e) {
    print("[$note] ERROR $e :: $raw");
  }
}

Future<void> main() async {
  final lines = await stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .toList();
  lines.forEach(probeLine);
}
