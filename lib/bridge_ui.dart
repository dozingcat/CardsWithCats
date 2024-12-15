import 'dart:async';
import 'dart:math';

import 'package:cards_with_cats/soundeffects.dart';
import 'package:cards_with_cats/stats/stats_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'bridge/bridge_bidding.dart';
import 'common_ui.dart';
import 'cards/card.dart';
import 'cards/rollout.dart';
import 'bridge/bridge.dart';
import 'bridge/bridge_ai.dart';

const debugOutput = false;

void printd(String msg) {
  if (debugOutput) print(msg);
}

PlayingCard computeCard(final CardToPlayRequest req) {
  final mcParams = MonteCarloParams(maxRounds: 30, rolloutsPerRound: 30, maxTimeMillis: 2500);
  final result = chooseCardMonteCarlo(req, mcParams, chooseCardRandom, Random());
  printd("Computed play: ${result.toString()}");
  return result.bestCard;
}

class BridgeMatchDisplay extends StatefulWidget {
  final BridgeMatch Function() initialMatchFn;
  final BridgeMatch Function() createMatchFn;
  final void Function(BridgeMatch?) saveMatchFn;
  final void Function() mainMenuFn;
  final bool dialogVisible;
  final List<int> catImageIndices;
  final bool tintTrumpCards;
  final Stream matchUpdateStream;
  final SoundEffectPlayer soundPlayer;
  final StatsStore statsStore;

  const BridgeMatchDisplay({
    Key? key,
    required this.initialMatchFn,
    required this.createMatchFn,
    required this.saveMatchFn,
    required this.mainMenuFn,
    required this.dialogVisible,
    required this.catImageIndices,
    required this.tintTrumpCards,
    required this.matchUpdateStream,
    required this.soundPlayer,
    required this.statsStore,
  }) : super(key: key);

  @override
  BridgeMatchState createState() => BridgeMatchState();
}

final baseSuitDisplayOrder = [Suit.spades, Suit.hearts, Suit.clubs, Suit.diamonds];

class BridgeMatchState extends State<BridgeMatchDisplay> {
  final rng = Random();
  var animationMode = AnimationMode.none;
  bool showPostBidDialog = false;
  var aiMode = AiMode.humanPlayer0;
  int currentBidder = 0;
  Map<int, Mood> playerMoods = {};
  bool showScoreOverlay = false;
  late BridgeMatch match;
  late StreamSubscription matchUpdateSubscription;

  BridgeRound get round => match.currentRound;

  @override
  void initState() {
    super.initState();
    match = widget.initialMatchFn();
    matchUpdateSubscription = widget.matchUpdateStream.listen((event) {
      if (event is BridgeMatch) {
        _updateMatch(event);
      }
    });
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
    if (round.isOver()) {
      match.finishRound();
    }
    if (match.isMatchOver()) {
      match = widget.createMatchFn();
    }
    widget.saveMatchFn(match);
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
  }

