/// Self-play harness for the SAYC bidding engine: deal random hands, run
/// full auctions, and flag suspicious results. Ported from the Python
/// reference implementation.
///
/// Hard failures (engine bugs):
///   exception        selectSaycBid threw
///   illegal-call     the chosen call is not legal in the auction
///   runaway-auction  the auction did not terminate
///   under-advertised the hand is below the minimums its own bid advertises
///   over-advertised  the hand exceeds the maximums its own bid advertises
///                    (partner may pass a hand that wanted to force on)
///
/// Heuristic result-quality flags (judgment, not necessarily bugs):
///   thin-game        non-preemptive game with < 24 combined total points
///   slam-light       undoubled slam with < 28 combined HCP
///   silly-strain     suit contract with <= 6 combined trumps
///   missed-game      declaring side with 26+ combined stopped below game
///                    (excused with an opponent suit unstopped, no major
///                    fit, and under 28 points: no game is attractive)
///   missed-slam      declaring side with 33+ combined HCP (or 36+ total
///                    points) stopped below the six level
///   passed-out       deal passed out despite 25+ combined points
library;

import 'dart:math';

import '../../cards/card.dart';
import '../bridge.dart';
import 'sayc_bidding.dart';

const hardFailureCategories = {
  "exception",
  "illegal-call",
  "runaway-auction",
  "under-advertised",
  "over-advertised",
};

const _maxCalls = 40;
// Injected chaos calls never pass, so legitimate fuzzed auctions can run
// well past the engine-only limit before three passes appear.
const _chaosMaxCalls = 100;

List<List<PlayingCard>> dealHands(int seed, int index) {
  final rng = Random(seed * 100003 + index);
  final deck = standardDeckCards()..shuffle(rng);
  return List.generate(4, (i) => deck.sublist(i * 13, (i + 1) * 13));
}

int _gameLevel(Suit? trump) => trump == null ? 3 : (isMajorSuit(trump) ? 4 : 5);

class SelfPlayFinding {
  final String category;
  final String message;

  SelfPlayFinding(this.category, this.message);

  @override
  String toString() => "$category: $message";
}

class SelfPlayResult {
  final List<BidAction> history;
  final List<SelfPlayFinding> findings;
  final int injectedCalls;

  SelfPlayResult(this.history, this.findings, [this.injectedCalls = 0]);
}

String _fmt(List<BidAction> history) =>
    history.isEmpty ? "(opening)" : history.map((c) => "$c").join(" ");

void _lintAdvertisement(HandAnalysis hand, int seat, BidAction call,
    BidMeaning meaning, List<BidAction> history, List<SelfPlayFinding> findings) {
  final problems = <String>[];
  final hcpLow = meaning.hcp?.low;
  if (hcpLow != null && hand.hcp < hcpLow) {
    problems.add("shows $hcpLow+ HCP, has ${hand.hcp}");
  }
  final totalLow = meaning.totalPoints?.low;
  if (totalLow != null && hand.totalPoints < totalLow) {
    problems.add("shows $totalLow+ total points, has ${hand.totalPoints}");
  }
  for (final suit in Suit.values) {
    final low = meaning.suitLengths[suit]?.low;
    if (low != null && hand.count(suit) < low) {
      problems.add("shows $low+ ${suit.name}, has ${hand.count(suit)}");
    }
  }
  if (problems.isNotEmpty) {
    findings.add(SelfPlayFinding(
        "under-advertised",
        "seat $seat bid $call after '${_fmt(history)}': "
        "${problems.join('; ')} [${meaning.description}]"));
  }

  final over = <String>[];
  final hcpHigh = meaning.hcp?.high;
  if (hcpHigh != null && hand.hcp > hcpHigh) {
    over.add("shows at most $hcpHigh HCP, has ${hand.hcp}");
  }
  final totalHigh = meaning.totalPoints?.high;
  if (totalHigh != null && hand.totalPoints > totalHigh) {
    over.add("shows at most $totalHigh total points, has ${hand.totalPoints}");
  }
  for (final suit in Suit.values) {
    final high = meaning.suitLengths[suit]?.high;
    if (high != null && hand.count(suit) > high) {
      over.add("shows at most $high ${suit.name}, has ${hand.count(suit)}");
    }
  }
  if (over.isNotEmpty) {
    findings.add(SelfPlayFinding(
        "over-advertised",
        "seat $seat bid $call after '${_fmt(history)}': "
        "${over.join('; ')} [${meaning.description}]"));
  }
}

