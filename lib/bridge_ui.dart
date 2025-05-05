import 'dart:async';
import 'dart:math';

import 'package:cards_with_cats/soundeffects.dart';
import 'package:cards_with_cats/stats/stats_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'bridge/bridge_bidding.dart';
import 'cards/round.dart';
import 'cards/trick.dart';
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
  final mcParams = MonteCarloParams(
      maxRounds: 30, rolloutsPerRound: 30, maxTimeMillis: 2500);
  final result =
      chooseCardMonteCarlo(req, mcParams, chooseCardRandom, Random());
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
    super.key,
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
    isClaimingRemainingTricks = false;
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

  void makeBidForHuman(PlayerBid bid) {
    setState(() {
      _addBid(bid);
    });
  }

  void resetBids() {
    setState(() {
      round.bidHistory = [];
      round.status = BridgeRoundStatus.bidding;
      showPostBidDialog = false;
      _scheduleNextActionIfNeeded();
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
      Future.delayed(const Duration(milliseconds: 1000), () {
        _makeBidForAiPlayer(round.currentBidder());
      });
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
    _updateMoodsAfterTrick();
    _playSoundsForMoods();
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
      playerIndex: playerIndex,
      cards: cards,
      highlightedCards: highlightedCards,
      animateFromCards: previousPlayerCards,
      onCardClicked: handleHandCardClicked,
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
      playerIndex: dummyPlayer,
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
              playerIndex: p,
              cards: round.players[p].hand,
              highlightedCards: p == round.currentTrick.leader
                  ? round.players[p].hand
                  : const [],
            ))
        .toList();
  }

  Widget allHandsForDebugging(layout) {
    final params = [0, 1, 2, 3]
        .map((p) => PlayerHandParams(
              playerIndex: p,
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
        playerIndex: humanNonDummyPlayer,
        cards: round.players[humanNonDummyPlayer].hand));
    final dummyIndex = round.visibleDummy();
    if (dummyIndex != null) {
      displayedHands.add(DisplayedHand(
          playerIndex: dummyIndex,
          cards: round.players[dummyIndex].hand,
          displayStyle: HandDisplayStyle.dummy));
    }

    return TrickCards(
      layout: layout,
      currentTrick: round.currentTrick,
      previousTricks: round.previousTricks,
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
    return !widget.dialogVisible && round.status == BridgeRoundStatus.bidding;
  }

  bool _shouldShowPostBidDialog() {
    return !widget.dialogVisible && showPostBidDialog;
  }

  bool _shouldShowClaimTricksDialog() {
    return !widget.dialogVisible && isClaimingRemainingTricks;
  }

  bool _shouldShowEndOfRoundDialog() {
    return !widget.dialogVisible && round.isOver();
  }

  void _showMainMenuAfterMatch() {
    widget.saveMatchFn(null);
    widget.mainMenuFn();
  }

  @override
  Widget build(BuildContext context) {
    final layout = computeLayout(context);

    return Stack(
      children: [
        // _playerCards(layout),
        allHandsForDebugging(layout),
        _trickCards(layout),
        if (_shouldShowBidDialog())
          BidDialog(
            layout: layout,
            round: round,
            onBid: makeBidForHuman,
            onResetBids: resetBids,
            catImageIndices: widget.catImageIndices,
          ),
        if (_shouldShowPostBidDialog())
          PostBidDialog(
              layout: layout,
              round: round,
              onConfirm: _handlePostBidDialogConfirm,
              onResetBids: resetBids,
          ),
        if (_shouldShowClaimTricksDialog())
          ClaimRemainingTricksDialog(onOk: _handleClaimTricksDialogOk),
        if (_shouldShowEndOfRoundDialog())
          EndOfRoundDialog(
            layout: layout,
            match: match,
            onContinue: () => setState(_startRound),
            onMainMenu: _showMainMenuAfterMatch,
          ),
      ],
    );
  }
}

const dialogBackgroundColor = Color.fromARGB(0x80, 0xd8, 0xd8, 0xd8);

class BidDialog extends StatefulWidget {
  final Layout layout;
  final BridgeRound round;
  final void Function(PlayerBid) onBid;
  final void Function() onResetBids;
  final List<int> catImageIndices;

