import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hearts/cards/rollout.dart';
import 'package:hearts/hearts/hearts.dart';
import 'package:hearts/hearts/hearts_ai.dart';

import 'cards/card.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CatTricks',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'CatTricks'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

enum AnimationMode {
  none,
  playing_trick_card,
  moving_trick_to_winner,
}

class Layout {
  late Size displaySize;
  late double edgePx;

  Rect cardArea() {
    return Rect.fromLTRB(edgePx, edgePx, displaySize.width - edgePx, displaySize.height - edgePx);
  }

  Rect areaForTrickCard(int playerIndex) {
    final ca = cardArea();
    final cardHeight = ca.height * 0.4;
    final cardWidth = ca.width * 0.4;
    final centerXFrac = (playerIndex == 1) ?
        0.25 :
        (playerIndex == 3) ? 0.75 : 0.5;
    final centerYFrac = (playerIndex == 0) ?
        0.75 :
        (playerIndex == 2) ? 0.25 : 0.5;
    final centerX = ca.left + ca.width * centerXFrac;
    final centerY = ca.top + ca.height * centerYFrac;
    return Rect.fromLTWH(centerX - cardWidth / 2, centerY - cardHeight / 2, cardWidth, cardHeight);
  }
}

PlayingCard computeCard(final CardToPlayRequest req) {
  return chooseCardMonteCarlo(
      req,
      MonteCarloParams(numHands: 20, rolloutsPerHand: 50),
      chooseCardAvoidingPoints,
      Random());
}

class _MyHomePageState extends State<MyHomePage> {
  final rng = Random();
  final rules = HeartsRuleSet();
  var animationMode = AnimationMode.none;
  late HeartsRound round;

  @override void initState() {
    super.initState();
    round = HeartsRound.deal(rules, List.filled(4, 0), 0, rng);
    Future.delayed(Duration(milliseconds: 500), () => _playNextCard());
  }

  void _playNextCard() async {
    if (round.isOver()) {
      round = HeartsRound.deal(rules, List.filled(4, 0), 0, rng);
    }

    // Do this in a separate thread/isolate.
    /*
    final card = chooseCardMonteCarlo(
        CardToPlayRequest.fromRound(round),
        MonteCarloParams(numHands: 20, rolloutsPerHand: 50),
        chooseCardAvoidingPoints,
        rng);
     */
    final card = await compute(computeCard, CardToPlayRequest.fromRound(round));
    setState(() {
      round.playCard(card);
    });
    Future.delayed(Duration(milliseconds: 500), () => _playNextCard());
  }

  Widget _positionedCard(final Rect rect, final PlayingCard card) {
    final cardImagePath = "assets/cards/${card.toString()}.webp";
    // TODO: Click handler.
    return Positioned(
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
        child: Container(
            child: Image(
              image: AssetImage(cardImagePath),
              fit: BoxFit.contain,
              alignment: Alignment.center,
            )));
  }

  Widget _handCards(final Layout layout, final List<PlayingCard> cards) {
    final cardWidthFrac = 0.15;
    final cardOverlapWidthFrac = 0.1;
    final totalWidthFrac = (int n) => cardWidthFrac + (n - 1) * cardOverlapWidthFrac;
    final cardWidth = cardWidthFrac * layout.displaySize.width;

    final cardHeightFrac = 0.2;
    final cardHeight = cardHeightFrac * layout.displaySize.height;

    final upperRowHeightFracStart = 0.65;
    final lowerRowHeightFracStart = 0.75;
    final List<Widget> cardImages = [];

    if (cards.length > 7) {
      final numUpperCards = (cards.length + 1) ~/ 2;
      final numLowerCards = cards.length - numUpperCards;
      final upperWidthFrac = totalWidthFrac(numUpperCards);
      final upperStartX = 0.5 - upperWidthFrac / 2;
      for (int i = 0; i < numUpperCards; i++) {
        final left = (upperStartX + (cardOverlapWidthFrac * (i - 1))) * layout.displaySize.width;
        final top = upperRowHeightFracStart * layout.displaySize.height;
        Rect cardRect = Rect.fromLTWH(left, top, cardWidth, cardHeight);
        cardImages.add(_positionedCard(cardRect, cards[i]));
      }
      for (int i = 0; i < numLowerCards; i++) {
        final left = (upperStartX + (cardOverlapWidthFrac * (i - 1 + 0.5))) * layout.displaySize.width;
        final top = lowerRowHeightFracStart * layout.displaySize.height;
        Rect cardRect = Rect.fromLTWH(left, top, cardWidth, cardHeight);
        cardImages.add(_positionedCard(cardRect, cards[numUpperCards + i]));
      }
    }
    else {
      final startX = 0.5 - totalWidthFrac(cards.length) / 2;
      for (int i = 0; i < cards.length; i++) {
        final left = (startX + (cardOverlapWidthFrac * (i - 1 + 0.5))) * layout.displaySize.width;
        final top = lowerRowHeightFracStart * layout.displaySize.height;
        Rect cardRect = Rect.fromLTWH(left, top, cardWidth, cardHeight);
        cardImages.add(_positionedCard(cardRect, cards[i]));
      }
    }
    return Stack(children: cardImages);
  }

