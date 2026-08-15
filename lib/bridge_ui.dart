import 'dart:async';
import 'dart:math';

import 'package:cards_with_cats/bridge/bridge_stats.dart';
import 'package:cards_with_cats/soundeffects.dart';
import 'package:cards_with_cats/stats/stats_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'bridge/sayc/sayc_bidding.dart';
import 'cards/round.dart';
import 'cards/trick.dart';
import 'common_ui.dart';
import 'cards/card.dart';
import 'cards/rollout.dart';
import 'bridge/bridge.dart';
import 'bridge/bridge_ai.dart';
import 'bridge/dd_solver.dart';
import 'bridge/dds_ffi.dart';

const debugOutput = false;

void printd(String msg) {
  if (debugOutput) print(msg);
}

PlayingCard computeCard(final CardToPlayRequest req) {
  try {
    // Monte Carlo with bid-aware deal sampling and exact double-dummy
    // endgame evaluation; see lib/bridge/PLAY_AI.md.
    final result = chooseCardMonteCarloDD(req, Random(),
        maxRounds: 50, ddTricksLimit: 7, maxTimeMillis: 2200);
    printd("Computed play: ${result.toString()}");
    return result.bestCard;
  } catch (e) {
    printd("MCDD failed ($e), falling back");
    final mcParams = MonteCarloParams(
        maxRounds: 30, rolloutsPerRound: 30, maxTimeMillis: 2500);
    final result =
        chooseCardMonteCarlo(req, mcParams, chooseCardRandom, Random());
    return result.bestCard;
  }
}

class DdResultRequest {
  final List<List<PlayingCard>> hands;
  final Suit? trump;
  final int leader;
  final int declarer;

  DdResultRequest(this.hands, this.trump, this.leader, this.declarer);
}

/// Tricks the declaring side takes double-dummy from the opening lead, or
/// null if no solver can answer within budget. Run via compute().
int? computeDoubleDummyDeclarerTricks(DdResultRequest req) {
  int? ns =
      DdsBackend.instance?.solve(req.hands, req.trump, req.leader, const []);
  // Without the native backend a full-deal solve can be very slow; give
  // the pure-Dart solver a bounded budget and omit the result on abort.
  ns ??= DDSolver.fromHands(req.hands, req.trump, req.leader)
      .solveWithNodeLimit(5000000);
  if (ns == null) return null;
  return req.declarer % 2 == 0 ? ns : 13 - ns;
}

class BridgeMatchDisplay extends StatefulWidget {
  final BridgeMatch Function() initialMatchFn;
  final BridgeMatch Function() createMatchFn;
  final void Function(BridgeMatch?) saveMatchFn;
  final void Function() mainMenuFn;
  final bool dialogVisible;
  final List<int> catImageIndices;
  final bool tintTrumpCards;
  final bool rotateDummyToTop;
  final Stream matchUpdateStream;
  final SoundEffectPlayer soundPlayer;
  final StatsStore statsStore;

  const BridgeMatchDisplay({
    super.key,
    required this.initialMatchFn,
    required this.createMatchFn,
    required this.saveMatchFn,
    required this.mainMenuFn,
    required this.dialogVisible,
    required this.catImageIndices,
    required this.tintTrumpCards,
    required this.rotateDummyToTop,
    required this.matchUpdateStream,
    required this.soundPlayer,
    required this.statsStore,
  });

  @override
  BridgeMatchState createState() => BridgeMatchState();
}

final baseSuitDisplayOrder = [
  Suit.spades,
  Suit.hearts,
  Suit.clubs,
  Suit.diamonds
];

class BridgeMatchState extends State<BridgeMatchDisplay> {
  final rng = Random();
  var animationMode = AnimationMode.none;
  bool isClaimingRemainingTricks = false;
  // Flag to keep the bidding dialog visible after bidding is completed, until
  // the player starts the round.
  bool showPostBidDialog = false;
  // Replaces the end-of-round dialog with the round details dialog.
  bool showRoundDetails = false;
  var aiMode = AiMode.humanPlayer0;
  int currentBidder = 0;
  Map<int, Mood> playerMoods = {};
  bool showScoreOverlay = false;
  late BridgeMatch match;
  late StreamSubscription matchUpdateSubscription;

  BridgeRound get round => match.currentRound;
  BridgeRound get duplicateRound => match.duplicateRound;

  // During play, hands/tricks/avatars can be rotated so the dummy is drawn at
  // the top of the display. Returns the offset to add to a player index to get
  // its display position; 0 if rotation is disabled or not applicable.
  int _displayRotation() {
    if (!widget.rotateDummyToTop) {
      return 0;
    }
    // Normal orientation while bidding and when showing all hands after the
    // round ends. Keep any rotation until the final trick is done animating.
    if (animationMode == AnimationMode.none && (round.status != BridgeRoundStatus.playing || round.isOver())) {
      return 0;
    }
    final contract = round.contract;
    if (contract == null) {
      return 0;
    }
    return (2 - contract.dummy) % 4;
  }

  int _displayIndexForPlayer(int playerIndex) =>
      (playerIndex + _displayRotation()) % 4;

  @override
  void initState() {
    super.initState();
    match = widget.initialMatchFn();
    matchUpdateSubscription = widget.matchUpdateStream.listen((event) {
      if (event is BridgeMatch) {
        _updateMatch(event);
      }
    });
    if (!duplicateRound.isOver()) {
      // Covers both a fresh round and a save made before the duplicate
      // round finished.
      _runDuplicateRound();
    }
    _scheduleNextActionIfNeeded();
  }

  @override
  void deactivate() {
    super.deactivate();
    matchUpdateSubscription.cancel();
  }

  void _updateMatch(BridgeMatch newMatch) {
    setState(() {
      match = newMatch;
      showPostBidDialog = false;
      _startRound();
    });
  }

  void _scheduleNextActionIfNeeded() {
    _scheduleNextAiBidIfNeeded();
    _scheduleNextAiPlayIfNeeded();
  }

  void _startRound() {
    _clearMoods();
    isClaimingRemainingTricks = false;
    showRoundDetails = false;
    _statsUpdatePending = false;
    if (round.isOver()) {
      match.finishRound();
    }
    if (match.isMatchOver()) {
      match = widget.createMatchFn();
    }
    widget.saveMatchFn(match);
    if (!duplicateRound.isOver()) {
      _runDuplicateRound();
    }
    _scheduleNextActionIfNeeded();
  }

  void _addBid(PlayerBid bid) {
    round.addBid(bid);
    if (round.status == BridgeRoundStatus.playing) {
      _handleBiddingDone();
    } else {
      _scheduleNextActionIfNeeded();
    }
    widget.saveMatchFn(match);
    if (round.isPassedOut()) {
      _updateStatsIfMatchOrRoundOver();
    }
  }

