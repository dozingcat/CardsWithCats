import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import 'common_ui.dart';
import 'cards/card.dart';
import 'cards/rollout.dart';
import 'spades/spades.dart';
import 'spades/spades_ai.dart';

PlayingCard computeCard(final CardToPlayRequest req) {
  return chooseCardMonteCarlo(
      req,
      MonteCarloParams(numHands: 20, rolloutsPerHand: 50),
      chooseCardRandom,
      Random());
}

class SpadesMatchDisplay extends StatefulWidget {
  final SpadesMatch Function() initialMatchFn;
  final SpadesMatch Function() createMatchFn;
  final void Function(SpadesMatch?) saveMatchFn;
  final void Function() mainMenuFn;
  final Stream matchUpdateStream;
  final bool dialogVisible;

  const SpadesMatchDisplay({
    Key? key,
    required this.initialMatchFn,
    required this.createMatchFn,
    required this.saveMatchFn,
    required this.mainMenuFn,
    required this.matchUpdateStream,
    required this.dialogVisible,
  }) : super(key: key);

  @override
  _SpadesMatchState createState() => _SpadesMatchState();
}

class _SpadesMatchState extends State<SpadesMatchDisplay> {
  final rng = Random();
  var animationMode = AnimationMode.none;
  bool showPostBidDialog = false;
  var aiMode = AiMode.human_player_0;
  int currentBidder = 0;
  Map<int, Mood> playerMoods = {};
  bool showScoreOverlay = false;
  late SpadesMatch match;
  late StreamSubscription matchUpdateSubscription;

  SpadesRound get round => match.currentRound;

  @override void initState() {
    super.initState();
    match = widget.initialMatchFn();
    matchUpdateSubscription = widget.matchUpdateStream.listen((event) {
      if (event is SpadesMatch) {
        _updateMatch(event);
      }
    });
    _scheduleNextActionIfNeeded();
  }

  @override void deactivate() {
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
    _scheduleNextPlayIfNeeded();
  }

  bool hasHumanPlayer() {
    return aiMode == AiMode.human_player_0;
  }

  void _handleBiddingDone() {
    if (hasHumanPlayer()) {
      setState(() {showPostBidDialog = true;});
    }
    else {
      Future.delayed(const Duration(milliseconds: 1000), () {
        _scheduleNextActionIfNeeded();
      });
    }
  }

  void _handlePostBidDialogConfirm() {
    setState(() {showPostBidDialog = false;});
    _scheduleNextActionIfNeeded();
  }

  void _setBidForPlayer({required int bid, required int playerIndex}) {
    round.setBidForPlayer(bid: bid, playerIndex: playerIndex);
    if (round.status == SpadesRoundStatus.playing) {
      _handleBiddingDone();
    }
    else {
      _scheduleNextActionIfNeeded();
    }
    widget.saveMatchFn(match);
  }

