/// Solves self-play deals double dummy once and caches the trick tables, so
/// that dd_eval.dart can score bidding changes against par in seconds
/// instead of re-solving every deal.
///
///   DDS_LIB=native/libdds.dylib dart run scripts/dd_tables.dart \
///       --seed N --deals N [--start N] [--workers N] --out FILE
///
/// The file starts with a "# seed N" line, then one line per deal: its
/// index and 20 trick counts, for declarers 0-3 (dealer first) and strains
/// NT, clubs, diamonds, hearts, spades. --workers splits the deals across
/// child processes (see bidding_accuracy.dart for why processes).
library;

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:cards_with_cats/bridge/dds_ffi.dart';
import 'package:cards_with_cats/bridge/sayc/selfplay.dart';
import 'package:cards_with_cats/cards/card.dart';

final _strains = <Suit?>[null, ...Suit.values];

String _solveRange(int seed, int start, int end) {
  final dds = DdsBackend.instance!;
  final out = StringBuffer();
  for (int i = start; i < end; i++) {
    final hands = dealHands(seed, i);
    final row = [i];
    for (int declarer = 0; declarer < 4; declarer++) {
      for (final s in _strains) {
        final ns = dds.solve(hands, s, (declarer + 1) % 4, const [])!;
        row.add(declarer % 2 == 0 ? ns : 13 - ns);
      }
    }
    out.writeln(row.join(" "));
    if ((i + 1) % 100 == 0) stderr.write(".");
  }
  return out.toString();
}

Future<String> _solveInChild(int seed, int start, int end) async {
  final script = Platform.script.toFilePath();
  final child = await Process.start(Platform.resolvedExecutable, [
    if (script.endsWith(".dart")) script,
    "--seed", "$seed", "--start", "$start", "--deals", "${end - start}",
    "--child",
  ]);
  final out = StringBuffer();
  final done = child.stdout.transform(utf8.decoder).forEach(out.write);
  await child.stderr.forEach((bytes) {
    final text = utf8.decode(bytes).replaceAll(RegExp(r"[^.]"), "");
    if (text.isNotEmpty) stderr.write(text);
  });
  await done;
  if (await child.exitCode != 0) {
    stderr.writeln("worker for deals $start-${end - 1} failed");
    exit(1);
  }
  // Only the table rows: the DDS library logs its load to stdout.
  return out
      .toString()
      .split("\n")
      .where((l) => l.isNotEmpty && RegExp(r"^\d").hasMatch(l))
      .map((l) => "$l\n")
      .join();
}

Future<void> main(List<String> args) async {
  int seed = 1, deals = 1000, start = 0, workers = 1;
  String? outPath;
  bool child = false;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--seed":
        seed = int.parse(args[++i]);
      case "--deals":
        deals = int.parse(args[++i]);
      case "--start":
        start = int.parse(args[++i]);
      case "--workers":
        workers = int.parse(args[++i]);
      case "--out":
        outPath = args[++i];
      case "--child":
        child = true;
    }
  }
  if (DdsBackend.instance == null) {
    print("DDS backend unavailable; set DDS_LIB (cpp/build_libdds.sh)");
    exit(1);
  }
  final end = start + deals;
  if (child) {
    stdout.write(_solveRange(seed, start, end));
    return;
  }
  if (outPath == null) {
    print("--out FILE is required");
    exit(1);
  }
  final bounds = [
    for (int w = 0; w <= workers; w++) start + deals * w ~/ workers
  ];
  final parts = workers <= 1
      ? [_solveRange(seed, start, end)]
      : await Future.wait([
          for (int w = 0; w < workers; w++)
            _solveInChild(seed, bounds[w], bounds[w + 1]),
        ]);
  stderr.write("\n");
  File(outPath).writeAsStringSync("# seed $seed\n${parts.join()}");
  print("wrote $deals tables to $outPath");
}