  void _makeBidForAiPlayer() {
    final playerIndex = round.currentBidder();
    final bid = selectSaycBid(
      round.players[playerIndex].hand,
      round.bidHistory.map((b) => b.action).toList(),
      vulnerability: round.vulnerability,
    );
    final playerBid = PlayerBid(playerIndex, bid.action);
    printd("P$playerIndex bids $bid");
    setState(() {
      _addBid(playerBid);
    });
  }

  void makeBidForHuman(PlayerBid bid) {
    setState(() {
      _addBid(bid);
    });
  }

  void resetBids() {
    setState(() {
      round.resetBidding();
      _scheduleNextActionIfNeeded();
    });
  }

  void undoLastHumanBid() {
    setState(() {
      round.undoBidsToPlayerIndex(0);
    });
  }

  bool _isWaitingForHumanBid() {
    return (round.status == BridgeRoundStatus.bidding &&
        aiMode == AiMode.humanPlayer0 &&
        round.currentBidder() == 0);
  }

  bool hasHumanPlayer() {
    return aiMode == AiMode.humanPlayer0;
  }

  void _handleBiddingDone() {
    if (hasHumanPlayer()) {
      setState(() {
        showPostBidDialog = true;
      });
    } else {
      Future.delayed(const Duration(milliseconds: 1000), () {
        _scheduleNextActionIfNeeded();
      });
    }
  }

  void _handlePostBidDialogConfirm() {
    setState(() {
      showPostBidDialog = false;
    });
    _scheduleNextActionIfNeeded();
  }

  void _scheduleNextAiBidIfNeeded() {
    if (round.status == BridgeRoundStatus.bidding && !_isWaitingForHumanBid()) {
      Future.delayed(const Duration(milliseconds: 1000), _makeBidForAiPlayer);
    }
  }

  void _scheduleNextAiPlayIfNeeded() {
    if (round.isOver()) {
      // printd("Round done, scores: ${round.pointsTaken().map((p) => p.totalRoundPoints)}");
    } else if (round.status == BridgeRoundStatus.playing &&
        !_isCurrentPlayerControlledByHuman()) {
      _computeAiPlay(minDelayMillis: 750);
    }
  }

  void _computeAiPlay({required int minDelayMillis}) async {
    // Do this in a separate thread/isolate. Note: `compute` has an overhead of
    // several hundred milliseconds in debug mode, but not in release mode.
    final t1 = DateTime.now().millisecondsSinceEpoch;
    try {
      printd("Starting isolate");
      final card =
          await compute(computeCard, CardToPlayRequest.fromRound(round));
      final elapsed = DateTime.now().millisecondsSinceEpoch - t1;
      final delayMillis = max(0, minDelayMillis - elapsed);
      printd("Delaying for $delayMillis ms");
      Future.delayed(
          Duration(milliseconds: delayMillis), () => _playCard(card));
    } catch (ex) {
      print("*** Exception in isolate: $ex");
      // final card = chooseCardToMakeBids(CardToPlayRequest.fromRound(round), rng);
      // _playCard(card);
    }
  }

  void _playCard(final PlayingCard card) {
    _clearMoods();
    if (round.status == BridgeRoundStatus.playing) {
      setState(() {
        round.playCard(card);
        animationMode = AnimationMode.movingTrickCard;
        // Hide the bidding dialog if it's still visible, which can happen
        // if the human player leads the first trick without dismissing it.
        showPostBidDialog = false;
      });
      widget.saveMatchFn(match);
      if (round.isOver() &&
          !duplicateRound.isOver() &&
          _runningDuplicate == null) {
        // Safety net: normally the replay started at the round's beginning.
        _runDuplicateRound();
      }
      _updateStatsIfMatchOrRoundOver();
    }
  }

  void _clearMoods() {
    playerMoods.clear();
  }

  void _updateMoodsAfterTrick() {
    playerMoods.clear();
    if (match.isMatchOver()) {
      switch (match.winningTeam()) {
        case 0:
          playerMoods[2] = .veryHappy;
          playerMoods[1] = playerMoods[3] = .mad;
          break;
        case 1:
          playerMoods[1] = playerMoods[3] = .veryHappy;
          playerMoods[2] = .mad;
      }
    }
    else if (round.isOver() && duplicateRound.isOver()) {
      int impDiff = BridgeMatch.impsForRounds(round, duplicateRound);
      // "Very happy" threshold is making a game when it went down in the
      // duplicate round, which is 400+50 -> 10 IMPs. Going down one extra trick
      // when vulnerable is 3 IMPs, "happy" needs slightly more than that.
      if (impDiff >= 10) {
        playerMoods[2] = .veryHappy;
        playerMoods[1] = playerMoods[3] = .mad;
      }
      else if (impDiff >= 4) {
        playerMoods[2] = .happy;
        playerMoods[1] = playerMoods[3] = .mad;
      }
      else if (impDiff <= -10) {
        playerMoods[1] = playerMoods[3] = .veryHappy;
        playerMoods[2] = .mad;
      }
      else if (impDiff <= -4) {
        playerMoods[1] = playerMoods[3] = .happy;
        playerMoods[2] = .mad;
      }
    }
    // Intentionally not setting moods during play when a contract is made or
    // defeated, since that could be expected (e.g. when preempting to prevent
    // the opponents' game, going down is expected and may give positive IMPs).
  }

  // Since there's always an AI winner and loser, playing happy/sad sounds for
  // them would be redundant. Instead only play a mad sound if a round is over
  // and one of the sides is "mad" because they lost by several IMPs.
  void _playSoundsForMoods() {
    if (match.isMatchOver()) {
      return;
    }
    if (playerMoods.containsValue(Mood.mad)) {
      widget.soundPlayer.playMadSound();
    }
  }

  // Double-dummy result of the finished round's contract, computed once
  // per round in a background isolate for the end-of-round dialog.
  BridgeRound? _ddResultRound;
  int? _ddDeclarerTricks;
  bool _ddComputeInFlight = false;

  void _ensureDoubleDummyResult() {
    if (!round.isOver() || round.contract == null) return;
    if (identical(_ddResultRound, round) || _ddComputeInFlight) return;
    _ddComputeInFlight = true;
    final target = round;
    final req = DdResultRequest(
      [for (int p = 0; p < 4; p++) target.originalHandForPlayer(p)],
      target.contract!.bid.trump,
      (target.contract!.declarer + 1) % 4,
      target.contract!.declarer,
    );
    compute(computeDoubleDummyDeclarerTricks, req).then((tricks) {
      _ddComputeInFlight = false;
      if (!mounted) return;
      setState(() {
        _ddResultRound = target;
        _ddDeclarerTricks = tricks;
      });
    });
  }