  void _makeBidForAiPlayer(int playerIndex) {
    int bid = chooseBid(BidRequest(
      scoresBeforeRound: round.initialScores,
      rules: round.rules,
      otherBids: [],
      hand: round.players[playerIndex].hand,
    ));
    print("P$playerIndex bids $bid");
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

  void _scheduleNextPlayIfNeeded() {
    if (round.isOver()) {
      print("Round done, scores: ${round.pointsTaken().map((p) => p.totalRoundPoints)}");
    }
    else if (round.currentPlayerIndex() != 0 && round.status == SpadesRoundStatus.playing) {
      Future.delayed(const Duration(milliseconds: 500), _playNextCard);
    }
  }

  void _playCard(final PlayingCard card) {
    _clearMoods();
    if (round.status == SpadesRoundStatus.playing) {
      setState(() {
        round.playCard(card);
        animationMode = AnimationMode.moving_trick_card;
      });
    }
    widget.saveMatchFn(match);
  }

  void _clearMoods() {
    playerMoods.clear();
  }

  void _updateMoodsAfterTrick() {
    print(round.toJson());
    playerMoods.clear();
    final lastTrick = round.previousTricks.last;
    // playerMoods[lastTrick.winner] = Mood.happy;
    if (match.isMatchOver()) {
      // Winners happy, losers sad.
      var winner = match.winningTeam();
      if (winner != null) {
        playerMoods[1] = playerMoods[3] = (winner == 1) ? Mood.veryHappy : Mood.mad;
        playerMoods[0] = playerMoods[2] = (winner == 1) ? Mood.mad : Mood.veryHappy;
      }
    }
    else if (round.isOver()) {
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
    }
    else {
      // Sad if took a trick after bidding nil.
      final tw = round.previousTricks.last.winner;
      if (round.players[tw].bid == 0 && round.previousTricks.where((t) => t.winner == tw).toList().length == 1) {
        playerMoods[tw] = Mood.mad;
      }
    }
  }

  void _trickCardAnimationFinished() {
    if (!round.isOver() && round.currentTrick.cards.isNotEmpty) {
      setState(() {animationMode = AnimationMode.none;});
      _scheduleNextActionIfNeeded();
    }
    else {
      setState(() {
        animationMode = AnimationMode.moving_trick_to_winner;
        _updateMoodsAfterTrick();
      });
    }
  }

  void _trickToWinnerAnimationFinished() {
    setState(() {animationMode = AnimationMode.none;});
    _scheduleNextActionIfNeeded();
  }

  void _playNextCard() async {
    // Do this in a separate thread/isolate.
    final card = await compute(computeCard, CardToPlayRequest.fromRound(round));
    _playCard(card);
  }

  void handleHandCardClicked(final PlayingCard card) {
    print("Clicked ${card.toString()}, status: ${round.status}, index: ${round.currentPlayerIndex()}");
    if (round.status == SpadesRoundStatus.playing && round.currentPlayerIndex() == 0) {
      if (round.legalPlaysForCurrentPlayer().contains(card)) {
        print("Playing");
        _playCard(card);
      }
    }
  }

  Widget _handCards(final Layout layout, final List<PlayingCard> cards) {
    final rects = playerHandCardRects(layout, cards);

    bool isHumanTurn = round.status == SpadesRoundStatus.playing && round.currentPlayerIndex() == 0;
    List<PlayingCard> highlightedCards = [];
    if (isHumanTurn) {
      highlightedCards = round.legalPlaysForCurrentPlayer();
    }

    bool isBidding = round.status == SpadesRoundStatus.bidding;

    final List<Widget> cardImages = [];
    for (final entry in rects.entries) {
      final card = entry.key;
      cardImages.add(PositionedCard(
        rect: entry.value,
        card: card,
        opacity: isBidding || highlightedCards.contains(card) ? 1.0 : 0.5,
        onCardClicked: (card) => handleHandCardClicked(card),
      ));
    }
    return Stack(children: cardImages);
  }


  Widget _trickCards(final Layout layout) {
    final humanHand = aiMode == AiMode.human_player_0 ? round.players[0].hand : null;
    return TrickCards(
      layout: layout,
      currentTrick: round.currentTrick,
      previousTricks: round.previousTricks,
      animationMode: animationMode,
      numPlayers: round.rules.numPlayers,
      humanPlayerHand: humanHand,
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
    return (
        round.status == SpadesRoundStatus.bidding &&
        aiMode == AiMode.human_player_0 && round.currentBidder() == 0
    );
  }

  bool _shouldShowHumanBidDialog() {
    return !widget.dialogVisible && _isWaitingForHumanBid();
  }

  bool _shouldShowPostBidDialog() {
    return !widget.dialogVisible && showPostBidDialog;
  }

  void makeBidForHuman(int bid) {
    print("Human bids $bid");
    setState(() {_setBidForPlayer(bid: bid, playerIndex: 0);});
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
      padding: EdgeInsets.fromLTRB(10, 80, 10, 10),
      child: FloatingActionButton(
        onPressed: () {setState(() {showScoreOverlay = !showScoreOverlay;});},
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
        if (_shouldShowHumanBidDialog()) BidDialog(layout: layout, maxBid: maxPlayerBid(), onBid: makeBidForHuman),
        if (_shouldShowPostBidDialog()) PostBidDialog(layout: layout, round: round, onConfirm: _handlePostBidDialogConfirm),
        if (_shouldShowEndOfRoundDialog()) EndOfRoundDialog(
          layout: layout,
          match: match,
          onContinue: () => setState(_startRound),
          onMainMenu: _showMainMenuAfterMatch,
        ),
        ...bidSpeechBubbles(layout),
        PlayerMoods(layout: layout, moods: playerMoods),
        if (shouldShowScoreOverlay())
          PlayerMessagesOverlay(layout: layout, messages: _currentRoundScoreMessages()),
        if (shouldShowScoreOverlayToggle())
          scoreOverlayButton(),
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
    setState(() {bidAmount = min(bidAmount + 1, widget.maxBid);});
  }

  bool canDecrementBid() => (bidAmount > 0);

  void decrementBid() {
    setState(() {bidAmount = max(bidAmount - 1, 0);});
  }

  @override
  Widget build(BuildContext context) {
    final adjustBidTextStyle = TextStyle(fontSize: widget.layout.dialogHeaderFontSize());
    final rowPadding = widget.layout.dialogBaseFontSize();

    return Center(
            child: Dialog(
                backgroundColor: dialogBackgroundColor,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _paddingAll(15,
                        Text("Choose your bid",
                            style: TextStyle(fontSize: widget.layout.dialogHeaderFontSize()))),
                    Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            child: Text("–", style: adjustBidTextStyle),
                            onPressed: canDecrementBid() ? decrementBid : null,
                          ),
                          _paddingAll(rowPadding, Text(bidAmount.toString(), style: adjustBidTextStyle)),
                          ElevatedButton(
                            child: Text("+", style: adjustBidTextStyle),
                            onPressed: canIncrementBid() ? incrementBid : null,
                          ),
                        ]),
                    _paddingAll(rowPadding,
                        Row(mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton(
                                child: _paddingAll(widget.layout.dialogBaseFontSize() * 0.3,
                                    Text("Bid ${bidAmount == 0 ? "Nil" : bidAmount.toString()}",
                                        style: TextStyle(fontSize: widget.layout.dialogBaseFontSize()))),
                                    onPressed: () => widget.onBid(bidAmount),
                              ),
                        ])),
                  ],
                )
            )
        );
  }
}

