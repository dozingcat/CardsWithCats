import 'dart:async';
import 'dart:math';

import 'package:cards_with_cats/cards/trick.dart';
import 'package:cards_with_cats/soundeffects.dart';
import 'package:cards_with_cats/stats/stats_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'cards/round.dart';
import 'common_ui.dart';
import 'cards/card.dart';
import 'cards/rollout.dart';
import 'ohhell/ohhell.dart';
import 'ohhell/ohhell_ai.dart';
import 'ohhell/ohhell_stats.dart';

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

class OhHellMatchDisplay extends StatefulWidget {
  final OhHellMatch Function() initialMatchFn;
  final OhHellMatch Function() createMatchFn;
  final void Function(OhHellMatch?) saveMatchFn;
  final void Function() mainMenuFn;
  final bool dialogVisible;
  final List<int> catImageIndices;
  final bool tintTrumpCards;
  final Stream matchUpdateStream;
  final SoundEffectPlayer soundPlayer;
  final StatsStore statsStore;

  const OhHellMatchDisplay({
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
  OhHellMatchState createState() => OhHellMatchState();
}

final baseSuitDisplayOrder = [Suit.spades, Suit.hearts, Suit.clubs, Suit.diamonds];

class OhHellMatchState extends State<OhHellMatchDisplay> {
  final rng = Random();
  var animationMode = AnimationMode.none;
  bool showPostBidDialog = false;
  bool isClaimingRemainingTricks = false;
  var aiMode = AiMode.humanPlayer0;
  int currentBidder = 0;
  Map<int, Mood> playerMoods = {};
  bool showScoreOverlay = false;
  late OhHellMatch match;
  late StreamSubscription matchUpdateSubscription;

  OhHellRound get round => match.currentRound;

  @override
  void initState() {
    super.initState();
    match = widget.initialMatchFn();
    matchUpdateSubscription = widget.matchUpdateStream.listen((event) {
      if (event is OhHellMatch) {
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

  void _updateMatch(OhHellMatch newMatch) {
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

  void _setBidForPlayer({required int bid, required int playerIndex}) {
    round.setBidForPlayer(bid: bid, playerIndex: playerIndex);
    if (round.status == OhHellRoundStatus.playing) {
      _handleBiddingDone();
    } else {
      _scheduleNextActionIfNeeded();
    }
    widget.saveMatchFn(match);
  }

  void _makeBidForAiPlayer(int playerIndex) {
    int bid = chooseBid(BidRequest(
      rules: round.rules,
      scoresBeforeRound: round.initialScores,
      otherBids: round.bidsInOrderMade(),
      trumpCard: round.trumpCard,
      dealerHasTrumpCard: round.dealerHasTrumpCard(),
      hand: round.players[playerIndex].hand,
    ), rng);
    printd("P$playerIndex bids $bid");
    setState(() {
      _setBidForPlayer(bid: bid, playerIndex: playerIndex);
    });
  }

  void _scheduleNextAiBidIfNeeded() {
    if (round.status == OhHellRoundStatus.bidding && !_isWaitingForHumanBid()) {
      Future.delayed(const Duration(milliseconds: 1000), () {
        _makeBidForAiPlayer(round.currentBidder());
      });
    }
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

  void _scheduleNextAiPlayIfNeeded() {
    if (round.isOver()) {
      printd("Round done, scores: ${round.pointsTaken().map((p) => p.totalRoundPoints)}");
    } else if (round.currentPlayerIndex() != 0 && round.status == OhHellRoundStatus.playing) {
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
    if (round.status == OhHellRoundStatus.playing) {
      setState(() {
        round.playCard(card);
        animationMode = AnimationMode.movingTrickCard;
      });
      widget.saveMatchFn(match);
      _updateStatsIfMatchOrRoundOver();
    }
  }

  void _updateStatsIfMatchOrRoundOver() async {
    if (round.isOver()) {
      final currentStats = (await widget.statsStore.readOhHellStats()) ?? OhHellStats.empty();
      var newStats = currentStats.updateFromRound(round);
      if (match.isMatchOver()) {
        newStats = newStats.updateFromMatch(match);
      }
      widget.statsStore.writeOhHellStats(newStats);
    }
  }

  void _clearMoods() {
    playerMoods.clear();
  }

  void _updateMoodsAfterTrick() {
    // print(round.toJson());
    playerMoods.clear();
    if (match.isMatchOver()) {
      final winners = match.winningPlayers();
      for (int i = 1; i < match.rules.numPlayers; i++) {
        playerMoods[i] = (winners.contains(i)) ? Mood.veryHappy : Mood.mad;
      }
    } else if (round.isOver()) {
      // Happy if made bid, sad if not.
      final scores = round.pointsTaken();
      for (int i = 1; i < match.rules.numPlayers; i++) {
        playerMoods[i] = (scores[i].totalRoundPoints >= round.rules.pointsForSuccessfulBid) ? Mood.happy : Mood.mad;
      }
    } else {
      // Mad if took the first trick over the bid.
      if (round.previousTricks.isNotEmpty) {
        int lastTrickWinner = round.previousTricks.last.winner;
        if (lastTrickWinner > 0) {
          int wonTricks = round.previousTricks.where((t) => t.winner == lastTrickWinner).length;
          if (wonTricks == round.players[lastTrickWinner].bid! + 1) {
            playerMoods[lastTrickWinner] = Mood.mad;
          }
        }
      }
    }
  }

  void _playSoundsForMoods() {
    bool hasHappy = playerMoods.containsValue(Mood.happy) || playerMoods.containsValue(Mood.veryHappy);
    bool hasMad = playerMoods.containsValue(Mood.mad);
    if (hasHappy) {
      widget.soundPlayer.playHappySound();
    }
    // Only happy sound if an AI player won the match.
    if (hasMad && (!match.isMatchOver() || !hasHappy)) {
      widget.soundPlayer.playMadSound();
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

  bool _shouldLeaderClaimRemainingTricks() {
    if (round.numCardsPerPlayer <= 5) {
      return false;
    }
    return shouldLeaderClaimRemainingTricks(round, trump: round.trumpSuit);
  }

  void _handleClaimTricksDialogOk() {
    claimRemainingTricks(round);
    setState(() {
      isClaimingRemainingTricks = false;
    });
  }

  void _trickToWinnerAnimationFinished() {
    setState(() {
      animationMode = AnimationMode.none;
    });
    if (_shouldLeaderClaimRemainingTricks()) {
      setState(() {
        isClaimingRemainingTricks = true;
      });
    }
    else {
      _scheduleNextActionIfNeeded();
    }
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
    if (round.status == OhHellRoundStatus.playing && round.currentPlayerIndex() == 0) {
      if (round.legalPlaysForCurrentPlayer().contains(card)) {
        printd("Playing");
        _playCard(card);
      }
    }
  }

  List<Suit> _suitDisplayOrder() {
    // Trump suit first.
    switch (round.trumpSuit) {
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

  Widget _handCards(final Layout layout, final List<PlayingCard> cards) {
    bool isHumanTurn = round.status == OhHellRoundStatus.playing && round.currentPlayerIndex() == 0;
    bool isBidding = round.status == OhHellRoundStatus.bidding;
    List<PlayingCard> highlightedCards = [];
    if (isBidding) {
      highlightedCards = cards;
    }
    else if (isHumanTurn) {
      highlightedCards = round.legalPlaysForCurrentPlayer();
    }

    final playerTrickCard = lastCardPlayedByPlayer(
      playerIndex: 0,
      numberOfPlayers: round.numberOfPlayers,
      currentTrick: round.currentTrick,
      previousTricks: round.previousTricks,
    );
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
        trumpSuit: widget.tintTrumpCards ? round.trumpSuit : null,
        animateFromCards: previousPlayerCards,
        highlightedCards: highlightedCards,
        onCardClicked: handleHandCardClicked);
  }

  Widget _trickCards(final Layout layout) {
    return TrickCards(
      layout: layout,
      currentTrick: round.currentTrick,
      previousTricks: round.previousTricks,
      trumpSuit: widget.tintTrumpCards ? round.trumpSuit : null,
      animationMode: animationMode,
      numPlayers: round.rules.numPlayers,
      displayedHands: [DisplayedHand(playerIndex: 0, cards: round.players[0].hand)],
      suitOrder: _suitDisplayOrder(),
      onTrickCardAnimationFinished: _trickCardAnimationFinished,
      onTrickToWinnerAnimationFinished: _trickToWinnerAnimationFinished,
    );
  }

  List<String> _currentRoundScoreMessages() {
    if (round.status == OhHellRoundStatus.bidding) {
      return List.generate(round.rules.numPlayers, (i) => "Score: ${round.initialScores[i]}");
    }
    final messages = <String>[];
    for (int i = 0; i < round.rules.numPlayers; i++) {
      final tricksTaken = round.previousTricks.where((t) => t.winner == i).length;
      messages.add("Score: ${round.initialScores[i]}\nBid ${round.players[i].bid}, Took $tricksTaken");
    }
    return messages;
  }

  bool shouldShowScoreOverlay() {
    return showScoreOverlay && !widget.dialogVisible && !round.isOver();
  }

  bool shouldShowScoreOverlayToggle() {
    return !widget.dialogVisible && !round.isOver();
  }

  bool _isWaitingForHumanBid() {
    return (round.status == OhHellRoundStatus.bidding &&
        aiMode == AiMode.humanPlayer0 &&
        round.currentBidder() == 0);
  }

  bool _shouldShowHumanBidDialog() {
    return !widget.dialogVisible && _isWaitingForHumanBid();
  }

  bool _shouldShowPostBidDialog() {
    return !widget.dialogVisible && showPostBidDialog;
  }

  bool _shouldShowClaimTricksDialog() {
    return !widget.dialogVisible && isClaimingRemainingTricks;
  }

  void makeBidForHuman(int bid) {
    printd("Human bids $bid");
    setState(() {
      _setBidForPlayer(bid: bid, playerIndex: 0);
    });
  }

  bool _shouldShowEndOfRoundDialog() {
    return !widget.dialogVisible && round.isOver();
  }

  List<Widget> bidSpeechBubbles(final Layout layout) {
    if (round.status != OhHellRoundStatus.bidding && !showPostBidDialog) return [];
    final bubbles = <Widget>[];
    for (int i = 0; i < round.rules.numPlayers; i++) {
      final bid = round.players[i].bid;
      if (bid != null) {
        bubbles.add(SpeechBubble(layout: layout, playerIndex: i, message: bid.toString()));
      }
    }
    return bubbles;
  }

  List<Widget> moodBubbles(final Layout layout) {
    final bubbles = <Widget>[];
    for (int i = 0; i < round.rules.numPlayers; i++) {
      if (playerMoods.containsKey(i)) {
        // Animate opacity?
        bubbles.add(MoodBubble(layout: layout, playerIndex: i, mood: playerMoods[i]!));
      }
    }
    return bubbles;
  }

  void _showMainMenuAfterMatch() {
    widget.saveMatchFn(null);
    widget.mainMenuFn();
  }

  Widget scoreOverlayButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 80, 10, 10),
      child: FloatingActionButton(
        onPressed: () {
          setState(() {
            showScoreOverlay = !showScoreOverlay;
          });
        },
        child: Icon(showScoreOverlay ? Icons.search_off : Icons.search),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = computeLayout(context);

    List<Widget> handsToShowForClaim() {
      if (!_shouldShowClaimTricksDialog()) {
        return [];
      }
      return (const [1, 2, 3]).map((p) =>
        PlayerHandCards(
          layout: layout,
          playerIndex: p,
          suitDisplayOrder: _suitDisplayOrder(),
          cards: round.players[p].hand,
          trumpSuit: widget.tintTrumpCards ? round.trumpSuit : null,
          highlightedCards: p == round.currentTrick.leader ? round.players[p].hand : const [],
        )).toList();
    }

    return Stack(
      children: <Widget>[
        _handCards(layout, round.players[0].hand),
        _trickCards(layout),
        ...handsToShowForClaim(),
        if (_shouldShowHumanBidDialog())
          BidDialog(layout: layout, round: round, onBid: makeBidForHuman, catImageIndices: widget.catImageIndices),
        if (_shouldShowPostBidDialog())
          PostBidDialog(layout: layout, round: round, onConfirm: _handlePostBidDialogConfirm),
        if (_shouldShowClaimTricksDialog())
          ClaimRemainingTricksDialog(onOk: _handleClaimTricksDialogOk),
        if (_shouldShowEndOfRoundDialog())
          EndOfRoundDialog(
            layout: layout,
            match: match,
            onContinue: () => setState(_startRound),
            onMainMenu: _showMainMenuAfterMatch,
            catImageIndices: widget.catImageIndices,
          ),
        ...bidSpeechBubbles(layout),
        PlayerMoods(layout: layout, moods: playerMoods),
        if (shouldShowScoreOverlay())
          PlayerMessagesOverlay(layout: layout, messages: _currentRoundScoreMessages()),
        if (shouldShowScoreOverlayToggle()) scoreOverlayButton(),
        // Text("${round.dealer.toString()} ${round.status}, ${round.players.map((p) => p.bid).toList()} ${_isWaitingForHumanBid()} ${match.scores}"),
      ],
    );
  }
}

const dialogBackgroundColor = Color.fromARGB(0x80, 0xd8, 0xd8, 0xd8);

class BidDialog extends StatefulWidget {
  final Layout layout;
  final OhHellRound round;
  final void Function(int) onBid;
  final List<int> catImageIndices;

  const BidDialog({
    super.key,
    required this.layout,
    required this.round,
    required this.onBid,
    required this.catImageIndices,
  });

  @override
  State<BidDialog> createState() => _BidDialogState();
}

// TODO: Handle disallowed bids.
class _BidDialogState extends State<BidDialog> {
  int bidAmount = 1;

  bool canIncrementBid() => (bidAmount < widget.round.numCardsPerPlayer);

  void incrementBid() {
    setState(() {
      bidAmount = min(bidAmount + 1, widget.round.numCardsPerPlayer);
    });
  }

  bool canDecrementBid() => (bidAmount > 0);

  void decrementBid() {
    setState(() {
      bidAmount = max(bidAmount - 1, 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    const adjustBidTextStyle = TextStyle(fontSize: 18);
    const rowPadding = 15.0;
    int? disallowedBid = widget.round.disallowedBidForCurrentBidder();

    Widget trumpCardMessage() {
      final trumpStr = widget.round.trumpCard.symbolString();
      const textStyle = TextStyle(fontSize: 10);
      final children = <Widget>[];
      if (widget.round.dealerHasTrumpCard()) {
        if (widget.round.dealer == 0) {
          children.add(Text("You have the trump card $trumpStr", style: textStyle));
        }
        else {
          children.add(Image.asset(catImageForIndex(widget.catImageIndices[widget.round.dealer]), height: 12));
          children.add(Text(" has the trump card $trumpStr", style: textStyle));
        }
      }
      else {
        children.add(Text("After dealing, the trump card is $trumpStr", style: textStyle));
      }
      return Opacity(opacity: 0.7, child: Padding(padding: const EdgeInsets.only(top: 5), child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: children
      )));
    }

    return Center(
        child: Transform.scale(scale: widget.layout.dialogScale(), child: Dialog(
            backgroundColor: dialogBackgroundColor,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(padding: const EdgeInsets.only(top: 15), child: Text("Trump is ${widget.round.trumpSuit.symbolChar}", style: adjustBidTextStyle)),
                trumpCardMessage(),

                const Padding(padding: EdgeInsets.only(top: 15), child: Text("Choose your bid", style: adjustBidTextStyle)),
                if (disallowedBid != null) paddingAll(5, Text("You may not bid $disallowedBid", style: const TextStyle(fontSize: 14))),
                const SizedBox(height: 10),
                Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: canDecrementBid() ? decrementBid : null,
                        child: const Text("–", style: adjustBidTextStyle),
                      ),
                      paddingAll(
                          rowPadding, Text(bidAmount.toString(), style: adjustBidTextStyle)),
                      ElevatedButton(
                        onPressed: canIncrementBid() ? incrementBid : null,
                        child: const Text("+", style: adjustBidTextStyle),
                      ),
                    ]),
                paddingAll(
                    rowPadding,
                    Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton(
                            onPressed: (bidAmount == disallowedBid) ? null :  () => widget.onBid(bidAmount),
                            child: Text("Bid ${bidAmount.toString()}"),
                          ),
                        ])),
              ],
            ))));
  }
}

class PostBidDialog extends StatelessWidget {
  final Layout layout;
  final OhHellRound round;
  final Function() onConfirm;

  const PostBidDialog(
      {super.key, required this.layout, required this.round, required this.onConfirm});

  String bidMessage() {
    final playerBid = round.players[0].bid!;
    final totalBids = round.bidsInOrderMade().reduce((a, b) => a + b);
    return "You bid $playerBid. The total of all bids is $totalBids, for ${round.numCardsPerPlayer} tricks.";
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
                halfPadding, Text(bidMessage(), style: textStyle, textAlign: TextAlign.left)),
            paddingAll(
                halfPadding,
                ElevatedButton(
                  onPressed: onConfirm,
                  child: const Text("Start round"),
                )),
            SizedBox(height: halfPadding),
          ],
        )));
  }
}

class EndOfRoundDialog extends StatelessWidget {
  final Layout layout;
  final OhHellMatch match;
  final Function() onContinue;
  final Function() onMainMenu;
  final List<int> catImageIndices;