  // Set when the human's round ends; stats are recorded once both the
  // round and its duplicate replay have finished (the replay usually
  // completes first, but not always). Deliberately not persisted:
  // restoring a save made after a round ended skips that round's stats
  // rather than risk double counting.
  bool _statsUpdatePending = false;

  void _updateStatsIfMatchOrRoundOver() {
    if (round.isOver()) {
      _statsUpdatePending = true;
      _updateStatsIfPendingAndDuplicateDone();
    }
  }

  void _updateStatsIfPendingAndDuplicateDone() async {
    if (!_statsUpdatePending || !round.isOver() || !duplicateRound.isOver()) {
      return;
    }
    _statsUpdatePending = false;
    final currentStats =
        (await widget.statsStore.readBridgeStats()) ?? BridgeStats.empty();
    var newStats = currentStats.updateFromRound(round, duplicateRound);
    if (match.isMatchOver()) {
      newStats = newStats.updateFromMatch(match);
    }
    widget.statsStore.writeBridgeStats(newStats);
  }

  // The duplicate round in progress, if any. Used to avoid double-starting
  // a replay that's already running.
  BridgeRound? _runningDuplicate;

  /// (Re)starts the AI replay of the current deal. The replay involves no
  /// human input, so it's kicked off as soon as a round starts and runs
  /// concurrently with the human's play (each AI card computed off the UI
  /// thread); by the time the round ends it's usually already finished.
  void _runDuplicateRound() {
    final dup = round.copyAndReset();
    match.duplicateRound = dup;
    _runningDuplicate = dup;
    _continueDuplicateRound(dup);
  }

  void _continueDuplicateRound(BridgeRound dup) async {
    // print("*** Starting duplicate round");
    try {
      while (!dup.isOver()) {
        // Stop if a newer duplicate round replaced this one, or the widget
        // is gone.
        if (!identical(dup, match.duplicateRound) || !mounted) {
          return;
        }
        if (dup.status == .bidding) {
          final playerIndex = dup.currentBidder();
          final bid = selectSaycBid(
            dup.players[playerIndex].hand,
            dup.bidHistory.map((b) => b.action).toList(),
            vulnerability: dup.vulnerability,
          );
          // print("*** Bid: ${bid.action}");
          dup.addBid(PlayerBid(playerIndex, bid.action));
        } else {
          final card =
              await compute(computeCard, CardToPlayRequest.fromRound(dup));
          if (!identical(dup, match.duplicateRound) || !mounted) {
            return;
          }
          // print("*** Play: $card");
          dup.playCard(card);
        }
        if (round.isOver()) {
          // The duplicate progress indicator is visible; update it.
          setState(() {});
        }
        await Future.delayed(const Duration(milliseconds: 10));
      }
      if (mounted) {
        setState(() {});
      }
      // Save so the completed duplicate round and IMP totals persist.
      widget.saveMatchFn(match);
      _updateStatsIfPendingAndDuplicateDone();
    } finally {
      // Clear even on abnormal exit so the safety-net restarts aren't
      // blocked by a stale reference.
      if (identical(_runningDuplicate, dup)) {
        _runningDuplicate = null;
      }
    }
  }

  List<Suit> _suitDisplayOrder() {
    final trump = round.trumpSuit();
    if (trump == null) {
      return [Suit.spades, Suit.hearts, Suit.clubs, Suit.diamonds];
    }
    // Trump suit first.
    switch (trump) {
      case Suit.spades:
        return [Suit.spades, Suit.hearts, Suit.clubs, Suit.diamonds];
      case Suit.hearts:
        return [Suit.hearts, Suit.spades, Suit.diamonds, Suit.clubs];
      case Suit.diamonds:
        return [Suit.diamonds, Suit.spades, Suit.hearts, Suit.clubs];
      case Suit.clubs:
        return [Suit.clubs, Suit.hearts, Suit.spades, Suit.diamonds];
    }
  }

  void _trickCardAnimationFinished() {
    if (!round.isOver() && round.currentTrick.cards.isNotEmpty) {
      setState(() {
        animationMode = AnimationMode.none;
      });
      _scheduleNextActionIfNeeded();
    } else {
      setState(() {
        animationMode = AnimationMode.movingTrickToWinner;
        _updateMoodsAfterTrick();
        _playSoundsForMoods();
      });
    }
  }

  void _trickToWinnerAnimationFinished() {
    setState(() {
      animationMode = AnimationMode.none;
    });
    if (_shouldLeaderClaimRemainingTricks()) {
      setState(() {
        isClaimingRemainingTricks = true;
      });
    } else {
      _scheduleNextActionIfNeeded();
    }
  }

  bool _shouldLeaderClaimRemainingTricks() {
    return shouldLeaderClaimRemainingTricks(round, trump: round.trumpSuit());
  }

  void _handleClaimTricksDialogOk() {
    claimRemainingTricks(round);
    setState(() {
      isClaimingRemainingTricks = false;
    });
    widget.saveMatchFn(match);
    _updateMoodsAfterTrick();
    _playSoundsForMoods();
    // Safety net only: the replay normally started at the round's
    // beginning and must not be restarted if it's running or done.
    if (!duplicateRound.isOver() && _runningDuplicate == null) {
      _runDuplicateRound();
    }
    _updateStatsIfMatchOrRoundOver();
  }

  bool _isPlayerControlledByHuman(int pnum) {
    int? declarer = round.contract?.declarer;
    return (pnum == 0 || (pnum == 2 && (declarer == 0 || declarer == 2)));
  }

  bool _isCurrentPlayerControlledByHuman() {
    return _isPlayerControlledByHuman(round.currentPlayerIndex());
  }

  bool _shouldIgnoreCardClick() {
    return (widget.dialogVisible || _shouldShowClaimTricksDialog());
  }

  void handleHandCardClicked(final PlayingCard card) {
    printd(
        "Clicked ${card.toString()}, status: ${round.status}, index: ${round.currentPlayerIndex()}");
    if (_shouldIgnoreCardClick()) {
      return;
    }
    if (round.status == BridgeRoundStatus.playing &&
        _isCurrentPlayerControlledByHuman()) {
      if (round.legalPlaysForCurrentPlayer().contains(card)) {
        printd("Playing");
        _playCard(card);
      }
    }
  }