class PostBidDialog extends StatelessWidget {
  final Layout layout;
  final SpadesRound round;
  final Function() onConfirm;

  const PostBidDialog({Key? key, required this.layout, required this.round, required this.onConfirm}): super(key: key);

  String playerBidMessage() {
    final playerBid = round.players[0].bid!;
    final partnerBid = round.players[2].bid!;
    final totalBid = playerBid + partnerBid;
    if (totalBid == 0) {
      return "You and your partner have both bid nil.";
    }
    else if (playerBid == 0) {
      return "Your team has bid $totalBid. You bid nil.";
    }
    else if (partnerBid == 0) {
      return "Your team has bid $totalBid. Your partner bid nil.";
    }
    else {
      return "Your team has bid $totalBid.";
    }
  }

  String opponentBidMessage() {
    final westBid = round.players[1].bid!;
    final eastBid = round.players[3].bid!;
    final totalBid = westBid + eastBid;
    if (totalBid == 0) {
      return "Your opponents have both bid nil.";
    }
    else if (westBid == 0) {
      return "Your opponents have bid $totalBid. The left opponent bid nil.";
    }
    else if (eastBid == 0) {
      return "Your opponents have bid $totalBid. The right opponent bid nil.";
    }
    else {
      return "Your opponents have bid $totalBid.";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Dialog(
        backgroundColor: dialogBackgroundColor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _paddingAll(15, Text(playerBidMessage())),
            _paddingAll(15, Text(opponentBidMessage())),
            _paddingAll(15, ElevatedButton(
              child: Text("Start round"),
              onPressed: onConfirm,
            )),
          ],
        )
      )
    );
  }
}

