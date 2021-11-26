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
  const SpadesMatchDisplay({Key? key}) : super(key: key);

  @override
  _SpadesMatchState createState() => _SpadesMatchState();
}

class _SpadesMatchState extends State<SpadesMatchDisplay> {
  final rng = Random();
  final rules = SpadesRuleSet();
  var animationMode = AnimationMode.none;
  var aiMode = AiMode.human_player_0;
  var currentBidder = 0;
  late SpadesMatch match;

  SpadesRound get round => match.currentRound;

  @override void initState() {
    super.initState();
    _startMatch();
  }

  void _startMatch() {
    match = SpadesMatch(rules, rng);
    _startRound();
  }

  void _scheduleNextActionIfNeeded() {
    _scheduleNextAiBidIfNeeded();
    _scheduleNextPlayIfNeeded();
  }

  void _setBidForPlayer({required int bid, required int playerIndex}) {
    round.setBidForPlayer(bid: bid, playerIndex: playerIndex);
    _scheduleNextActionIfNeeded();
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
    if (round.isOver()) {
      match.finishRound();
    }
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
    if (round.status == SpadesRoundStatus.playing) {
      setState(() {
        round.playCard(card);
        animationMode = AnimationMode.moving_trick_card;
      });
    }
  }

  void _trickCardAnimationFinished() {
    if (!round.isOver() && round.currentTrick.cards.isNotEmpty) {
      setState(() {animationMode = AnimationMode.none;});
      _scheduleNextActionIfNeeded();
    }
    else {
      setState(() {animationMode = AnimationMode.moving_trick_to_winner;});
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

  bool _isWaitingForHumanBid() {
    return (
        round.status == SpadesRoundStatus.bidding &&
        aiMode == AiMode.human_player_0 && round.currentBidder() == 0
    );
  }

  void makeBidForHuman(int bid) {
    print("Human bids $bid");
    _setBidForPlayer(bid: bid, playerIndex: 0);
  }

  int maxPlayerBid() {
    final numTricks = round.rules.numberOfCardsPerPlayer;
    return max(1, numTricks - (round.players[2].bid ?? 0));
  }

  bool _shouldShowEndOfRoundDialog() {
    return round.isOver() && !match.isMatchOver();
  }

  bool _shouldShowEndOfMatchDialog() {
    return !match.isMatchOver();
  }

  List<Widget> bidSpeechBubbles(final Layout layout) {
    if (round.status != SpadesRoundStatus.bidding) return [];
    final bubbles = <Widget>[];
    for (int i = 0; i < round.rules.numPlayers; i++) {
      final bid = round.players[i].bid;
      if (bid != null) {
        bubbles.add(SpeechBubble(layout: layout, playerIndex: i, message: bid.toString()));
      }
    }
    return bubbles;
  }

  @override
  Widget build(BuildContext context) {
    final layout = computeLayout(context);

    return Stack(
      children: <Widget>[
        Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.green,
        ),
        ...[0, 1, 2, 3].map((i) => AiPlayerImage(layout: layout, playerIndex: i)),
        _handCards(layout, round.players[0].hand),
        _trickCards(layout),
        if (_isWaitingForHumanBid()) BidDialog(layout: layout, maxBid: maxPlayerBid(), onBid: makeBidForHuman),
        if (_shouldShowEndOfRoundDialog()) EndOfRoundDialog(
          round: round,
          onContinue: () => setState(_startRound),
        ),
        Text("${round.dealer.toString()} ${round.status}, ${round.players.map((p) => p.bid).toList()} ${_isWaitingForHumanBid()}"),
        ...bidSpeechBubbles(layout),
      ],
    );
  }
}

final dialogBackgroundColor = Color.fromARGB(0x80, 0xd8, 0xd8, 0xd8);

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
                        Text("Choose your bid!",
                            style: TextStyle(fontSize: widget.layout.dialogHeaderFontSize()))),
                    Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            child: Text("-", style: adjustBidTextStyle),
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
                                child: Text("Bid ${bidAmount == 0 ? "Nil" : bidAmount.toString()}",
                                    style: TextStyle(fontSize: widget.layout.dialogBaseFontSize())),
                                onPressed: () => widget.onBid(bidAmount),
                              ),
                        ])),
                  ],
                )
            )
        );

  }
}

class EndOfRoundDialog extends StatelessWidget {
  final SpadesRound round;
  final Function() onContinue;

  const EndOfRoundDialog({Key? key, required this.round, required this.onContinue}): super(key: key);

  @override
  Widget build(BuildContext context) {
    final scores = round.pointsTaken();
    const cellPad = 10.0;

    return Center(
      child: Dialog(
      backgroundColor: dialogBackgroundColor,
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            TableRow(children: [
              _paddingAll(cellPad, Text("")),
              _paddingAll(cellPad, Text("You")),
              _paddingAll(cellPad, Text("Them")),
            ]),
            TableRow(children: [
              _paddingAll(cellPad, Text("Round score")),
              _paddingAll(cellPad, Text(scores[0].totalRoundPoints.toString())),
              _paddingAll(cellPad, Text(scores[1].totalRoundPoints.toString())),
            ]),
            TableRow(children: [
              _paddingAll(cellPad, Text("Match score")),
              _paddingAll(cellPad, Text(scores[0].endingMatchPoints.toString())),
              _paddingAll(cellPad, Text(scores[1].endingMatchPoints.toString())),
            ]),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [_paddingAll(15, ElevatedButton(
            child: Text("Continue"),
            onPressed: onContinue,
          ))],
        ),
      ])));
  }
}
