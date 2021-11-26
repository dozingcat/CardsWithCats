import 'dart:collection';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'cards/card.dart';
import 'cards/trick.dart';

enum AnimationMode {
  none,
  moving_passed_cards,
  moving_trick_card,
  moving_trick_to_winner,
}

enum AiMode {
  all_ai,
  human_player_0,
}

class Layout {
  late Size displaySize;
  late double edgePx;

  Rect cardArea() {
    return Rect.fromLTRB(edgePx, edgePx, displaySize.width - edgePx, displaySize.height - edgePx);
  }

  Size baseCardSize() {
    final ca = cardArea();
    return Size(ca.width * 0.4, ca.height * 0.4);
  }

  Rect trickCardAreaForPlayer(int playerIndex) {
    final ca = cardArea();
    final cs = baseCardSize();
    final centerXFrac = (playerIndex == 1) ?
    0.25 :
    (playerIndex == 3) ? 0.75 : 0.5;
    final centerYFrac = (playerIndex == 0) ?
    0.75 :
    (playerIndex == 2) ? 0.25 : 0.5;
    final centerX = ca.left + ca.width * centerXFrac;
    final centerY = ca.top + ca.height * centerYFrac;
    return Rect.fromLTWH(centerX - cs.width / 2, centerY - cs.height / 2, cs.width, cs.height);
  }

  Rect cardOriginAreaForPlayer(int playerIndex) {
    final w = displaySize.width;
    final h = displaySize.height;
    final ca = cardArea();
    final cardHeight = ca.height * 0.4;
    final cardWidth = ca.width * 0.4;
    switch (playerIndex) {
      case 0:
        return Rect.fromCenter(
            center: Offset(w / 2, h + cardHeight / 2), width: cardWidth, height: cardHeight);
      case 1:
        return Rect.fromCenter(
            center: Offset(-cardWidth / 2, h / 2), width: cardWidth, height: cardHeight);
      case 2:
        return Rect.fromCenter(
            center: Offset(w / 2, -cardHeight / 2), width: cardWidth, height: cardHeight);
      case 3:
        return Rect.fromCenter(
            center: Offset(w  + cardWidth / 2, h / 2), width: cardWidth, height: cardHeight);
      default:
        throw Exception("Bad player index: $playerIndex");
    }
  }

  double dialogBaseFontSize() {
    return max(16, displaySize.shortestSide / 30);
  }

  double dialogHeaderFontSize() {
    return max(26, displaySize.shortestSide / 20);
  }
}

class PositionedCard extends StatelessWidget {
  final Rect rect;
  final PlayingCard card;
  final double opacity;
  final void Function(PlayingCard) onCardClicked;

  const PositionedCard({
    Key? key,
    required this.rect,
    required this.card,
    required this.onCardClicked,
    this.opacity = 1.0,
  }): super(key: key);

  @override
  Widget build(BuildContext context) {
    final cardImagePath = "assets/cards/${card.toString()}.webp";
    const backgroundImagePath = "assets/cards/black.webp";
    return Positioned(
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
        child: GestureDetector(
            onTapDown: (tap) => onCardClicked(card),
            child: Stack(children: [
              if (opacity < 1) const Center(child: Image(
                image: AssetImage(backgroundImagePath),
                fit: BoxFit.contain,
                alignment: Alignment.center,
              )),
              Center(child: Image(
                color: Color.fromRGBO(255, 255, 255, opacity),
                colorBlendMode: BlendMode.modulate,
                image: AssetImage(cardImagePath),
              )),
            ])));
  }
}

class AiPlayerImage extends StatelessWidget {
  final Layout layout;
  final int playerIndex;

  const AiPlayerImage({Key? key, required this.layout, required this.playerIndex}): super(key: key);

  @override
  Widget build(BuildContext context) {
    final imagePath = "assets/cats/cat${playerIndex + 1}.png";
    const imageAspectRatio = 156 / 112;
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
          return const Rect.fromLTWH(0, 0, 0, 0);
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
}

class SpeechBubble extends StatelessWidget {
  final Layout layout;
  final int playerIndex;
  final String message;
  final double widthFraction;
  static const imageAspectRatio = 640.0 / 574;
  static const imagePath = "assets/misc/speech_bubble.png";

