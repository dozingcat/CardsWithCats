/// Command-line interface to the SAYC bidding engine.
///
///   dart run scripts/bridge_cli.dart "A2 AKJT Q32 9876" "1H pass"
///   dart run scripts/bridge_cli.dart "" --describe 1NT
///   dart run scripts/bridge_cli.dart "pass 1S pass" --explain
///
/// Hands accept 13 cards ("AS QS 3S ...") or four suit groups, spades first
/// with '-' for a void ("A2 AKJT Q32 9876"). With --describe/--explain no
/// hand is needed and the first positional argument is the history.
/// Positions not yet ported report "(not ported yet)".
library;

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:cards_with_cats/bridge/bridge.dart';
import 'package:cards_with_cats/bridge/sayc/sayc_bidding.dart';

List<BidAction> parseHistory(String s) {
  final trimmed = s.trim();
  if (trimmed.isEmpty) return [];
  return trimmed
      .split(RegExp(r"[,\s]+"))
      .map(BidAction.fromString)
      .toList();
}

void main(List<String> args) {
  final positional = <String>[];
  String? describeArg;
  bool explain = false;
  for (int i = 0; i < args.length; i++) {
    if (args[i] == "--describe") {
      describeArg = args[++i];
    } else if (args[i] == "--explain") {
      explain = true;
    } else {
      positional.add(args[i]);
    }
  }

  if (explain || describeArg != null) {
    // The single positional argument (if any) is the history.
    final history = parseHistory(positional.isEmpty ? "" : positional[0]);
    if (describeArg != null) {
      final meaning =
          describeSaycCall(history, BidAction.fromString(describeArg));
      if (meaning == null) {
        print("No defined meaning for $describeArg in this auction "
            "(or position not ported yet)");
      } else {
        print("$describeArg shows: ${meaning.summary()} "
            "(${meaning.description})");
      }
    }
    if (explain) {
      final ex = explainSaycAuction(history);
      for (final entry in ex.calls) {
        if (entry.meaning == null) {
          print("${entry.action}: (no defined meaning)");
        } else {
          print("${entry.action}: ${entry.meaning!.summary()} "
              "(${entry.meaning!.description})");
        }
      }
      if (ex.players.isNotEmpty) {
        print("\nPlayer constraints (seat 1 = dealer):");
        final seats = ex.players.keys.toList()..sort();
        for (final seat in seats) {
          print("  Seat ${seat + 1}: ${ex.players[seat]!.summary()}");
        }
      }
    }
    return;
  }

  if (positional.isEmpty) {
    stderr.writeln(
        "Usage: bridge_cli <hand> [history] | <history> --describe CALL | "
        "<history> --explain");
    exit(64);
  }
  final hand = parseHand(positional[0]);
  final history = parseHistory(positional.length > 1 ? positional[1] : "");
  final result = selectSaycBid(hand, history);
  print("Bid: ${result.action}");
  print("Bid information: ${result.meaning.summary()} "
      "(${result.meaning.description})");
}