  PlayerHandParams _humanNonDummyHand(final Layout layout) {
    final declarer = round.contract?.declarer;
    int playerIndex = declarer == 2 ? 2 : 0;
    bool isPlayingNextCard = round.status == BridgeRoundStatus.playing &&
        round.currentPlayerIndex() == playerIndex;
    bool isBidding = round.status == BridgeRoundStatus.bidding;
    final cards = round.players[playerIndex].hand;
    List<PlayingCard> highlightedCards = [];
    if (isBidding) {
      highlightedCards = cards;
    } else if (isPlayingNextCard) {
      highlightedCards = round.legalPlaysForCurrentPlayer();
    }

    final playerTrickCard = lastCardPlayedByPlayer(
      playerIndex: playerIndex,
      numberOfPlayers: round.numberOfPlayers,
      currentTrick: round.currentTrick,
      previousTricks: round.previousTricks,
    );

    final previousPlayerCards =
        (playerTrickCard != null) ? [...cards, playerTrickCard] : null;
    // Flutter needs a key property to determine whether the PlayerHandCards
    // component has changed between renders.
    var key = "H${cards.map((c) => c.toString()).join()}";
    if (playerTrickCard != null) {
      key += ":${playerTrickCard.toString()}";
    }

    return PlayerHandParams(
      key: Key(key),
      playerIndex: _displayIndexForPlayer(playerIndex),
      cards: cards,
      highlightedCards: highlightedCards,
      animateFromCards: previousPlayerCards,
      onCardClicked: handleHandCardClicked,
      // The human's hand can be at a side position when rotating the dummy to
      // the top; there's no avatar there, so draw closer to the edge.
      leaveAvatarSpace: false,
    );
  }

  PlayerHandParams? _dummyHand(final Layout layout) {
    int? dummyPlayer = round.visibleDummy();
    if (dummyPlayer == null) {
      return null;
    }
    assert(round.status == BridgeRoundStatus.playing);

    bool isPlayingNextCard = round.currentPlayerIndex() == dummyPlayer;
    final cards = round.players[dummyPlayer].hand;
    List<PlayingCard> highlightedCards = [];
    if (isPlayingNextCard) {
      highlightedCards = round.legalPlaysForCurrentPlayer();
    }

    final lastPlayedCard = lastCardPlayedByPlayer(
      playerIndex: dummyPlayer,
      numberOfPlayers: round.numberOfPlayers,
      currentTrick: round.currentTrick,
      previousTricks: round.previousTricks,
    );
    final previousPlayerCards =
        (lastPlayedCard != null) ? [...cards, lastPlayedCard] : null;
    var key = "H${cards.map((c) => c.toString()).join()}";
    if (lastPlayedCard != null) {
      key += ":${lastPlayedCard.toString()}";
    }

    return PlayerHandParams(
      key: Key(key),
      playerIndex: _displayIndexForPlayer(dummyPlayer),
      displayStyle: HandDisplayStyle.dummy,
      cards: cards,
      highlightedCards: highlightedCards,
      animateFromCards: previousPlayerCards,
      onCardClicked: handleHandCardClicked,
    );
  }

  List<PlayerHandParams> _handsToShowForClaim(Layout layout) {
    if (!_shouldShowClaimTricksDialog() || round.contract == null) {
      return [];
    }
    List<int> playersToShow = switch (round.contract!.declarer) {
      0 => [1, 3],
      1 => [1, 2],
      2 => [1, 3],
      3 => [2, 3],
      _ => [],
    };
    return playersToShow
        .map((p) => PlayerHandParams(
              playerIndex: _displayIndexForPlayer(p),
              cards: round.players[p].hand,
              highlightedCards: p == round.currentTrick.leader
                  ? round.players[p].hand
                  : const [],
            ))
        .toList();
  }

  Widget allHandsForDebugging(Layout layout) {
    final params = [0, 1, 2, 3]
        .map((p) => PlayerHandParams(
              playerIndex: _displayIndexForPlayer(p),
              cards: round.players[p].hand,
              highlightedCards: [],
              onCardClicked: handleHandCardClicked,
            ))
        .toList();
    return MultiplePlayerHandCards(
      layout: layout,
      playerHands: params,
      suitOrder: _suitDisplayOrder(),
      trumpSuit: widget.tintTrumpCards ? round.trumpSuit() : null,
    );
  }

  Widget allHandsForPostRound(Layout layout) {
    final params = [0, 1, 2, 3]
        .map((p) => PlayerHandParams(
            playerIndex: p,
            cards: round.originalHandForPlayer(p),
            highlightedCards: [],
          ))
        .toList();
    return MultiplePlayerHandCards(
      layout: layout,
      playerHands: params,
      suitOrder: _suitDisplayOrder(),
      trumpSuit: widget.tintTrumpCards ? round.trumpSuit() : null,
    );

  }

  Widget _playerCards(layout) {
    final humanHand = _humanNonDummyHand(layout);
    final dummyHand = _dummyHand(layout);
    final claimHands = _handsToShowForClaim(layout);
    final allHands = [
      humanHand,
      if (dummyHand != null) dummyHand,
      ...claimHands,
    ];

    return MultiplePlayerHandCards(
      layout: layout,
      playerHands: allHands,
      suitOrder: _suitDisplayOrder(),
      trumpSuit: widget.tintTrumpCards ? round.trumpSuit() : null,
    );
  }

  Widget _trickCards(final Layout layout) {
    List<DisplayedHand> displayedHands = [];
    final declarer = round.contract?.declarer;
    final humanNonDummyPlayer = declarer == 2 ? 2 : 0;
    displayedHands.add(DisplayedHand(
        playerIndex: _displayIndexForPlayer(humanNonDummyPlayer),
        cards: round.players[humanNonDummyPlayer].hand,
        leaveAvatarSpace: false));
    final dummyIndex = round.visibleDummy();
    if (dummyIndex != null) {
      displayedHands.add(DisplayedHand(
          playerIndex: _displayIndexForPlayer(dummyIndex),
          cards: round.players[dummyIndex].hand,
          displayStyle: HandDisplayStyle.dummy));
    }

    // The trick data stores logical player indices; rotate leaders and
    // winners to display positions if needed.
    final rotation = _displayRotation();
    final displayCurrentTrick = (rotation == 0)
        ? round.currentTrick
        : TrickInProgress((round.currentTrick.leader + rotation) % 4,
            round.currentTrick.cards);
    final displayPreviousTricks = (rotation == 0)
        ? round.previousTricks
        : [
            ...round.previousTricks.map((t) => Trick(
                (t.leader + rotation) % 4, t.cards, (t.winner + rotation) % 4))
          ];

    return TrickCards(
      layout: layout,
      currentTrick: displayCurrentTrick,
      previousTricks: displayPreviousTricks,
      displayedHands: displayedHands,
      trumpSuit: widget.tintTrumpCards ? round.trumpSuit() : null,
      animationMode: animationMode,
      numPlayers: 4,
      suitOrder: _suitDisplayOrder(),
      onTrickCardAnimationFinished: _trickCardAnimationFinished,
      onTrickToWinnerAnimationFinished: _trickToWinnerAnimationFinished,
    );
  }