  void _makeBidForAiPlayer(int playerIndex) {
    final bid = chooseBid(BidRequest(
      playerIndex: playerIndex,
      hand: round.players[playerIndex].hand,
      bidHistory: round.bidHistory,
    ));
    printd("P$playerIndex bids $bid");
    setState(() {
      _addBid(bid);
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

  void _scheduleNextAiBidIfNeeded() {
    if (round.status == BridgeRoundStatus.bidding && !_isWaitingForHumanBid()) {
      Future.delayed(const Duration(milliseconds: 1000), () {
        _makeBidForAiPlayer(round.currentBidder());
      });
    }
  }

  void _scheduleNextAiPlayIfNeeded() {
    if (round.isOver()) {
      // printd("Round done, scores: ${round.pointsTaken().map((p) => p.totalRoundPoints)}");
    } else if (round.currentPlayerIndex() != 0 && round.status == BridgeRoundStatus.playing) {
      _computeAiPlay(minDelayMillis: 750);
    }
  }

  void _computeAiPlay({required int minDelayMillis}) async {
    // Do this in a separate thread/isolate. Note: `compute` has an overhead of
    // several hundred milliseconds in debug mode, but not in release mode.
    final t1 = DateTime.now().millisecondsSinceEpoch;
    try {
      printd("Starting isolate");
      final card = await compute(computeCard, CardToPlayRequest.fromRound(round));
      final elapsed = DateTime.now().millisecondsSinceEpoch - t1;
      final delayMillis = max(0, minDelayMillis - elapsed);
      printd("Delaying for $delayMillis ms");
      Future.delayed(Duration(milliseconds: delayMillis), () => _playCard(card));
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
      });
      widget.saveMatchFn(match);
      _updateStatsIfMatchOrRoundOver();
    }
  }

  void _clearMoods() {
    playerMoods.clear();
  }

  void _updateMoodsAfterTrick() {
    // TODO
  }

  void _playSoundsForMoods() {
    // TODO
  }

  void _updateStatsIfMatchOrRoundOver() {
    // TODO
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
    _scheduleNextActionIfNeeded();
  }

  void handleHandCardClicked(final PlayingCard card) {
    printd(
        "Clicked ${card.toString()}, status: ${round.status}, index: ${round.currentPlayerIndex()}");
    if (round.status == BridgeRoundStatus.playing && round.currentPlayerIndex() == 0) {
      if (round.legalPlaysForCurrentPlayer().contains(card)) {
        printd("Playing");
        _playCard(card);
      }
    }
  }

  void handleDummyCardClicked(final PlayingCard card) {
    // TODO
  }

  // Duplicated from hearts_ui, might be worth a common function.
  PlayingCard? _lastCardPlayedByHuman() {
    final ct = round.currentTrick;
    if (ct.cards.isNotEmpty && ct.leader == 0) {
      return ct.cards[0];
    }
    else if (ct.cards.length + ct.leader > 4) {
      return ct.cards[4 - ct.leader];
    }
    else if (round.previousTricks.isNotEmpty) {
      final lt = round.previousTricks.last;
      return lt.cards[(4 - lt.leader) % 4];
    }
    return null;
  }

  Widget _handCards(final Layout layout, final List<PlayingCard> cards) {
    bool isHumanTurn = round.status == BridgeRoundStatus.playing && round.currentPlayerIndex() == 0;
    bool isBidding = round.status == BridgeRoundStatus.bidding;
    List<PlayingCard> highlightedCards = [];
    if (isBidding) {
      highlightedCards = cards;
    }
    else if (isHumanTurn) {
      highlightedCards = round.legalPlaysForCurrentPlayer();
    }

    final playerTrickCard = _lastCardPlayedByHuman();
    final previousPlayerCards = (playerTrickCard != null) ? [...cards, playerTrickCard] : null;
    // Flutter needs a key property to determine whether the PlayerHandCards
    // component has changed between renders.
    var key = "H${cards.map((c) => c.toString()).join()}";
    if (playerTrickCard != null) {
      key += ":${playerTrickCard.toString()}";
    }

    return PlayerHandCards(
        key: Key(key),
        layout: layout,
        suitDisplayOrder: _suitDisplayOrder(),
        cards: cards,
        trumpSuit: widget.tintTrumpCards ? round.trumpSuit() : null,
        animateFromCards: previousPlayerCards,
        highlightedCards: highlightedCards,
        onCardClicked: handleHandCardClicked);
  }

  Widget _trickCards(final Layout layout) {
    final humanHand = aiMode == AiMode.humanPlayer0 ? round.players[0].hand : null;
    return TrickCards(
      layout: layout,
      currentTrick: round.currentTrick,
      previousTricks: round.previousTricks,
      trumpSuit: widget.tintTrumpCards ? round.trumpSuit() : null,
      animationMode: animationMode,
      numPlayers: 4,
      humanPlayerHand: humanHand,
      humanPlayerSuitOrder: _suitDisplayOrder(),
      onTrickCardAnimationFinished: _trickCardAnimationFinished,
      onTrickToWinnerAnimationFinished: _trickToWinnerAnimationFinished,
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = computeLayout(context);
    // TODO
    return Stack(
        children: [
          _handCards(layout, round.players[0].hand),
          _trickCards(layout),
        ],
    );
  }
}

const dialogBackgroundColor = Color.fromARGB(0x80, 0xd8, 0xd8, 0xd8);

class BidDialog extends StatefulWidget {
  final Layout layout;
  final BridgeRound round;
  final List<int> catImageIndices;

  const BidDialog({
    super.key,
    required this.layout,
    required this.round,
    required this.catImageIndices,
  });

  @override
  State<BidDialog> createState() => _BidDialogState();
}

class _BidDialogState extends State<BidDialog> {

  @override
  Widget build(BuildContext context) {
    const headerFontSize = 14.0;
    const cellPad = 4.0;

    Widget headerCell(String msg) => paddingAll(
        cellPad,
        Text(msg,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: headerFontSize, fontWeight: FontWeight.bold)));

    Widget catImageCell(int imageIndex) {
      const imageHeight = headerFontSize * 1.3;
      const leftPadding = headerFontSize * 1.1;
      return Padding(
          padding: const EdgeInsets.only(left: leftPadding),
          child: Image.asset(catImageForIndex(imageIndex), height: imageHeight));
    }

    final bidHistory = widget.round.bidHistory;
    final dealer = widget.round.dealer;

    final numHumanBids = bidHistory.where((pb) => pb.player == 0).length;
    final numBidRows = numHumanBids + (bidHistory.isNotEmpty && bidHistory[0].player != 0 ? 1 : 0);

    Widget bidCell({required int rowIndex, required int playerIndex}) {
      int bidIndex = 4 * rowIndex + playerIndex - dealer;
      if (bidIndex < 0 || bidIndex >= bidHistory.length) {
        return const SizedBox();
      }
      return Text(bidHistory[bidIndex].symbolString());
    }

    final numberOfBidRows = (dealer + bidHistory.length / 4).ceil();

    return Center(
      child: Transform.scale(scale: widget.layout.dialogScale(), child: Dialog(
        backgroundColor: dialogBackgroundColor,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          paddingAll(10, Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              TableRow(children: [
                paddingAll(cellPad, headerCell("You")),
                paddingAll(cellPad, catImageCell(widget.catImageIndices[1])),
                paddingAll(cellPad, catImageCell(widget.catImageIndices[2])),
                paddingAll(cellPad, catImageCell(widget.catImageIndices[3])),
              ]),
              ...[for(var row = 0; row < numberOfBidRows; row += 1) TableRow(children: [
                bidCell(rowIndex: row, playerIndex: 0),
                bidCell(rowIndex: row, playerIndex: 1),
                bidCell(rowIndex: row, playerIndex: 2),
                bidCell(rowIndex: row, playerIndex: 3),
              ])]
            ]
          ))
        ])
      ))
    );
  }

}