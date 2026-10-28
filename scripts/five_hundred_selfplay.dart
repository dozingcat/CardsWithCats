// Duplicate self-play between two 500 AI strategies. Each deal is played
// twice with the strategies swapping teams, and the result is strategy A's
// average round score differential per deal (summed over both plays).
//
// dart run scripts/five_hundred_selfplay.dart --a=bid=sim,play=mc30 --b=bid=sim --deals=1000 --workers=8

import 'dart:isolate';
import 'dart:math';

import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/five_hundred/five_hundred.dart';
import 'package:cards_with_cats/five_hundred/five_hundred_ai.dart';

class Strategy {
  final FiveHundredBid? Function(FiveHundredRound round, int player, Random rng) bid;
  final Set<PlayingCard> Function(FiveHundredRound round, Random rng) discard;
  final CardChoice Function(FiveHundredRound round, Random rng) play;

  Strategy({required this.bid, required this.discard, required this.play});
}

FiveHundredBid? _neverBid(FiveHundredRound round, int player, Random rng) => null;

// The original placeholder: most of the trumps plus side aces plus two tricks
// from partner, in the best suit, never no trump.
FiveHundredBid? _simpleBid(FiveHundredRound round, int player, Random rng) {
  final high = highBid(round.bidHistory);
  if (high != null && high.player % numTeams == player % numTeams) {
    return null;
  }
  final hand = round.cardsForPlayer(player);
  double estimate(Suit trump) {
    final numTrumps = hand.where((c) => effectiveSuit(c, trump) == trump).length;
    final sideAces = hand.where((c) => c is SuitedCard && c.rank == .ace && effectiveSuit(c, trump) != trump).length;
    return 0.75 * numTrumps + sideAces + 2;
  }
  final suit = Suit.values.reduce((a, b) => estimate(a) >= estimate(b) ? a : b);
  for (int tricks = minimumBidTricks; tricks <= min(estimate(suit).floor(), maximumBidTricks); tricks++) {
    final bid = FiveHundredBid(tricks, suit);
    if (round.canCurrentBidderMakeBid(bid)) {
      return bid;
    }
  }
  return null;
}

// Names are comma separated options, e.g. "bid=sim,play=mc30,minDiff=-30".
//   bid: never, simple (the placeholder), sim (simulation based)
//   play: random, heuristic, mcN (Monte Carlo with N deals)
Strategy strategyForName(String name) {
  final opts = <String, String>{};
  for (final p in name.split(",")) {
    final kv = p.split("=");
    opts[kv[0]] = kv[1];
  }
  final hParams = HeuristicPlayParams(
    declarerPullsTrump: opts["hpull"] != "0",
    onlyWinWithSafeCards: opts["hsafe"] == "1",
    ruffWhenPossible: opts["hruff"] != "0",
    secondHandLow: opts["h2low"] == "1",
  );
  final discardParams = DiscardParams(
    createVoids: opts["dvoids"] != "0",
    guardedKingMinLength: int.parse(opts["dking"] ?? "2"),
  );
  CardChoice heuristic(FiveHundredRound round, Random rng) => chooseCardHeuristic(round, rng, hParams);
  final playName = opts["play"] ?? "heuristic";
  final CardChoice Function(FiveHundredRound, Random) play = switch (playName) {
    "random" => chooseCardRandom,
    "heuristic" => heuristic,
    _ when playName.startsWith("mc") => (round, rng) => chooseCardMonteCarlo(
        round, FiveHundredMonteCarloParams(
            numDeals: int.parse(playName.substring(2)),
            rolloutChooseFn: heuristic,
            auctionAttempts: int.parse(opts["playAuction"] ?? "0")), rng),
    _ => throw ArgumentError("Unknown play: $playName"),
  };
  final bidParams = FiveHundredBidParams(
    numDeals: int.parse(opts["bidDeals"] ?? "100"),
    minExpectedDifferential: double.parse(opts["minDiff"] ?? "30"),
    neverOutbidPartner: opts["outbidPartner"] != "1",
    auctionAttempts: int.parse(opts["bidAuction"] ?? "50"),
  );
  final bidName = opts["bid"] ?? "sim";
  final FiveHundredBid? Function(FiveHundredRound, int, Random) bid = switch (bidName) {
    "never" => _neverBid,
    "simple" => _simpleBid,
    "sim" => (round, player, rng) => chooseBid(round, player, rng, bidParams),
    _ => throw ArgumentError("Unknown bid: $bidName"),
  };
  Set<PlayingCard> discard(FiveHundredRound round, Random rng) => chooseDiscards(round, rng, discardParams);
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
  List<int> noTrump = [0, 0];
  List<int> sumBidTricks = [0, 0];
  List<int> sumTricks = [0, 0];
  List<int> sumDeclarerScore = [0, 0];

  void add(Stats o) {
    deals += o.deals;
    passedOut += o.passedOut;
    sumDiff += o.sumDiff;
    sumSqDiff += o.sumSqDiff;
    for (int i = 0; i < 2; i++) {
      declared[i] += o.declared[i];
      made[i] += o.made[i];
      noTrump[i] += o.noTrump[i];
      sumBidTricks[i] += o.sumBidTricks[i];
      sumTricks[i] += o.sumTricks[i];
      sumDeclarerScore[i] += o.sumDeclarerScore[i];
    }
  }
}