  bool _shouldShowBidDialog() {
    return !widget.dialogVisible
        && !round.isPassedOut()
        && (round.status == BridgeRoundStatus.bidding || showPostBidDialog);
  }

  bool _shouldShowClaimTricksDialog() {
    return !widget.dialogVisible && isClaimingRemainingTricks;
  }

  bool _shouldShowEndOfRoundDialog() {
    // animationMode check allows the last trick animation to complete.
    return !widget.dialogVisible && round.isOver() && animationMode == AnimationMode.none;
  }

  bool _isPlayInProgress() {
    return round.status == BridgeRoundStatus.playing &&
        round.contract != null &&
        !round.isOver() &&
        !showPostBidDialog &&
        !isClaimingRemainingTricks;
  }

  bool _shouldShowScoreOverlayToggle() {
    return !widget.dialogVisible && _isPlayInProgress();
  }

  bool _shouldShowScoreOverlay() {
    return showScoreOverlay && !widget.dialogVisible && _isPlayInProgress();
  }

  Widget _scoreOverlayButton() {
    return Opacity(opacity: 0.6, child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 80, 10, 10),
      child: FloatingActionButton(
        onPressed: () {
          setState(() {
            showScoreOverlay = !showScoreOverlay;
          });
        },
        child: Icon(showScoreOverlay ? Icons.search_off : Icons.search),
      ),
    ));
  }

  Widget _scoreOverlay() {
    final contract = round.contract!;
    final declarerTricks = round.numTricksWonByDeclarer();
    final defenderTricks = round.previousTricks.length - declarerTricks;
    final declarerIsNS = contract.declarer % 2 == 0;
    final nsTricks = declarerIsNS ? declarerTricks : defenderTricks;
    final ewTricks = declarerIsNS ? defenderTricks : declarerTricks;

    final message = [
      contractDescription(contract),
      "Vulnerable: ${vulnerabilityDescription(round.vulnerability)}",
      "N-S tricks: $nsTricks",
      "E-W tricks: $ewTricks",
    ].join("\n");

    final overlay = Center(
        child: Container(
            decoration: BoxDecoration(
                color: const Color.fromARGB(208, 255, 255, 255),
                border: Border.all(
                  color: const Color.fromARGB(128, 0, 0, 0),
                ),
                borderRadius: const BorderRadius.all(Radius.circular(20))),
            child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color.fromARGB(224, 0, 0, 0),
                      fontSize: 18,
                    )))));

    return TweenAnimationBuilder(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 250),
      child: overlay,
      builder: (BuildContext context, double opacity, Widget? child) {
        return Opacity(opacity: opacity, child: child);
      },
    );
  }

  void _showMainMenuAfterMatch() {
    widget.saveMatchFn(null);
    widget.mainMenuFn();
  }

  @override
  Widget build(BuildContext context) {
    final layout = computeLayout(context);
    _ensureDoubleDummyResult();
    final showAllHands = false;

    return Stack(
      children: [
        // AI player images are drawn here rather than in the main app so
        // that they can rotate with the hands when the dummy is shown at top.
        ...[1, 2, 3].map((i) => AiPlayerImage(
            layout: layout,
            playerIndex: _displayIndexForPlayer(i),
            catImageIndex: widget.catImageIndices[i])),
        if (!showAllHands && !_shouldShowEndOfRoundDialog()) _playerCards(layout),
        if (showAllHands && !_shouldShowEndOfRoundDialog()) allHandsForDebugging(layout),
        if (_shouldShowEndOfRoundDialog()) allHandsForPostRound(layout),
        _trickCards(layout),
        if (_shouldShowBidDialog())
          BidDialog(
            layout: layout,
            round: round,
            onBid: makeBidForHuman,
            onResetBids: undoLastHumanBid,
            onConfirmContract: _handlePostBidDialogConfirm,
            catImageIndices: widget.catImageIndices,
          ),
        if (_shouldShowClaimTricksDialog())
          ClaimRemainingTricksDialog(onOk: _handleClaimTricksDialogOk),
        if (_shouldShowEndOfRoundDialog() && !showRoundDetails)
          EndOfRoundDialog(
            layout: layout,
            match: match,
            duplicateRound: duplicateRound,
            doubleDummyDeclarerTricks:
                identical(_ddResultRound, round) ? _ddDeclarerTricks : null,
            onContinue: () => setState(_startRound),
            onMainMenu: _showMainMenuAfterMatch,
            // Uncomment to show button to replay duplicate round.
            // onReplayDuplicateRound: _runDuplicateRound,
            onShowDetails: duplicateRound.isOver()
                ? () => setState(() => showRoundDetails = true)
                : null,
          ),
        if (_shouldShowEndOfRoundDialog() && showRoundDetails)
          RoundDetailsDialog(
            layout: layout,
            round: round,
            duplicateRound: duplicateRound,
            onClose: () => setState(() => showRoundDetails = false),
          ),
        PlayerMoods(layout: layout, moods: playerMoods, durationMillis: 5000),
        if (_shouldShowScoreOverlay()) _scoreOverlay(),
        if (_shouldShowScoreOverlayToggle()) _scoreOverlayButton(),
      ],
    );
  }
}

const dialogBackgroundColor = Color.fromARGB(0x80, 0xd8, 0xd8, 0xd8);

/// The auction as a table, one column per seat, with tap-to-explain of any
/// call's SAYC meaning. Used while bidding (BidDialog, with "You"/cat image
/// headers) and when reviewing a finished round (with seat letter headers).
class BidHistoryTable extends StatefulWidget {
  final BridgeRound round;
  // Exactly four header cells, in player index order.
  final List<Widget> headerCells;

  const BidHistoryTable({
    super.key,
    required this.round,
    required this.headerCells,
  });

  @override
  State<BidHistoryTable> createState() => _BidHistoryTableState();
}

class _BidHistoryTableState extends State<BidHistoryTable> {
  int? explainBidRow;
  int explainBidColumn = 0;

  @override
  Widget build(BuildContext context) {
    final bidHistory = widget.round.bidHistory;
    final dealer = widget.round.dealer;
    final isBiddingOver = widget.round.contract != null || widget.round.isPassedOut();
    final numberOfBidRows = ((dealer + bidHistory.length + (isBiddingOver ? 0 : 1)) / 4).ceil();

    Widget bidCell({required int rowIndex, required int playerIndex}) {
      int bidIndex = 4 * rowIndex + playerIndex - dealer;
      if (bidIndex == bidHistory.length && !isBiddingOver) {
        return const Text("?", textAlign: TextAlign.center);
      }
      if (bidIndex < 0 || bidIndex >= bidHistory.length) {
        return const SizedBox();
      }

      final isExplainingBid = explainBidRow == rowIndex && explainBidColumn == playerIndex;
      return GestureDetector(
          onTap: () {
            setState(() {
              if (isExplainingBid) {
                explainBidRow = null;
              }
              else {
                explainBidRow = rowIndex;
                explainBidColumn = playerIndex;
              }
            });
          },
          child: Container(
            color: isExplainingBid ? Colors.white : Colors.transparent,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(
              bidHistory[bidIndex].action.symbolString(),
              textAlign: TextAlign.center))),
      );
    }