  const SpeechBubble({
    Key? key,
    required this.layout,
    required this.playerIndex,
    required this.message,
    this.widthFraction = 0.2,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var transform = Matrix4.identity();
    final dh = layout.displaySize.height;
    final dw = layout.displaySize.width;
    final playerHeight = layout.edgePx;
    final imageWidth = min(playerHeight * 1.5, widthFraction * dw);
    final imageHeight = imageWidth / imageAspectRatio;
    final fontSize = imageHeight / 2;
    var top = 0.0;
    var left = 0.0;
    switch (playerIndex) {
      case 1:
        left = playerHeight / 2;
        top = dh / 2 - playerHeight * 1.6 / 2 - imageHeight;
        break;
      case 2:
        transform = Matrix4.rotationX(pi);
        left = dw / 2;
        top = playerHeight * 1.1;
        break;
      case 3:
        transform = Matrix4.rotationY(pi);
        left = dw - playerHeight / 2 - imageWidth;
        top = dh / 2 - playerHeight * 1.6 / 2 - imageHeight;
        break;
      case 0:
        left = dw / 2 - playerHeight / 2;
        top = dh - playerHeight - imageHeight;
        break;
    }

    return Positioned(
      top: top,
      left: left,
      width: imageWidth,
      height: imageHeight,

      child: Stack(children: [
        SizedBox(
          width: imageWidth,
          height: imageHeight,
          child: Transform(alignment: Alignment.center, transform: transform, child: const Image(
            image: AssetImage(imagePath),
            fit: BoxFit.contain,
            alignment: Alignment.center,
          )),
        ),
        Center(child: Column(children: [
          SizedBox(height: imageHeight * (playerIndex == 2 ? 0.33: 0.06)),
          Text(message, style: TextStyle(fontSize: fontSize)),
        ])),
      ],
    ));
  }
}

class TrickCards extends StatelessWidget {
  final Layout layout;
  final TrickInProgress currentTrick;
  final List<Trick> previousTricks;
  final AnimationMode animationMode;
  final int numPlayers;
  final void Function() onTrickCardAnimationFinished;
  final void Function() onTrickToWinnerAnimationFinished;
  final List<PlayingCard>? humanPlayerHand;

  const TrickCards({
    Key? key,
    required this.layout,
    required this.currentTrick,
    required this.previousTricks,
    required this.animationMode,
    required this.numPlayers,
    required this.onTrickCardAnimationFinished,
    required this.onTrickToWinnerAnimationFinished,
    this.humanPlayerHand,
  }): super(key: key);

  @override
  Widget build(BuildContext context) {
    if (animationMode == AnimationMode.moving_trick_to_winner) {
      return _trickCardsAnimatingToWinner(layout, previousTricks.last);
    }
    List<Widget> cardWidgets = [];
    if (currentTrick.cards.isNotEmpty) {
      if (animationMode == AnimationMode.moving_trick_card) {
        cardWidgets.addAll(_trickCardsWithLastAnimating(
            layout, currentTrick.leader, numPlayers, currentTrick.cards));
      }
      else {
        cardWidgets.addAll(_staticTrickCards(
            layout, currentTrick.leader, numPlayers, currentTrick.cards));
      }
    }
    else if (previousTricks.isNotEmpty) {
      final trick = previousTricks.last;
      if (animationMode == AnimationMode.moving_trick_card) {
        cardWidgets.addAll(_trickCardsWithLastAnimating(
            layout, trick.leader, numPlayers, trick.cards));
      }
      else {
        // Finished animating trick to winner, don't show any cards.
      }
    }
    return Stack(children: cardWidgets);
  }

  Widget _trickCardForPlayer(final Layout layout, final PlayingCard card, int playerIndex) {
    final cardRect = layout.trickCardAreaForPlayer(playerIndex);
    return PositionedCard(rect: cardRect, card: card, onCardClicked: (_) => {});
  }

  List<Widget> _staticTrickCards(
      final Layout layout, int leader, int numPlayers, List<PlayingCard> cards) {
    List<Widget> cardWidgets = [];
    for (int i = 0; i < cards.length; i++) {
      int p = (leader + i) % numPlayers;
      cardWidgets.add(_trickCardForPlayer(layout, cards[i], p));
    }
    return cardWidgets;
  }