class EndOfRoundDialog extends StatelessWidget {
  final Layout layout;
  final SpadesMatch match;
  final Function() onContinue;
  final Function() onMainMenu;

  const EndOfRoundDialog({
    Key? key,
    required this.layout,
    required this.match,
    required this.onContinue,
    required this.onMainMenu,
  }): super(key: key);

  @override
  Widget build(BuildContext context) {
    final scores = match.currentRound.pointsTaken();
    final headerFontSize = layout.dialogBaseFontSize() * 0.9;
    final pointsFontSize = layout.dialogBaseFontSize() * 1.2;
    const cellPad = 4.0;

    Widget pointsCell(Object p) => _paddingAll(
        cellPad,
        Text(p.toString(),
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: pointsFontSize)));

    Widget headerCell(String msg) => _paddingAll(
      cellPad,
        Text(msg,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: headerFontSize, fontWeight: FontWeight.bold)));

    TableRow pointsRow(String title, List<Object> points) => TableRow(children: [
      _paddingAll(cellPad, headerCell(title)),
      ...points.map((p) => _paddingAll(cellPad, pointsCell(p.toString())))
    ]);

    String matchOverMessage() =>
        match.winningTeam() == 0 ? "You win!" : "You lose :(";

    bool anyNonzero(Iterable<int> xs) => xs.any((x) => x != 0);

    final dialog = Center(
      child: Dialog(
      backgroundColor: dialogBackgroundColor,
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (match.isMatchOver()) Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _paddingAll(10, Text(matchOverMessage(), style: TextStyle(fontSize: layout.dialogHeaderFontSize()))),
          ],
        ),
        _paddingAll(10, Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            TableRow(children: [
              _paddingAll(cellPad, headerCell("")),
              _paddingAll(cellPad, headerCell("You")),
              _paddingAll(cellPad, headerCell("Them")),
            ]),
            pointsRow("Previous score", match.currentRound.initialScores),
            pointsRow("Points from tricks", [...scores.map((s) => s.successfulBidPoints + s.failedBidPoints)]),
            if (match.rules.penalizeBags)
              pointsRow("Bags", [...scores.map((s) => s.overtricks)]),
            if (anyNonzero(scores.map((s) => s.overtrickPenalty)))
              pointsRow("Bag penalty", [...scores.map((s) => s.overtrickPenalty)]),
            if (anyNonzero(scores.map((s) => s.successfulNilPoints + s.failedNilPoints)))
              pointsRow("Points from nil bids", [...scores.map((s) => s.successfulNilPoints + s.failedNilPoints)]),
            pointsRow("Total score", [...scores.map((s) => s.endingMatchPoints)]),
          ],
        )),
        if (match.isMatchOver()) Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _paddingAll(15, ElevatedButton(
              child: const Text("New Game"),
              onPressed: onContinue,
            )),
            _paddingAll(15, ElevatedButton(
              child: const Text("Main Menu"),
              onPressed: onMainMenu,
            )),
          ],
        ),
        if (!match.isMatchOver()) Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [_paddingAll(15, ElevatedButton(
            child: const Text("Continue"),
            onPressed: onContinue,
          ))],
        ),
      ])));

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: -1.0, end: 1.0),
      duration: const Duration(milliseconds: 1000),
      child: dialog,
      builder: (context, val, child) => Opacity(opacity: val.clamp(0.0, 1.0), child: child),
    );
    return dialog;
  }
}