    Widget bidExplanation() {
      int bidIndex = 4 * explainBidRow! + explainBidColumn - dealer;
      if (bidIndex >= bidHistory.length) {
        return const SizedBox();
      }
      final bidsUpToSelection = bidHistory.sublist(0, bidIndex).map((b) => b.action).toList();
      final meaning = describeSaycCall(bidsUpToSelection, bidHistory[bidIndex].action);
      return Padding(padding: EdgeInsets.only(bottom: 5), child: Container(
        width: 200,
        color: Colors.white70,
        child: paddingAll(4, Text(
          meaning != null ? meaning.description : "No specific meaning",
          style: const TextStyle(fontSize: 10),
        )),
      ));
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      paddingAll(
          10,
          Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              TableRow(children: widget.headerCells),
              ...[
                for (var row = 0; row < numberOfBidRows; row += 1)
                  TableRow(children: [
                    bidCell(rowIndex: row, playerIndex: 0),
                    bidCell(rowIndex: row, playerIndex: 1),
                    bidCell(rowIndex: row, playerIndex: 2),
                    bidCell(rowIndex: row, playerIndex: 3),
                  ])
              ]
            ],
          )),
      if (explainBidRow != null) bidExplanation(),
    ]);
  }
}

class BidDialog extends StatefulWidget {
  final Layout layout;
  final BridgeRound round;
  final void Function(PlayerBid) onBid;
  final void Function() onResetBids;
  final void Function() onConfirmContract;
  final List<int> catImageIndices;

  const BidDialog({
    super.key,
    required this.layout,
    required this.round,
    required this.onBid,
    required this.onResetBids,
    required this.onConfirmContract,
    required this.catImageIndices,
  });

  @override
  State<BidDialog> createState() => _BidDialogState();
}

class _BidDialogState extends State<BidDialog> {
  ContractBid contractBid = ContractBid(1, Suit.clubs);

  @override
  Widget build(BuildContext context) {
    const adjustBidTextStyle = TextStyle(fontSize: 18, height: 0);
    const headerFontSize = 14.0;
    const cellPad = 4.0;
    const rowPadding = 15.0;

    Widget headerCell(String msg) => paddingAll(
        cellPad,
        Text(msg,
            textAlign: TextAlign.right,
            style: const TextStyle(
                fontSize: headerFontSize, fontWeight: FontWeight.bold)));

    Widget catImageCell(int imageIndex) {
      const imageHeight = headerFontSize * 1.3;
      const padding = headerFontSize * 0.85;
      return paddingHorizontal(padding,
          Image.asset(catImageForIndex(imageIndex), height: imageHeight));
    }

    final bidHistory = widget.round.bidHistory;
    final dealer = widget.round.dealer;
    final isBiddingOver = widget.round.contract != null || widget.round.isPassedOut();
    final hasHumanBid = bidHistory.any((b) => b.player == 0);

    bool canDecrementBid() {
      return contractBid.count > 1;
    }

    bool canIncrementBid() {
      return contractBid.count < 7;
    }

    void decrementBid() {
      if (contractBid.count <= 1) {
        return;
      }
      setState(() {
        contractBid = ContractBid(contractBid.count - 1, contractBid.trump);
      });
    }

    void incrementBid() {
      if (contractBid.count >= 7) {
        return;
      }
      setState(() {
        contractBid = ContractBid(contractBid.count + 1, contractBid.trump);
      });
    }

    bool isHumanBidding = widget.round.currentBidder() == 0;

    bool canBid() {
      if (!isHumanBidding) {
        return false;
      }
      return canCurrentBidderMakeContractBid(widget.round.bidHistory, contractBid);
    }

    void doBid() {
      final bid = PlayerBid(
          0, BidAction.contract(contractBid.count, contractBid.trump));
      setState(() {
        widget.onBid(bid);
      });
    }

    bool canPass() {
      return isHumanBidding;
    }

    void doPass() {
      setState(() {
        widget.onBid(PlayerBid(0, BidAction.pass()));
      });
    }

    bool canDouble() {
      if (!isHumanBidding) {
        return false;
      }
      return canCurrentBidderDouble(widget.round.bidHistory);
    }

    void doDouble() {
      setState(() {
        widget.onBid(PlayerBid(0, BidAction.double()));
      });
    }

    bool canRedouble() {
      if (!isHumanBidding) {
        return false;
      }
      return canCurrentBidderRedouble(widget.round.bidHistory);
    }

    void doRedouble() {
      setState(() {
        widget.onBid(PlayerBid(0, BidAction.redouble()));
      });
    }

    String contractMessage() {
      if (widget.round.contract == null) {
        return "The hand is passed out.";
      }
      return "The contract is ${contractDescription(widget.round.contract!)}";
    }

    List<Widget> postBidRows() {
      const textStyle = TextStyle(fontSize: 14);
      final halfPadding = textStyle.fontSize! * 0.75;

      return [
        paddingAll(
          halfPadding, Text(contractMessage(), style: textStyle, textAlign: TextAlign.left)),
        ElevatedButton(
          onPressed: widget.onConfirmContract,
          child: const Text("Start round"),
        ),
      ];
    }

    return Center(
        child: Transform.translate(
            offset: Offset(0, -widget.layout.displaySize.height * 0.1),
            child: Transform.scale(
                scale: widget.layout.dialogScale(),
                child: Dialog(
                    backgroundColor: dialogBackgroundColor,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                              "Vulnerable: ${vulnerabilityDescription(widget.round.vulnerability)}",
                              style: const TextStyle(fontSize: 12))),
                      BidHistoryTable(round: widget.round, headerCells: [
                        paddingHorizontal(cellPad, headerCell("You")),
                        catImageCell(widget.catImageIndices[1]),
                        catImageCell(widget.catImageIndices[2]),
                        catImageCell(widget.catImageIndices[3]),
                      ]),

                      if (!isBiddingOver) ...[
                        Row(
                            spacing: 12,
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton(
                                onPressed:
                                    canDecrementBid() ? decrementBid : null,
                                child: const Text("–", style: adjustBidTextStyle),
                              ),
                              Text(contractBid.count.toString(),
                                  style: adjustBidTextStyle),
                              ElevatedButton(
                                onPressed:
                                    canIncrementBid() ? incrementBid : null,
                                child: const Text("+", style: adjustBidTextStyle),
                              ),
                            ]),
                        paddingAll(
                            rowPadding,
                            SegmentedButton<Suit?>(
                              segments: const [
                                ButtonSegment(
                                    value: Suit.clubs, label: Text("♣")),
                                ButtonSegment(
                                    value: Suit.diamonds, label: Text("♦")),
                                ButtonSegment(
                                    value: Suit.hearts, label: Text("♥")),
                                ButtonSegment(
                                    value: Suit.spades, label: Text("♠")),
                                ButtonSegment(value: null, label: Text("NT")),
                              ],
                              showSelectedIcon: false,
                              selected: {contractBid.trump},
                              onSelectionChanged: (Set<Suit?> selectedSuits) {
                                setState(() {
                                  contractBid = ContractBid(
                                      contractBid.count, selectedSuits.first);
                                });
                              },
                            )),
                        Row(
                          spacing: 8,
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: canBid() ? doBid : null,
                              child: Text("Bid ${contractBid.symbolString()}"),
                            ),
                            ElevatedButton(
                              onPressed: canPass() ? doPass : null,
                              child: const Text("Pass"),
                            ),
                            if (!canRedouble())
                              ElevatedButton(
                                onPressed: canDouble() ? doDouble : null,
                                child: const Text("Double"),
                              ),
                            if (canRedouble())
                              ElevatedButton(
                                onPressed: doRedouble,
                                child: const Text("Redouble"),
                              ),
                          ],
                        ),
                      ],
                      if (isBiddingOver) ...postBidRows(),
                      const SizedBox(height: 12),
                      Row(
                        spacing: 8,
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: ((isHumanBidding || isBiddingOver) && hasHumanBid) ?  widget.onResetBids : null,
                            child: Text("Undo last bid"),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ])))));
  }
}