  List<Widget> _trickCardsWithLastAnimating(
      final Layout layout, int leader, int numPlayers, List<PlayingCard> cards) {
    final cardsWithoutLast = cards.sublist(0, cards.length - 1);
    List<Widget> cardWidgets =
    List.of(_staticTrickCards(layout, leader, numPlayers, cardsWithoutLast));
    final animPlayer = (leader + cards.length - 1) % numPlayers;
    final endRect = layout.trickCardAreaForPlayer(animPlayer);
    var startRect = layout.cardOriginAreaForPlayer(animPlayer);
    if (animPlayer == 0 && humanPlayerHand != null) {
      // We want to know where the card was drawn in the player's hand. It's not
      // there now, so we have to compute the card rects as if it were.
      final previousHandCards = [...humanPlayerHand!, cards.last];
      startRect = playerHandCardRects(layout, previousHandCards)[cards.last]!;
    }

    cardWidgets.add(TweenAnimationBuilder(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 200),
        onEnd: onTrickCardAnimationFinished,
        builder: (BuildContext context, double frac, Widget? child) {
          final animRect = Rect.lerp(startRect, endRect, frac)!;
          return PositionedCard(
              rect: animRect, card: cards.last, onCardClicked: (_) => {});
        }));

    return cardWidgets;
  }

  Widget _trickCardsAnimatingToWinner(final Layout layout, final Trick trick) {
    // Negative animation value means not moving. It might be better to have
    // a separate state for "waiting to move trick", but that would make state
    // transition logic more complex.
    return TweenAnimationBuilder(
        tween: Tween(begin: -3.0, end: 1.0),
        duration: const Duration(milliseconds: 1000),
        onEnd: onTrickToWinnerAnimationFinished,
        builder: (BuildContext context, double t, Widget? child) {
          final List<Widget> cardWidgets = [];
          final endRect = layout.cardOriginAreaForPlayer(trick.winner);
          for (int i = 0; i < trick.cards.length; i++) {
            int p = (trick.leader + i) % trick.cards.length;
            final startRect = layout.trickCardAreaForPlayer(p);
            final center = startRect.center + (endRect.center - startRect.center) * max(0, t);
            Rect animRect = Rect.fromCenter(
                center: center, width: endRect.width, height: endRect.height);
            cardWidgets.add(PositionedCard(
                rect: animRect, card: trick.cards[i], onCardClicked: (_) => {}));
          }
          return Stack(children: cardWidgets);
        });
  }
}

LinkedHashMap<PlayingCard, Rect> playerHandCardRects(Layout layout, List<PlayingCard> cards) {
  final rects = LinkedHashMap<PlayingCard, Rect>();
  final cardWidthFrac = 0.1875;
  final cardOverlapWidthFrac = 0.125;
  final totalWidthFrac = (int n) => cardWidthFrac + (n - 1) * cardOverlapWidthFrac;
  final cardWidth = cardWidthFrac * layout.displaySize.width;

  final cardHeightFrac = 0.2;
  final cardHeight = cardHeightFrac * layout.displaySize.height;

  final upperRowHeightFracStart = 0.69;
  final lowerRowHeightFracStart = 0.79;

  List sortedCards = [
    ...sortedCardsInSuit(cards, Suit.hearts),
    ...sortedCardsInSuit(cards, Suit.spades),
    ...sortedCardsInSuit(cards, Suit.diamonds),
    ...sortedCardsInSuit(cards, Suit.clubs),
  ];

  if (sortedCards.length > 7) {
    final numUpperCards = (sortedCards.length + 1) ~/ 2;
    final numLowerCards = sortedCards.length - numUpperCards;
    final upperWidthFrac = totalWidthFrac(numUpperCards);
    final upperStartX = 0.5 - upperWidthFrac / 2;
    for (int i = 0; i < numUpperCards; i++) {
      final left = (upperStartX + (cardOverlapWidthFrac * i)) * layout.displaySize.width;
      final top = upperRowHeightFracStart * layout.displaySize.height;
      rects[sortedCards[i]] = Rect.fromLTWH(left, top, cardWidth, cardHeight);
    }
    for (int i = 0; i < numLowerCards; i++) {
      final left = (upperStartX + (cardOverlapWidthFrac * (i + 0.5))) * layout.displaySize.width;
      final top = lowerRowHeightFracStart * layout.displaySize.height;
      rects[sortedCards[numUpperCards + i]] = Rect.fromLTWH(left, top, cardWidth, cardHeight);
    }
  }
  else {
    final startX = 0.5 - totalWidthFrac(sortedCards.length) / 2;
    for (int i = 0; i < sortedCards.length; i++) {
      final left = (startX + (cardOverlapWidthFrac * i)) * layout.displaySize.width;
      final top = lowerRowHeightFracStart * layout.displaySize.height;
      rects[sortedCards[i]] = Rect.fromLTWH(left, top, cardWidth, cardHeight);
    }
  }
  return rects;
}

Layout computeLayout(BuildContext context) {
  final ds = MediaQuery.of(context).size;
  return Layout()
    ..displaySize = ds
    ..edgePx = max(ds.width / 20, ds.height / 15)
  ;
}
