// Duplicate self-play between two Rook AI strategies. Each deal is played
// twice with the strategies swapping teams, and the result is strategy A's
// average round score differential per deal (summed over both plays).
//
// dart run scripts/rook_selfplay.dart --a=bid=sim,play=heuristic --b=bid=never,play=random --deals=2000 --workers=8

import 'dart:isolate';
import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/rook/rook.dart';
import 'package:cards_with_cats/rook/rook_ai.dart';

class Strategy {
  final int? Function(RookRound round, int player, Random rng) bid;
  final DiscardsAndTrump Function(RookRound round, Random rng) discard;
  final PlayingCard Function(RookRound round, Random rng) play;

  Strategy({required this.bid, required this.discard, required this.play});
}

int? _neverBid(RookRound round, int player, Random rng) => null;

// Always bids the minimum if nobody has bid, otherwise passes.
int? _bidMinimum(RookRound round, int player, Random rng) =>
    round.bidHistory.every((b) => b.isPass) ? round.rules.minimumBid : null;

PlayingCard Function(RookRound, Random) mcPlay(int numDeals, RookChooseCardFn rolloutFn) {
  final params = RookMonteCarloParams(numDeals: numDeals, rolloutChooseFn: rolloutFn);
  return (round, rng) => chooseCardMonteCarlo(round, params, rng);
}

// Names are comma separated options, e.g. "bid=sim,play=mc30,minDiff=-10".
//   bid: never, min (bid the minimum if nobody has bid), sim (simulation based)
//   play: random, heuristic, mcN (Monte Carlo with N deals)
//   minDiff, bidDeals: parameters for simulation based bidding
Strategy strategyForName(String name) {
  final opts = <String, String>{};
  for (final p in name.split(",")) {
    final kv = p.split("=");
    opts[kv[0]] = kv[1];
  }
  // Heuristic play options, also used for Monte Carlo rollouts.
  final hParams = HeuristicPlayParams(
    jokerCaptureMinPoints: int.parse(opts["hjoker"] ?? "10"),
    declarerPullsTrump: opts["hpull"] != "0",
    smearToPartner: opts["hsmear"] != "0",
    onlyWinWithSafeCards: opts["hsafe"] == "1",
    leadMastersBeforeTrump: opts["hmasters"] == "1",
    riskySmearMaxPoints: int.parse(opts["hrisky"] ?? "5"),
    countNestInLastTrick: opts["hnest"] == "1",
  );
  final discardParams = DiscardParams(
    trumpHighCardWeight: double.parse(opts["dhigh"] ?? "1.0"),
    pointCardKeepWeight: int.parse(opts["dpoints"] ?? "-300"),
    aceKeepWeight: int.parse(opts["dace"] ?? "5000"),
    createVoids: opts["dvoids"] != "0",
  );
  PlayingCard heuristic(RookRound round, Random rng) => chooseCardHeuristic(round, rng, hParams);
  final playName = opts["play"] ?? "heuristic";
  final PlayingCard Function(RookRound, Random) play = switch (playName) {
    "random" => chooseCardRandom,
    "heuristic" => heuristic,
    _ when playName.startsWith("mc") => mcPlay(int.parse(playName.substring(2)), heuristic),
    _ => throw ArgumentError("Unknown play: $playName"),
  };
  final bidParams = RookBidParams(
    numDeals: int.parse(opts["bidDeals"] ?? "200"),
    minExpectedDifferential: double.parse(opts["minDiff"] ?? "-70"),
    partnerBidBonus: double.parse(opts["partnerBonus"] ?? "0"),
    outbidPartnerMargin: opts.containsKey("outbidMargin") ? int.parse(opts["outbidMargin"]!) : null,
    respectRookLimit: opts["rookLimit"] != "0",
  );
  final bidName = opts["bid"] ?? "sim";
  final int? Function(RookRound, int, Random) bid = switch (bidName) {
    "never" => _neverBid,
    "min" => _bidMinimum,
    "sim" => (round, player, rng) => chooseBid(round, player, rng, bidParams),
    _ => throw ArgumentError("Unknown bid: $bidName"),
  };
  DiscardsAndTrump discard(RookRound round, Random rng) => chooseDiscardsAndTrump(round, rng, discardParams);
  return Strategy(bid: bid, discard: discard, play: play);
}

class Stats {
  int deals = 0;
  int passedOut = 0;
  double sumDiff = 0;
  double sumSqDiff = 0;
  // Index 0 is strategy A, 1 is B.
  List<int> declared = [0, 0];
  List<int> made = [0, 0];
  List<int> sumBid = [0, 0];
  List<int> sumDeclarerPoints = [0, 0];

  void add(Stats o) {
    deals += o.deals;
    passedOut += o.passedOut;
    sumDiff += o.sumDiff;
    sumSqDiff += o.sumSqDiff;
    for (int i = 0; i < 2; i++) {
      declared[i] += o.declared[i];
      made[i] += o.made[i];
      sumBid[i] += o.sumBid[i];
      sumDeclarerPoints[i] += o.sumDeclarerPoints[i];
    }
  }
}