class EndOfRoundDialog extends StatelessWidget {
  final Layout layout;
  final BridgeMatch match;
  final BridgeRound duplicateRound;
  // Declarer-side tricks with best play by everyone, if computed.
  final int? doubleDummyDeclarerTricks;
  final Function() onContinue;
  final Function() onMainMenu;
  // For testing to see how the AI plays the hand over multiple runs.
  final Function()? onReplayDuplicateRound;
  // Switches to the duplicate round details dialog.
  final Function()? onShowDetails;

  const EndOfRoundDialog({
    super.key,
    required this.layout,
    required this.match,
    required this.duplicateRound,
    this.doubleDummyDeclarerTricks,
    required this.onContinue,
    required this.onMainMenu,
    this.onReplayDuplicateRound,
    this.onShowDetails,
  });

  Row makeRow(List<Widget> children) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  List<Row> rowsForDuplicateRound() {
    final round = match.currentRound;
    int myScore = round.contractScoreForPlayer(0);
    int dupScore = duplicateRound.contractScoreForPlayer(0);
    int scoreDiff = myScore - dupScore;
    final [nsImps, ewImps] = match.totalImpsPerTeam();

    return [
      makeRow([
        paddingAll(
          0,
          Text("${roundResultDescription(duplicateRound)}: ${plusPrefixIfPositive(dupScore)}"),
        ),
      ]),
      makeRow([
        Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text("Difference: ${plusPrefixIfPositive(scoreDiff)}")
        ),
      ]),
      makeRow([
        paddingAll(
            0,
            Text("IMPs: ${plusPrefixIfPositive(impsForScoreDifference(scoreDiff))}")
        ),
      ]),
      if (onShowDetails != null) makeRow([
        TextButton(
          onPressed: onShowDetails,
          child: const Text("Show details", style: TextStyle(fontSize: 12)),
        ),
      ]),
      if (onReplayDuplicateRound != null) makeRow([
        Transform.scale(scale: 0.5, child:
        ElevatedButton(
          onPressed: onReplayDuplicateRound,
          child: const Text("Replay duplicate round"),
        )),
      ]),
      if (match.numRounds > 1) makeRow([
        Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text("Match IMPs: $nsImps – $ewImps",
                style: const TextStyle(fontSize: 16))),
      ]),
      if (match.isMatchOver()) makeRow([
        Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(matchResultDescription(match.netImpsForPlayer0()),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold))),
      ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final round = match.currentRound;
    final roundResultDesc = roundResultDescription(round);

    final dialog = Center(
        child: Transform.scale(
            scale: layout.dialogScale(),
            child: Dialog(
                insetPadding: EdgeInsets.zero,
                backgroundColor: dialogBackgroundColor,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    makeRow([
                      Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                              "Round ${match.currentRoundNumber} of ${match.numRounds}"
                              " — Vul: ${vulnerabilityDescription(round.vulnerability)}")),
                    ]),
                    makeRow([
                      Padding(
                          padding: const EdgeInsets.only(top: 10, left: 10, right: 10),
                          child: Text("$roundResultDesc: ${formatRoundScore(round)}",
                              style: const TextStyle(fontSize: 18))),
                    ]),
                    if (doubleDummyDeclarerTricks != null)
                      makeRow([
                        Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                                "Double dummy: ${contractResultDescription(round.contract!, doubleDummyDeclarerTricks!)}",
                                style: const TextStyle(fontSize: 11))),
                      ]),
                    makeRow([
                      const Padding(
                        padding: EdgeInsets.only(),
                        child: Text("Duplicate round"),
                      ),
                    ]),
                    // Show progress indicator while duplicate round is playing.
                    if (!duplicateRound.isOver()) makeRow([
                      paddingAll(
                        10,
                        CircularProgressIndicator(value: duplicateRound.previousTricks.length / 13),
                      ),
                    ]),
                    if (duplicateRound.isOver()) ...rowsForDuplicateRound(),
                    // Buttons appear when the duplicate round finishes, so
                    // that every archived round has a completed duplicate.
                    if (duplicateRound.isOver() && match.isMatchOver())
                      makeRow([
                          paddingAll(
                              15,
                              ElevatedButton(
                                onPressed: onContinue,
                                child: const Text("Rematch"),
                              )),
                          paddingAll(
                              15,
                              ElevatedButton(
                                onPressed: onMainMenu,
                                child: const Text("Main Menu"),
                              )),
                        ],
                      ),
                    if (duplicateRound.isOver() && !match.isMatchOver())
                      makeRow([
                          paddingAll(
                              15,
                              ElevatedButton(
                                onPressed: onContinue,
                                child: const Text("Continue"),
                              ))
                      ]),
                  ],
                ))));

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: -1.0, end: 1.0),
      duration: const Duration(milliseconds: 1000),
      child: dialog,
      builder: (context, val, child) =>
          Opacity(opacity: val.clamp(0.0, 1.0), child: child),
    );
  }
}

