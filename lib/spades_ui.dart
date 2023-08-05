import 'dart:async';
import 'dart:math';

import 'package:cards_with_cats/soundeffects.dart';
import 'package:cards_with_cats/spades/spades_stats.dart';
import 'package:cards_with_cats/stats/stats_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'common_ui.dart';
import 'cards/card.dart';
import 'cards/rollout.dart';
import 'spades/spades.dart';
import 'spades/spades_ai.dart';

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

class SpadesMatchDisplay extends StatefulWidget {
  final SpadesMatch Function() initialMatchFn;
  final SpadesMatch Function() createMatchFn;
  final void Function(SpadesMatch?) saveMatchFn;
  final void Function() mainMenuFn;
  final bool dialogVisible;
  final List<int> catImageIndices;
  final bool tintTrumpCards;
  final Stream matchUpdateStream;
  final SoundEffectPlayer soundPlayer;
  final StatsStore statsStore;

  const SpadesMatchDisplay({
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
  _SpadesMatchState createState() => _SpadesMatchState();
}

class _SpadesMatchState extends State<SpadesMatchDisplay> {
  final rng = Random();
  var animationMode = AnimationMode.none;
  bool showPostBidDialog = false;
  var aiMode = AiMode.humanPlayer0;
  int currentBidder = 0;
  Map<int, Mood> playerMoods = {};
  bool showScoreOverlay = false;
  late SpadesMatch match;
  late StreamSubscription matchUpdateSubscription;

  SpadesRound get round => match.currentRound;
  final suitDisplayOrder = [Suit.spades, Suit.hearts, Suit.clubs, Suit.diamonds];

  @override
  void initState() {
    super.initState();
    match = widget.initialMatchFn();
    matchUpdateSubscription = widget.matchUpdateStream.listen((event) {
      if (event is SpadesMatch) {
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

  void _updateMatch(SpadesMatch newMatch) {
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
    if (round.status == SpadesRoundStatus.playing) {
      _handleBiddingDone();
    } else {
      _scheduleNextActionIfNeeded();
    }
    widget.saveMatchFn(match);
  }

  void _makeBidForAiPlayer(int playerIndex) {
    int bid = chooseBid(BidRequest(
      scoresBeforeRound: round.initialScores,
      rules: round.rules,
      otherBids: round.bidsInOrderMade(),
      hand: round.players[playerIndex].hand,
    ));
    printd("P$playerIndex bids $bid");
    setState(() {
      _setBidForPlayer(bid: bid, playerIndex: playerIndex);
    });
  }

  void _scheduleNextAiBidIfNeeded() {
    if (round.status == SpadesRoundStatus.bidding && !_isWaitingForHumanBid()) {
      Future.delayed(const Duration(milliseconds: 1000), () {
        _makeBidForAiPlayer(round.currentBidder());
      });
    }
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

  void _scheduleNextAiPlayIfNeeded() {
    if (round.isOver()) {
      printd("Round done, scores: ${round.pointsTaken().map((p) => p.totalRoundPoints)}");
    } else if (round.currentPlayerIndex() != 0 && round.status == SpadesRoundStatus.playing) {
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
    if (round.status == SpadesRoundStatus.playing) {
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
      final currentStats = (await widget.statsStore.readSpadesStats()) ?? SpadesStats.empty();
      var newStats = currentStats.updateFromRound(round);
      if (match.isMatchOver()) {
        newStats = newStats.updateFromMatch(match);
      }
      widget.statsStore.writeSpadesStats(newStats);
    }
  }

  void _clearMoods() {
    playerMoods.clear();
  }

  void _updateMoodsAfterTrick() {
    // print(round.toJson());
    playerMoods.clear();
    if (match.isMatchOver()) {
      // Winners happy, losers sad.
      var winner = match.winningTeam();
      if (winner != null) {
        playerMoods[1] = playerMoods[3] = (winner == 1) ? Mood.veryHappy : Mood.mad;
        playerMoods[0] = playerMoods[2] = (winner == 1) ? Mood.mad : Mood.veryHappy;
      }
    } else if (round.isOver()) {
      // Happy if >=100 points, sad if <0.
      final scores = round.pointsTaken();
      if (scores[0].totalRoundPoints >= 100) {
        playerMoods[0] = playerMoods[2] = Mood.happy;
      }
      if (scores[0].totalRoundPoints < 0) {
        playerMoods[0] = playerMoods[2] = Mood.mad;
      }
      if (scores[1].totalRoundPoints >= 100) {
        playerMoods[1] = playerMoods[3] = Mood.happy;
      }
      if (scores[1].totalRoundPoints < 0) {
        playerMoods[1] = playerMoods[3] = Mood.mad;
      }
    } else {
      // Sad if took a trick after bidding nil.
      final tw = round.previousTricks.last.winner;
      if (round.players[tw].bid == 0 &&
          round.previousTricks.where((t) => t.winner == tw).toList().length == 1) {
        playerMoods[tw] = Mood.mad;
      }
    }
  }

  void _playSoundsForMoods() {
    if (match.isMatchOver()) {
      if (match.winningTeam() == 0) {
        widget.soundPlayer.playHappySound();
      }
      else {
        widget.soundPlayer.playMadSound();
      }
    }
    else {
      bool hasHappy = playerMoods.containsValue(Mood.happy) || playerMoods.containsValue(Mood.veryHappy);
      bool hasMad = playerMoods.containsValue(Mood.mad);
      if (hasHappy) {
        widget.soundPlayer.playHappySound();
      }
      if (hasMad) {
        widget.soundPlayer.playMadSound();
      }
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
    if (round.status == SpadesRoundStatus.playing && round.currentPlayerIndex() == 0) {
      if (round.legalPlaysForCurrentPlayer().contains(card)) {
        printd("Playing");
        _playCard(card);
      }
    }
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
    bool isHumanTurn = round.status == SpadesRoundStatus.playing && round.currentPlayerIndex() == 0;
    bool isBidding = round.status == SpadesRoundStatus.bidding;
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
        suitDisplayOrder: suitDisplayOrder,
        trumpSuit: widget.tintTrumpCards ? Suit.spades : null,
        cards: cards,
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
      trumpSuit: widget.tintTrumpCards ? Suit.spades : null,
      animationMode: animationMode,
      numPlayers: round.rules.numPlayers,
      humanPlayerHand: humanHand,
      humanPlayerSuitOrder: suitDisplayOrder,
      onTrickCardAnimationFinished: _trickCardAnimationFinished,
      onTrickToWinnerAnimationFinished: _trickToWinnerAnimationFinished,
    );
  }

  List<String> _currentRoundScoreMessages() {
    int teamScore(int p) {
      return round.initialScores[p % round.rules.numTeams];
    }

    if (round.status == SpadesRoundStatus.bidding) {
      return List.generate(round.rules.numPlayers, (i) => "Score: ${teamScore(i)}");
    }
    final messages = <String>[];
    for (int i = 0; i < round.rules.numPlayers; i++) {
      final tricksTaken = round.previousTricks.where((t) => t.winner == i).length;
      messages.add("Score: ${teamScore(i)}\nBid ${round.players[i].bid}, Took $tricksTaken");
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
    return (round.status == SpadesRoundStatus.bidding &&
        aiMode == AiMode.humanPlayer0 &&
        round.currentBidder() == 0);
  }

  bool _shouldShowHumanBidDialog() {
    return !widget.dialogVisible && _isWaitingForHumanBid();
  }

  bool _shouldShowPostBidDialog() {
    return !widget.dialogVisible && showPostBidDialog;
  }

  void makeBidForHuman(int bid) {
    printd("Human bids $bid");
    setState(() {
      _setBidForPlayer(bid: bid, playerIndex: 0);
    });
  }

  int maxPlayerBid() {
    final numTricks = round.rules.numberOfCardsPerPlayer;
    return max(1, numTricks - (round.players[2].bid ?? 0));
  }

  bool _shouldShowEndOfRoundDialog() {
    return !widget.dialogVisible && round.isOver();
  }

  List<Widget> bidSpeechBubbles(final Layout layout) {
    if (round.status != SpadesRoundStatus.bidding && !showPostBidDialog) return [];
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

    return Stack(
      children: <Widget>[
        _handCards(layout, round.players[0].hand),
        _trickCards(layout),
        if (_shouldShowHumanBidDialog())
          BidDialog(layout: layout, maxBid: maxPlayerBid(), onBid: makeBidForHuman),
        if (_shouldShowPostBidDialog())
          PostBidDialog(layout: layout, round: round, onConfirm: _handlePostBidDialogConfirm),
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

Widget _paddingAll(final double paddingPx, final Widget child) {
  return Padding(padding: EdgeInsets.all(paddingPx), child: child);
}

class BidDialog extends StatefulWidget {
  final Layout layout;
  final int maxBid;
  final void Function(int) onBid;

  const BidDialog({
    Key? key,
    required this.layout,
    required this.maxBid,
    required this.onBid,
  }) : super(key: key);

  @override
  _BidDialogState createState() => _BidDialogState();
}

class _BidDialogState extends State<BidDialog> {
  int bidAmount = 1;

  bool canIncrementBid() => (bidAmount < widget.maxBid);

  void incrementBid() {
    setState(() {
      bidAmount = min(bidAmount + 1, widget.maxBid);
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
    final adjustBidTextStyle = TextStyle(fontSize: 18);
    final rowPadding = 15.0;

    return Center(
        child: Transform.scale(scale: widget.layout.dialogScale(), child: Dialog(
            backgroundColor: dialogBackgroundColor,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _paddingAll(
                    15,
                    const Text("Choose your bid", style: TextStyle(fontSize: 18))),
                Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: canDecrementBid() ? decrementBid : null,
                        child: Text("–", style: adjustBidTextStyle),
                      ),
                      _paddingAll(
                          rowPadding, Text(bidAmount.toString(), style: adjustBidTextStyle)),
                      ElevatedButton(
                        onPressed: canIncrementBid() ? incrementBid : null,
                        child: Text("+", style: adjustBidTextStyle),
                      ),
                    ]),
                _paddingAll(
                    rowPadding,
                    Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton(
                            child: Text("Bid ${bidAmount == 0 ? "Nil" : bidAmount.toString()}"),
                            onPressed: () => widget.onBid(bidAmount),
                          ),
                        ])),
              ],
            ))));
  }
}

class PostBidDialog extends StatelessWidget {
  final Layout layout;
  final SpadesRound round;
  final Function() onConfirm;

  const PostBidDialog(
      {Key? key, required this.layout, required this.round, required this.onConfirm})
      : super(key: key);

  String playerBidMessage() {
    final playerBid = round.players[0].bid!;
    final partnerBid = round.players[2].bid!;
    final totalBid = playerBid + partnerBid;
    if (totalBid == 0) {
      return "You and your partner have both bid nil.";
    } else if (playerBid == 0) {
      return "Your team has bid $totalBid.\nYou bid nil.";
    } else if (partnerBid == 0) {
      return "Your team has bid $totalBid.\nYour partner bid nil.";
    } else {
      return "Your team has bid $totalBid.";
    }
  }

  String opponentBidMessage() {
    final westBid = round.players[1].bid!;
    final eastBid = round.players[3].bid!;
    final totalBid = westBid + eastBid;
    if (totalBid == 0) {
      return "Your opponents have both bid nil.";
    } else if (westBid == 0) {
      return "Your opponents have bid $totalBid.\nThe left opponent bid nil.";
    } else if (eastBid == 0) {
      return "Your opponents have bid $totalBid.\nThe right opponent bid nil.";
    } else {
      return "Your opponents have bid $totalBid.";
    }
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
            _paddingAll(
                halfPadding, Text(playerBidMessage(), style: textStyle, textAlign: TextAlign.left)),
            _paddingAll(halfPadding,
                Text(opponentBidMessage(), style: textStyle, textAlign: TextAlign.left)),
            _paddingAll(
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
  final SpadesMatch match;
  final Function() onContinue;
  final Function() onMainMenu;
  final List<int> catImageIndices;

  const EndOfRoundDialog({
    Key? key,
    required this.layout,
    required this.match,
    required this.onContinue,
    required this.onMainMenu,
    required this.catImageIndices,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final scores = match.currentRound.pointsTaken();
    const headerFontSize = 14.0;
    const pointsFontSize = headerFontSize * 1.2;
    const cellPad = 4.0;

    Widget pointsCell(Object p) => _paddingAll(cellPad,
        Text(p.toString(), textAlign: TextAlign.right, style: const TextStyle(fontSize: pointsFontSize)));

    Widget headerCell(String msg) => _paddingAll(
        cellPad,
        Text(msg,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: headerFontSize, fontWeight: FontWeight.bold)));

    const catImageHeight = headerFontSize * 1.3;

    Widget humanTeamHeaderCell() => Row(children: [
          const Text("You", style: TextStyle(fontSize: headerFontSize, fontWeight: FontWeight.bold)),
          const SizedBox(width: headerFontSize * 0.1),
          const Text("/", style: TextStyle(fontSize: headerFontSize, fontWeight: FontWeight.bold)),
          Image.asset(catImageForIndex(catImageIndices[2]), height: catImageHeight),
        ]);

    Widget opponentTeamHeaderCell() => Padding(
        padding: const EdgeInsets.only(left: headerFontSize * 1.25),
        child: Row(children: [
          Image.asset(catImageForIndex(catImageIndices[1]), height: catImageHeight),
          const Text(" /", style: TextStyle(fontSize: headerFontSize, fontWeight: FontWeight.bold)),
          Image.asset(catImageForIndex(catImageIndices[3]), height: catImageHeight),
        ]));

    TableRow pointsRow(String title, List<Object> points) => TableRow(children: [
          _paddingAll(cellPad, headerCell(title)),
          ...points.map((p) => _paddingAll(cellPad, pointsCell(p.toString())))
        ]);

    String matchOverMessage() => match.winningTeam() == 0 ? "You win!" : "You lose :(";

    bool anyNonzero(Iterable<int> xs) => xs.any((x) => x != 0);

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
                    _paddingAll(
                        10,
                        Text(matchOverMessage(), style: const TextStyle(fontSize: 26))),
                  ],
                ),
              _paddingAll(
                  10,
                  Table(
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    defaultColumnWidth: const IntrinsicColumnWidth(),
                    children: [
                      TableRow(children: [
                        _paddingAll(cellPad, const SizedBox()),
                        _paddingAll(cellPad, humanTeamHeaderCell()),
                        _paddingAll(cellPad, opponentTeamHeaderCell()),
                      ]),
                      pointsRow("Previous score", match.currentRound.initialScores),
                      pointsRow("Points from tricks",
                          [...scores.map((s) => s.successfulBidPoints + s.failedBidPoints)]),
                      if (match.rules.penalizeBags)
                        pointsRow("Bags", [...scores.map((s) => s.overtricks)]),
                      if (anyNonzero(scores.map((s) => s.overtrickPenalty)))
                        pointsRow("Bag penalty", [...scores.map((s) => s.overtrickPenalty)]),
                      if (anyNonzero(scores.map((s) => s.successfulNilPoints)))
                        pointsRow("Nil bid made",
                            [...scores.map((s) => s.successfulNilPoints)]),
                      if (anyNonzero(scores.map((s) => s.failedNilPoints)))
                        pointsRow("Nil bid failed",
                            [...scores.map((s) => s.failedNilPoints)]),
                      pointsRow("Total score", [...scores.map((s) => s.endingMatchPoints)]),
                    ],
                  )),
              if (match.isMatchOver())
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _paddingAll(
                        15,
                        ElevatedButton(
                          onPressed: onContinue,
                          child: const Text("Rematch"),
                        )),
                    _paddingAll(
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
                    _paddingAll(
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
