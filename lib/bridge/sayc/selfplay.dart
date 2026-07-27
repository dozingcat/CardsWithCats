/// Self-play harness for the SAYC bidding engine: deal random hands, run
/// full auctions, and flag suspicious results. Ported from the Python
/// reference implementation.
///
/// Hard failures (engine bugs):
///   exception        selectSaycBid threw
///   illegal-call     the chosen call is not legal in the auction
///   runaway-auction  the auction did not terminate
///   under-advertised the hand is below the minimums its own bid advertises
///
/// Heuristic result-quality flags (judgment, not necessarily bugs):
///   thin-game        non-preemptive game with < 24 combined total points
///   slam-light       undoubled slam with < 28 combined HCP
///   silly-strain     suit contract with <= 6 combined trumps
///   missed-game      declaring side with 26+ combined stopped below game
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
};

const _maxCalls = 40;

List<List<PlayingCard>> dealHands(int seed, int index) {
  final rng = Random(seed * 100003 + index);
  final deck = standardDeckCards()..shuffle(rng);
  return List.generate(4, (i) => deck.sublist(i * 13, (i + 1) * 13));
}

int _gameLevel(Suit? trump) => trump == null ? 3 : (isMajorSuit(trump) ? 4 : 5);

bool isLegalCall(BidAction call, List<BidAction> history) {
  int? lastBidIndex;
  for (int i = history.length - 1; i >= 0; i--) {
    if (history[i].bidType == BidType.contract) {
      lastBidIndex = i;
      break;
    }
  }
  if (call.bidType == BidType.pass) return true;
  final n = history.length;
  if (call.bidType == BidType.contract) {
    if (lastBidIndex == null) return true;
    return call.contractBid!.isHigherThan(history[lastBidIndex].contractBid!);
  }
  if (lastBidIndex == null) return false;
  final since = history.sublist(lastBidIndex + 1);
  final doubled = since.any((c) => c.bidType == BidType.double);
  final redoubled = since.any((c) => c.bidType == BidType.redouble);
  final bidByOpponents = (n - lastBidIndex) % 2 == 1;
  if (call.bidType == BidType.double) {
    return bidByOpponents && !doubled && !redoubled;
  }
  return !bidByOpponents && doubled && !redoubled; // redouble
}

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

  SelfPlayResult(this.history, this.findings);
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
  BidAction? firstBid;
  for (int i = 0; i < history.length; i++) {
    if (i % 2 == side && history[i].bidType == BidType.contract) {
      firstBid = history[i];
      break;
    }
  }
  final preempted = firstBid != null &&
      firstBid.contractBid!.trump != null &&
      firstBid.contractBid!.count >= 2;
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
    // Only the declaring side: defenders selling out is a different (and
    // much harder) judgment problem.
    findings.add(SelfPlayFinding(
        "missed-game",
        "the declaring side has ${combinedTotal(side)} combined points but "
        "stopped in $contract"));
  }
}

int highCardPointsOf(List<PlayingCard> hand) => HandAnalysis(hand).hcp;

SelfPlayResult runDeal(List<List<PlayingCard>> hands) {
  final history = <BidAction>[];
  final findings = <SelfPlayFinding>[];
  while (history.length < _maxCalls) {
    final seat = history.length % 4;
    if (history.length >= 4 &&
        history
            .sublist(history.length - 3)
            .every((c) => c.bidType == BidType.pass)) {
      break;
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
      _lintAdvertisement(
          HandAnalysis(hands[seat]), seat, call, meaning, history, findings);
    }
    history.add(call);
    if (history.length >= _maxCalls) {
      findings.add(SelfPlayFinding("runaway-auction", _fmt(history)));
      break;
    }
  }
  _lintResult(hands, history, findings);
  return SelfPlayResult(history, findings);
}