// Plays one deal with `strategies[team]` for each team. Returns team 0's
// score differential, and records bid stats with `strategyIndexForTeam`.
int playDeal(int dealSeed, List<Strategy> strategies, List<int> strategyIndexForTeam, RookRuleSet rules, Random rng, Stats stats) {
  final dealer = dealSeed % numPlayers;
  final round = RookRound.deal(rules: rules, scores: [0, 0], dealer: dealer, rng: Random(dealSeed));
  Strategy forPlayer(int p) => strategies[p % numTeams];
  while (round.status == RookRoundStatus.bidding && !round.isPassedOut()) {
    final p = round.currentBidder();
    round.addBid(PlayerBid(p, forPlayer(p).bid(round, p, rng)));
  }
  if (round.isPassedOut()) {
    stats.passedOut += 1;
    return 0;
  }
  final declarer = round.declarer();
  final choice = forPlayer(declarer).discard(round, rng);
  round.discardAndChooseTrump(choice.discards, choice.trump);
  while (!round.isOver()) {
    round.playCard(forPlayer(round.currentPlayerIndex()).play(round, rng));
  }
  final declarerTeam = declarer % numTeams;
  final s = strategyIndexForTeam[declarerTeam];
  final points = round.teamPointsTaken()[declarerTeam];
  stats.declared[s] += 1;
  stats.sumBid[s] += round.contract!.bid;
  stats.sumDeclarerPoints[s] += points;
  if (points >= round.contract!.bid) {
    stats.made[s] += 1;
  }
  return teamScoreDifferential(round, 0);
}

Stats runDeals(String nameA, String nameB, int firstDeal, int numDeals, bool noPointDiscards) {
  final a = strategyForName(nameA);
  final b = strategyForName(nameB);
  final rules = RookRuleSet(allowDiscardingPointCards: !noPointDiscards);
  final stats = Stats();
  final rng = Random(firstDeal * 7919 + 1);
  for (int d = firstDeal; d < firstDeal + numDeals; d++) {
    final diffAFirst = playDeal(d, [a, b], [0, 1], rules, rng, stats);
    final diffBFirst = playDeal(d, [b, a], [1, 0], rules, rng, stats);
    final diff = diffAFirst - diffBFirst;
    stats.deals += 1;
    stats.sumDiff += diff;
    stats.sumSqDiff += diff * diff;
  }
  return stats;
}

Future<void> main(List<String> args) async {
  final opts = <String, String>{};
  for (final a in args) {
    final kv = a.replaceFirst("--", "").split("=");
    opts[kv[0]] = kv.length > 1 ? kv.sublist(1).join("=") : "true";
  }
  final nameA = opts["a"] ?? "bid=sim";
  final nameB = opts["b"] ?? "bid=never,play=random";
  final numDeals = int.parse(opts["deals"] ?? "1000");
  final firstDeal = int.parse(opts["start"] ?? "0");
  final workers = min(int.parse(opts["workers"] ?? "8"), 10);
  final noPointDiscards = opts["noPointDiscards"] == "true";

  final t0 = DateTime.now();
  final perWorker = (numDeals / workers).ceil();
  final futures = <Future<Stats>>[];
  for (int w = 0; w < workers; w++) {
    final start = firstDeal + w * perWorker;
    final count = min(perWorker, firstDeal + numDeals - start);
    if (count <= 0) break;
    futures.add(Isolate.run(() => runDeals(nameA, nameB, start, count, noPointDiscards)));
  }
  final total = Stats();
  for (final s in await Future.wait(futures)) {
    total.add(s);
  }
  final n = total.deals;
  final mean = total.sumDiff / n;
  final variance = total.sumSqDiff / n - mean * mean;
  final stdErr = sqrt(variance / n);
  String pct(int x, int d) => d == 0 ? "-" : "${(100.0 * x / d).toStringAsFixed(1)}%";
  String avg(int x, int d) => d == 0 ? "-" : (x / d).toStringAsFixed(1);
  print("A=$nameA B=$nameB deals=$n${noPointDiscards ? " (no point discards)" : ""} "
      "time=${DateTime.now().difference(t0).inSeconds}s");
  print("A differential per deal (both seatings): ${mean.toStringAsFixed(2)} ± ${stdErr.toStringAsFixed(2)}");
  print("passed out: ${pct(total.passedOut, 2 * n)}");
  for (int i = 0; i < 2; i++) {
    final label = i == 0 ? "A" : "B";
    print("$label declared ${pct(total.declared[i], 2 * n)} of rounds, avg bid ${avg(total.sumBid[i], total.declared[i])}, "
        "avg points ${avg(total.sumDeclarerPoints[i], total.declared[i])}, made ${pct(total.made[i], total.declared[i])}");
  }
}