  const BidDialog({
    super.key,
    required this.layout,
    required this.round,
    required this.onBid,
    required this.onResetBids,
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

    Widget bidCell({required int rowIndex, required int playerIndex}) {
      int bidIndex = 4 * rowIndex + playerIndex - dealer;
      if (bidIndex == bidHistory.length) {
        return const Text("?", textAlign: TextAlign.center);
      }
      if (bidIndex < 0 || bidIndex > bidHistory.length) {
        return const SizedBox();
      }
      return Text(bidHistory[bidIndex].action.symbolString(),
          textAlign: TextAlign.center);
    }

    final numberOfBidRows = ((dealer + bidHistory.length + 2) / 4).ceil();

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
      final lastBid = lastContractBid(widget.round.bidHistory);
      if (lastBid == null) {
        return true;
      }
      return contractBid.isHigherThan(lastBid.action.contractBid!);
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

    return Center(
        child: Transform.translate(
            offset: Offset(0, -widget.layout.displaySize.height * 0.1),
            child: Transform.scale(
                scale: widget.layout.dialogScale(),
                child: Dialog(
                    backgroundColor: dialogBackgroundColor,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      paddingAll(
                          10,
                          Table(
                            defaultVerticalAlignment:
                                TableCellVerticalAlignment.middle,
                            defaultColumnWidth: const IntrinsicColumnWidth(),
                            children: [
                              TableRow(children: [
                                paddingHorizontal(cellPad, headerCell("You")),
                                catImageCell(widget.catImageIndices[1]),
                                catImageCell(widget.catImageIndices[2]),
                                catImageCell(widget.catImageIndices[3]),
                              ]),
                              ...[
                                for (var row = 0;
                                    row < numberOfBidRows;
                                    row += 1)
                                  TableRow(children: [
                                    bidCell(rowIndex: row, playerIndex: 0),
                                    bidCell(rowIndex: row, playerIndex: 1),
                                    bidCell(rowIndex: row, playerIndex: 2),
                                    bidCell(rowIndex: row, playerIndex: 3),
                                  ])
                              ]
                            ],
                          )),
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
                      const SizedBox(height: 12),
                      Row(
                        spacing: 8,
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: widget.onResetBids,
                            child: Text("Reset"),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ])))));
  }
}

class PostBidDialog extends StatelessWidget {
  final Layout layout;
  final BridgeRound round;
  final Function() onConfirm;
  final Function() onResetBids;

  const PostBidDialog(
      {Key? key, required this.layout, required this.round, required this.onConfirm, required this.onResetBids})
      : super(key: key);

  String contractMessage() {
    if (round.contract == null) {
      return "The hand is passed out.";
    }
    final contract = round.contract!;
    String declarerDesc = switch (contract.declarer) {
      0 => "South",
      1 => "West",
      2 => "North",
      3 => "East",
      _ => throw Error(),
    };
    String doubledDesc = switch (contract.doubled) {
      DoubledType.none => "",
      DoubledType.doubled => " doubled",
      DoubledType.redoubled => " redoubled",
    };
    return "The contract is ${contract.bid.symbolString()}$doubledDesc by $declarerDesc";
  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 14);
    final halfPadding = textStyle.fontSize! * 0.75;
    return Transform.scale(scale: layout.dialogScale(), child: Dialog(
        backgroundColor: dialogBackgroundColor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: halfPadding),
            paddingAll(
                halfPadding, Text(contractMessage(), style: textStyle, textAlign: TextAlign.left)),
            paddingAll(
                halfPadding,
                ElevatedButton(
                  onPressed: onConfirm,
                  child: const Text("Start round"),
                )),
            SizedBox(height: halfPadding),
            paddingAll(
                halfPadding,
                ElevatedButton(
                  onPressed: onResetBids,
                  child: const Text("Reset bidding"),
                )),
            SizedBox(height: halfPadding),          ],
        )));
  }
}

class EndOfRoundDialog extends StatelessWidget {
  final Layout layout;
  final BridgeMatch match;
  final Function() onContinue;
  final Function() onMainMenu;

  const EndOfRoundDialog({
    super.key,
    required this.layout,
    required this.match,
    required this.onContinue,
    required this.onMainMenu,
  });

  String roundResultDescription(BridgeRound round) {
    if (round.isPassedOut()) {
      return "Passed out";
    }
    final contract = round.contract!;
    final tricksOver = round.tricksTakenByDeclarerOverContract();
    final direction = "SWNE"[contract.declarer];

    final contractDesc = "${contract.bid.symbolString()} by $direction";
    final bidResultDesc = tricksOver >= 0
        ? "made ${tricksOver + contract.bid.count}"
        : "down ${-tricksOver}";
    return "$contractDesc, $bidResultDesc";
  }

  @override
  Widget build(BuildContext context) {
    final round = match.currentRound;
    final roundResultDesc = roundResultDescription(round);
    final scoreDesc = "Score: ${round.contractScoreForPlayer(0)}";

    final dialog = Center(
        child: Transform.scale(
            scale: layout.dialogScale(),
            child: Dialog(
                insetPadding: EdgeInsets.zero,
                backgroundColor: dialogBackgroundColor,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        paddingAll(
                            10,
                            Text(roundResultDesc,
                                style: const TextStyle(fontSize: 20))),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        paddingAll(
                            10,
                            Text(scoreDesc,
                                style: const TextStyle(fontSize: 20))),
                      ],
                    ),
                    if (match.isMatchOver())
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                    if (!match.isMatchOver())
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          paddingAll(
                              15,
                              ElevatedButton(
                                onPressed: onContinue,
                                child: const Text("Continue"),
                              ))
                        ],
                      ),
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