void _lintResult(List<List<PlayingCard>> hands, List<BidAction> history,
    List<SelfPlayFinding> findings) {
  int? lastBidIndex;
  for (int i = history.length - 1; i >= 0; i--) {
    if (history[i].bidType == BidType.contract) {
      lastBidIndex = i;
      break;
    }
  }
  int combinedTotal(int parity) =>
      HandAnalysis(hands[parity]).totalPoints +
      HandAnalysis(hands[parity + 2]).totalPoints;
  int combinedHcp(int parity) =>
      highCardPointsOf(hands[parity]) + highCardPointsOf(hands[parity + 2]);

  if (lastBidIndex == null) {
    for (final parity in [0, 1]) {
      if (combinedTotal(parity) >= 25) {
        findings.add(SelfPlayFinding(
            "passed-out",
            "passed out with side $parity holding "
            "${combinedTotal(parity)} combined points"));
      }
    }
    return;
  }
  final contract = history[lastBidIndex].contractBid!;
  final side = lastBidIndex % 2;
  final doubled = history.sublist(lastBidIndex + 1).any((c) =>
      c.bidType == BidType.double || c.bidType == BidType.redouble);
  final trump = contract.trump;
  if (trump != null) {
    final trumps = hands[side].where((c) => c.suit == trump).length +
        hands[side + 2].where((c) => c.suit == trump).length;
    if (trumps <= 6) {
      findings.add(SelfPlayFinding("silly-strain",
          "contract $contract with only $trumps combined trumps"));
    }
  }
  final sideBids = [
    for (int i = 0; i < history.length; i++)
      if (i % 2 == side && history[i].bidType == BidType.contract)
        history[i].contractBid!
  ];
  final firstBid = sideBids.isEmpty ? null : sideBids.first;
  // A double-jump raise of the side's first suit (e.g. 1S-4S) is a
  // preemptive raise, not a strength-showing auction.
  final jumpRaised = firstBid != null &&
      sideBids.skip(1).any((b) =>
          b.trump != null &&
          b.trump == firstBid.trump &&
          b.count >= firstBid.count + 3);
  final preempted = firstBid != null &&
      firstBid.trump != null &&
      (firstBid.count >= 2 || jumpRaised);
  final atGame = contract.count >= _gameLevel(trump);
  if (atGame && !doubled && !preempted && combinedTotal(side) < 24) {
    findings.add(SelfPlayFinding(
        "thin-game", "$contract with ${combinedTotal(side)} combined points"));
  }
  if (contract.count >= 6 && !doubled && combinedHcp(side) < 28) {
    findings.add(SelfPlayFinding(
        "slam-light", "$contract with ${combinedHcp(side)} combined HCP"));
  }
  if (!atGame && !doubled && combinedTotal(side) >= 26) {
    // A partscore can be the right spot despite the points: with an
    // opponent-bid suit unstopped (3NT unattractive), no eight-card major
    // fit, and not enough for the five level, stopping in 4C/4D is at
    // worst unclear, so don't flag it.
    final oppSuits = {
      for (int i = 0; i < history.length; i++)
        if (i % 2 != side &&
            history[i].bidType == BidType.contract &&
            history[i].contractBid!.trump != null)
          history[i].contractBid!.trump!
    };
    bool stopped(Suit s) =>
        HandAnalysis(hands[side]).hasStopper(s) ||
        HandAnalysis(hands[side + 2]).hasStopper(s);
    final majorFit = [Suit.hearts, Suit.spades].any((s) =>
        hands[side].where((c) => c.suit == s).length +
            hands[side + 2].where((c) => c.suit == s).length >=
        8);
    final excused = oppSuits.any((s) => !stopped(s)) &&
        !majorFit &&
        combinedTotal(side) < 28;
    if (!excused) {
      // Only the declaring side: defenders selling out is a different (and
      // much harder) judgment problem.
      findings.add(SelfPlayFinding(
          "missed-game",
          "the declaring side has ${combinedTotal(side)} combined points but "
          "stopped in $contract"));
    }
  }
  if (contract.count < 6 &&
      !doubled &&
      (combinedHcp(side) >= 33 || combinedTotal(side) >= 36)) {
    findings.add(SelfPlayFinding(
        "missed-slam",
        "the declaring side has ${combinedHcp(side)} combined HCP "
        "(${combinedTotal(side)} total points) but stopped in $contract"));
  }
}