// Plays one deal with `strategies[team]` for each team. Returns team 0's
// score differential, and records bid stats with `strategyIndexForTeam`.
int playDeal(int dealSeed, List<Strategy> strategies, List<int> strategyIndexForTeam, FiveHundredRuleSet rules, Random rng, Stats stats) {
  final dealer = dealSeed % numPlayers;
  final round = FiveHundredRound.deal(rules: rules, scores: [0, 0], dealer: dealer, rng: Random(dealSeed));
  Strategy forPlayer(int p) => strategies[p % numTeams];
  while (round.status == FiveHundredRoundStatus.bidding && !round.isPassedOut()) {
    final p = round.currentBidder();
    round.addBid(PlayerBid(p, forPlayer(p).bid(round, p, rng)));
  }
  if (round.isPassedOut()) {
    stats.passedOut += 1;
    return 0;
  }
  final declarer = round.declarer();
  round.discard(forPlayer(declarer).discard(round, rng));
  while (!round.isOver()) {
    final (card, suit) = forPlayer(round.currentPlayerIndex()).play(round, rng);
    round.playCard(card, jokerLeadSuit: suit);
  }
  final declarerTeam = declarer % numTeams;
  final s = strategyIndexForTeam[declarerTeam];
  final bid = round.contract!.bid;
  stats.declared[s] += 1;
  stats.sumBidTricks[s] += bid.tricks;
  stats.sumTricks[s] += round.tricksTakenByTeam()[declarerTeam];
  stats.sumDeclarerScore[s] += round.contractScoresForTeams()[declarerTeam];
  if (bid.isNoTrump) stats.noTrump[s] += 1;
  if (round.didDeclarerMakeContract()) stats.made[s] += 1;
  return teamScoreDifferential(round, 0);
}

Stats runDeals(String nameA, String nameB, int firstDeal, int numDeals) {
  final a = strategyForName(nameA);
  final b = strategyForName(nameB);
  final rules = FiveHundredRuleSet();
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
  final nameB = opts["b"] ?? "bid=simple,play=random";
  final numDeals = int.parse(opts["deals"] ?? "1000");
  final firstDeal = int.parse(opts["start"] ?? "0");
  final workers = min(int.parse(opts["workers"] ?? "8"), 10);

  final t0 = DateTime.now();
  final perWorker = (numDeals / workers).ceil();
  final futures = <Future<Stats>>[];
  for (int w = 0; w < workers; w++) {
    final start = firstDeal + w * perWorker;
    final count = min(perWorker, firstDeal + numDeals - start);
    if (count <= 0) break;
    futures.add(Isolate.run(() => runDeals(nameA, nameB, start, count)));
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
  String avg(int x, int d) => d == 0 ? "-" : (x / d).toStringAsFixed(2);
  print("A=$nameA B=$nameB deals=$n time=${DateTime.now().difference(t0).inSeconds}s");
  print("A differential per deal (both seatings): ${mean.toStringAsFixed(2)} ± ${stdErr.toStringAsFixed(2)}");
  print("passed out: ${pct(total.passedOut, 2 * n)}");
  for (int i = 0; i < 2; i++) {
    final label = i == 0 ? "A" : "B";
    print("$label declared ${pct(total.declared[i], 2 * n)}, NT ${pct(total.noTrump[i], total.declared[i])}, "
        "avg bid ${avg(total.sumBidTricks[i], total.declared[i])} tricks, "
        "avg taken ${avg(total.sumTricks[i], total.declared[i])}, made ${pct(total.made[i], total.declared[i])}, "
        "avg declarer score ${avg(total.sumDeclarerScore[i], total.declared[i])}");
  }
}