  const EndOfRoundDialog({
    super.key,
    required this.layout,
    required this.match,
    required this.onContinue,
    required this.onMainMenu,
    required this.catImageIndices,
  });

  @override
  Widget build(BuildContext context) {
    final scores = match.currentRound.pointsTaken().map((p) => p.totalRoundPoints).toList();
    const headerFontSize = 14.0;
    const pointsFontSize = headerFontSize * 1.2;
    const cellPad = 4.0;

    Widget pointsCell(Object p) => paddingAll(cellPad,
        Text(p.toString(), textAlign: TextAlign.right, style: const TextStyle(fontSize: pointsFontSize)));

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

    TableRow pointsRow(String title, List<Object> points) => TableRow(children: [
      paddingAll(cellPad, headerCell(title)),
      ...points.map((p) => paddingAll(cellPad, pointsCell(p.toString())))
    ]);

    String matchOverMessage() {
      final p = match.winningPlayers();
      if (p.contains(0)) {
        return (p.length == 1) ? "You win!" : "You tied for the win!";
      }
      return "You lose :(";
    }

    final dialog = Center(
        child: Transform.scale(scale: layout.dialogScale(), child: Dialog(
            insetPadding: EdgeInsets.zero,
            backgroundColor: dialogBackgroundColor,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (match.isMatchOver())
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    paddingAll(
                        10,
                        Text(matchOverMessage(),
                            style: const TextStyle(fontSize: 26))),
                  ],
                ),
              if (match.rules.numRoundsInMatch != null && !match.isMatchOver())
                ...[
                  const SizedBox(height: 15),
                  Text("Round ${match.previousRounds.length + 1} of ${match.rules.numRoundsInMatch}"),
                ],
              paddingAll(
                  10,
                  Table(
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    defaultColumnWidth: const IntrinsicColumnWidth(),
                    children: [
                      TableRow(children: [
                        paddingAll(cellPad, headerCell("")),
                        paddingAll(cellPad, headerCell("You")),
                        paddingAll(cellPad, catImageCell(catImageIndices[1])),
                        paddingAll(cellPad, catImageCell(catImageIndices[2])),
                        paddingAll(cellPad, catImageCell(catImageIndices[3])),
                      ]),
                      pointsRow("Previous", match.currentRound.initialScores),
                      pointsRow("Round score", scores),
                      pointsRow("Total score", match.scores),
                    ],
                  )),
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
            ]))));

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: -1.0, end: 1.0),
      duration: const Duration(milliseconds: 1000),
      child: dialog,
      builder: (context, val, child) => Opacity(opacity: val.clamp(0.0, 1.0), child: child),
    );
  }
}