int highCardPointsOf(List<PlayingCard> hand) => HandAnalysis(hand).hcp;

/// A random legal non-pass call for fuzzing: usually a legal double/redouble
/// or one of the few cheapest contract bids, occasionally anything legal.
BidAction randomLegalCall(Random rng, List<BidAction> history) {
  final contracts = <BidAction>[
    for (int level = 1; level <= 7; level++)
      for (final trump in [...Suit.values, null])
        if (isLegalCall(BidAction.contract(level, trump), history))
          BidAction.contract(level, trump)
  ];
  contracts.sort((a, b) =>
      a.contractBid!.isHigherThan(b.contractBid!) ? 1 : -1);
  final candidates = <BidAction>[
    if (isLegalCall(BidAction.double(), history)) BidAction.double(),
    if (isLegalCall(BidAction.redouble(), history)) BidAction.redouble(),
    ...(rng.nextDouble() < 0.1 ? contracts : contracts.take(8)),
  ];
  if (candidates.isEmpty) return BidAction.pass();
  return candidates[rng.nextInt(candidates.length)];
}

/// Runs one auction. With `chaosRng` set, each call is replaced with a
/// random legal call with probability `chaosProbability`, fuzzing the
/// engine's responses to auctions it would never produce itself; injected
/// calls carry no meaning and are exempt from the lints.
SelfPlayResult runDeal(List<List<PlayingCard>> hands,
    {Random? chaosRng, double chaosProbability = 0}) {
  final history = <BidAction>[];
  final findings = <SelfPlayFinding>[];
  int injectedCalls = 0;
  // Seats that have had a call injected: their later engine calls are
  // premised on bids their hand never justified, so the advertisement
  // lints don't apply to them.
  final injectedSeats = <int>{};
  final maxCalls = chaosRng == null ? _maxCalls : _chaosMaxCalls;
  while (history.length < maxCalls) {
    final seat = history.length % 4;
    if (history.length >= 4 &&
        history
            .sublist(history.length - 3)
            .every((c) => c.bidType == BidType.pass)) {
      break;
    }
    if (chaosRng != null && chaosRng.nextDouble() < chaosProbability) {
      history.add(randomLegalCall(chaosRng, history));
      injectedCalls++;
      injectedSeats.add(seat);
      continue;
    }
    BidAction call;
    BidMeaning? meaning;
    try {
      final result = selectSaycBid(hands[seat], history);
      call = result.action;
      meaning = result.meaning;
    } catch (e) {
      findings.add(SelfPlayFinding("exception",
          "seat $seat after '${_fmt(history)}': ${e.runtimeType}: $e"));
      call = BidAction.pass();
    }
    if (!isLegalCall(call, history)) {
      findings.add(SelfPlayFinding(
          "illegal-call",
          "seat $seat chose $call after '${_fmt(history)}' "
          "[${meaning?.description ?? ''}]"));
      call = BidAction.pass();
      meaning = null;
    }
    if (meaning != null) {
      if (!injectedSeats.contains(seat)) {
        _lintAdvertisement(
            HandAnalysis(hands[seat]), seat, call, meaning, history, findings);
      }
      // Not a failure, but worth monitoring: a rule set existed for this
      // auction but no rule matched the hand, so the fallback bidder acted.
      if (meaning.description.startsWith("No rule matched")) {
        findings.add(SelfPlayFinding("no-rule-matched",
            "seat $seat (${HandAnalysis(hands[seat]).totalPoints} points) "
            "chose $call after '${_fmt(history)}'"));
      }
      // Also monitored: auctions with no rule set at all, where the
      // heuristic fallback acts and the call carries no meaning for
      // partner's or opponents' inference.
      if (meaning.description.startsWith("Fallback:") &&
          call.bidType != BidType.pass) {
        findings.add(SelfPlayFinding("fallback-used",
            "seat $seat chose $call after '${_fmt(history)}'"));
      }
    }
    history.add(call);
    if (history.length >= maxCalls) {
      findings.add(SelfPlayFinding("runaway-auction", _fmt(history)));
      break;
    }
  }
  _lintResult(hands, history, findings);
  return SelfPlayResult(history, findings, injectedCalls);
}