  Widget _trickCardForPlayer(final Layout layout, final PlayingCard card, int playerIndex) {
    final cardRect = layout.areaForTrickCard(playerIndex);
    return _positionedCard(cardRect, card);
  }

  Widget _trickCards(final Layout layout) {
    List<Widget> cardWidgets = [];
    if (round.currentTrick.cards.isNotEmpty) {
      for (int i = 0; i < round.currentTrick.cards.length; i++) {
        int p = (round.currentTrick.leader + i) % round.rules.numPlayers;
        cardWidgets.add(_trickCardForPlayer(layout, round.currentTrick.cards[i], p));
      }
    }
    else if (round.previousTricks.isNotEmpty) {
      final trick = round.previousTricks.last;
      for (int i = 0; i < trick.cards.length; i++) {
        int p = (trick.leader + i) % round.rules.numPlayers;
        cardWidgets.add(_trickCardForPlayer(layout, trick.cards[i], p));
      }
    }
    return Stack(children: cardWidgets);
  }

  Widget _aiPlayerWidget(final Layout layout, int playerIndex) {
    final imagePath = "assets/cats/cat${playerIndex + 1}.png";
    final imageAspectRatio = 156 / 112;
    final displaySize = layout.displaySize;
    final playerSize = layout.edgePx;

    final rect = (() {
      switch (playerIndex) {
        case 0:
          return Rect.fromLTWH(0, displaySize.height - playerSize, displaySize.width, playerSize);
        case 1:
          return Rect.fromLTWH(0, 0, playerSize, displaySize.height);
        case 2:
          return Rect.fromLTWH(0, 0, displaySize.width, playerSize);
        case 3:
          return Rect.fromLTWH(displaySize.width - playerSize, 0, playerSize, displaySize.height);
        default:
          return Rect.fromLTWH(0, 0, 0, 0);
      }
    })();
    final angle = (playerIndex - 2) * pi / 2;
    final scale = (playerIndex == 1 || playerIndex == 3) ? imageAspectRatio : 1.0;

    return Positioned(
      top: rect.top,
      left: rect.left,
      width: rect.width,
      height: rect.height,

      child: Container(
        color: Colors.white70,
        width: rect.width,
        height: rect.height,
        // The image won't naturally take up the full width If rotated 90 degrees,
        // so in that case scale by the aspect ratio.
        child: Transform.scale(scale: scale, child: Transform.rotate(angle: angle, child: Image(
          image: AssetImage(imagePath),
          fit: BoxFit.contain,
          alignment: Alignment.center,
        ))),
      ),

      // child: Text("Hello $playerNum"),
    );
  }

  Layout computeLayout() {
    final ds = MediaQuery.of(context).size;
    return Layout()
        ..displaySize = ds
        ..edgePx = max(ds.width / 20, ds.height / 15)
        ;
  }

  @override
  Widget build(BuildContext context) {
    final layout = computeLayout();

    return Scaffold(
      body: Stack(
          children: <Widget>[
            Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.green,
            ),
            ...[0, 1, 2, 3].map((i) => _aiPlayerWidget(layout, i)),
            _trickCards(layout),
            _handCards(layout, round.players[0].hand),
          ],
        ),
    );
  }
}