/// Shows what happened in the player's round or the duplicate round, with
/// tabs for the auction (as a BidHistoryTable with seat letter headers) and
/// the play (one trick at a time with the winning card highlighted).
class RoundDetailsDialog extends StatefulWidget {
  final Layout layout;
  final BridgeRound round;
  final BridgeRound duplicateRound;
  final Function() onClose;

  const RoundDetailsDialog({
    super.key,
    required this.layout,
    required this.round,
    required this.duplicateRound,
    required this.onClose,
  });

  @override
  State<RoundDetailsDialog> createState() => _RoundDetailsDialogState();
}

class _RoundDetailsDialogState extends State<RoundDetailsDialog> {
  bool showDuplicate = false;
  int selectedTabIndex = 0;
  int trickIndex = 0;

  BridgeRound get selectedRound =>
      showDuplicate ? widget.duplicateRound : widget.round;

  Widget biddingTab() {
    Widget headerCell(String msg) => paddingAll(
        4,
        Text(msg,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)));

    return BidHistoryTable(round: selectedRound, headerCells: [
      for (int p = 0; p < 4; p++) headerCell("SWNE"[p]),
    ]);
  }

  Widget playTab() {
    final tricks = selectedRound.previousTricks;
    if (tricks.isEmpty) {
      return paddingAll(20, const Text("No cards were played."));
    }
    final trick = tricks[trickIndex];

    Widget seatCard(int playerIndex) {
      final cardIndex = (playerIndex - trick.leader) % 4;
      final card = trick.cards[cardIndex];
      final isWinner = playerIndex == trick.winner;
      return Container(
          decoration: BoxDecoration(
            border: Border.all(
                color: isWinner ? Colors.amber : Colors.transparent,
                width: 2.5),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Image.asset("assets/cards/solid/${card.toString()}.webp",
              height: 64));
    }

    // Arrow in the center of the cross pointing at the trick leader's card.
    final leadArrow = RotatedBox(
        quarterTurns: (trick.leader + 2) % 4,
        child: const Icon(Icons.arrow_upward, size: 24, color: Colors.black54));

    // Cross layout matching the table: N top, W left, E right, S bottom.
    return Column(mainAxisSize: MainAxisSize.min, children: [
      seatCard(2),
      Row(mainAxisSize: MainAxisSize.min, children: [
        seatCard(1),
        SizedBox(width: 56, child: Center(child: leadArrow)),
        seatCard(3),
      ]),
      seatCard(0),
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: trickIndex > 0
              ? () => setState(() => trickIndex -= 1)
              : null,
        ),
        Text("Trick ${trickIndex + 1} of ${tricks.length}",
            style: const TextStyle(fontSize: 12)),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: trickIndex < tricks.length - 1
              ? () => setState(() => trickIndex += 1)
              : null,
        ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
        child: Transform.scale(
            scale: widget.layout.dialogScale(),
            child: Dialog(
                insetPadding: EdgeInsets.zero,
                backgroundColor: dialogBackgroundColor,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    paddingAll(
                        8,
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                                value: false,
                                label: Text("Your round",
                                    style: TextStyle(fontSize: 12))),
                            ButtonSegment(
                                value: true,
                                label: Text("Duplicate",
                                    style: TextStyle(fontSize: 12))),
                          ],
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                              visualDensity: VisualDensity.compact),
                          selected: {showDuplicate},
                          onSelectionChanged: (selection) => setState(() {
                            showDuplicate = selection.first;
                            // Intentionally keep the trick index where it was.
                          }),
                        )),
                    Text(roundResultDescription(selectedRound),
                        style: const TextStyle(fontSize: 14)),
                    paddingAll(
                        8,
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(
                                value: 0,
                                label: Text("Bidding",
                                    style: TextStyle(fontSize: 12))),
                            ButtonSegment(
                                value: 1,
                                label: Text("Play",
                                    style: TextStyle(fontSize: 12))),
                          ],
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                              visualDensity: VisualDensity.compact),
                          selected: {selectedTabIndex},
                          onSelectionChanged: (selection) => setState(
                              () => selectedTabIndex = selection.first),
                        )),
                    if (selectedTabIndex == 0) biddingTab(),
                    if (selectedTabIndex == 1) playTab(),
                    paddingAll(
                        10,
                        ElevatedButton(
                          onPressed: widget.onClose,
                          child: const Text("Back"),
                        )),
                  ],
                ))));
  }
}

/// "made 4" / "down 2" for taking [tricks] against [contract].
String contractResultDescription(Contract contract, int tricks) {
  final over = tricks - contract.bid.numTricksRequired;
  return over >= 0 ? "made ${over + contract.bid.count}" : "down ${-over}";
}

String roundResultDescription(BridgeRound round) {
  if (round.isPassedOut()) {
    return "Passed out";
  }
  final contract = round.contract!;
  final tricksOver = round.tricksTakenByDeclarerOverContract();
  final direction = "SWNE"[contract.declarer];
  String doubledDesc = switch (contract.doubled) {
    DoubledType.none => "",
    DoubledType.doubled => " doubled",
    DoubledType.redoubled => " redoubled",
  };

  final contractDesc = "${contract.bid.symbolString()}$doubledDesc by $direction";
  final bidResultDesc = tricksOver >= 0
      ? "made ${tricksOver + contract.bid.count}"
      : "down ${-tricksOver}";
  return "$contractDesc, $bidResultDesc";
}

String contractDescription(Contract contract) {
  const declarerNames = ["South", "West", "North", "East"];
  String doubledDesc = switch (contract.doubled) {
    DoubledType.none => "",
    DoubledType.doubled => " doubled",
    DoubledType.redoubled => " redoubled",
  };
  return "${contract.bid.symbolString()}$doubledDesc"
      " by ${declarerNames[contract.declarer]}";
}

String vulnerabilityDescription(Vulnerability v) => switch (v) {
      Vulnerability.neither => "None",
      Vulnerability.nsOnly => "N-S",
      Vulnerability.ewOnly => "E-W",
      Vulnerability.both => "Both",
    };

String matchResultDescription(int totalImps) {
  if (totalImps == 0) {
    return "Match tied";
  }
  final imps = totalImps.abs();
  final impsDesc = "$imps IMP${imps == 1 ? '' : 's'}";
  return totalImps > 0 ? "You won by $impsDesc!" : "You lost by $impsDesc";
}

String plusPrefixIfPositive(int n) => "${(n > 0) ? '+' : ''}$n";

String formatRoundScore(BridgeRound r) => plusPrefixIfPositive(r.contractScoreForPlayer(0));
