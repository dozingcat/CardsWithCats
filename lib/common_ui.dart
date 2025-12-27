import 'dart:collection';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'cards/card.dart';
import 'cards/trick.dart';
import 'common.dart';

enum AnimationMode {
  none,
  movingTrickCard,
  movingTrickToWinner,
}

enum AiMode {
  allAi,
  humanPlayer0,
}

const defaultCardAspectRatio = 521.0 / 726;

class Layout {
  late Size displaySize;
  late double playerHeight;
  late EdgeInsets padding;
  double cardAspectRatio = defaultCardAspectRatio;

  Rect cardArea() {
    final border = playerHeight * 0.9;
    return Rect.fromLTRB(border, border, displaySize.width - border, displaySize.height - border);
  }

  Size baseCardSize() {
    final ca = cardArea();
    return Size(ca.width * 0.4, ca.height * 0.4);
  }

  Rect trickCardAreaForPlayer(int playerIndex) {
    final ca = cardArea();
    final cs = baseCardSize();
    final centerXFrac = (playerIndex == 1)
        ? 0.25
        : (playerIndex == 3)
            ? 0.75
            : 0.5;
    final centerYFrac = (playerIndex == 0)
        ? 0.75
        : (playerIndex == 2)
            ? 0.25
            : 0.5;
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
            center: Offset(w + cardWidth / 2, h / 2), width: cardWidth, height: cardHeight);
      default:
        throw Exception("Bad player index: $playerIndex");
    }
  }

  double dialogScale() {
    return (displaySize.shortestSide / 350).clamp(1.0, 2.0);
  }
}

Rect centeredSubrectWithAspectRatio(Rect parentRect, double aspectRatio) {
  final parentAspect = parentRect.width / parentRect.height;
  if (parentAspect > aspectRatio) {
    // Parent is wider, move in from left and right.
    final subrectWidth = parentRect.height * aspectRatio;
    return Rect.fromCenter(center: parentRect.center, width: subrectWidth, height: parentRect.height);
  }
  else {
    // Parent is taller, move in from top and bottom.
    final subrectHeight = parentRect.width / aspectRatio;
    return Rect.fromCenter(center: parentRect.center, width: parentRect.width, height: subrectHeight);
  }
}

const defaultTrumpBackgroundColor = Color.fromARGB(255, 255, 215, 0);

class PositionedCard extends StatelessWidget {
  final Rect rect;
  final PlayingCard card;
  final double cardAspectRatio;
  final double dimming;
  final double rotation;
  final bool isTrump;
  final void Function(PlayingCard)? onCardClicked;
  final Color? backgroundColor;

  const PositionedCard({
    super.key,
    required this.rect,
    required this.card,
    this.cardAspectRatio = defaultCardAspectRatio,
    this.onCardClicked,
    this.dimming = 0.0,
    this.rotation = 0.0,
    this.isTrump = false,
    this.backgroundColor,
  });

  Color? cardBackgroundColor() {
    if (backgroundColor != null) {
      return backgroundColor;
    }
    if (isTrump) {
      return defaultTrumpBackgroundColor;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cardRect = centeredSubrectWithAspectRatio(rect, cardAspectRatio);

    final cardStack = <Widget>[];
    Color? bgColor = cardBackgroundColor();
    final cardImagePath = bgColor != null ?
        "assets/cards/transparent/${card.toString()}.webp" :
        "assets/cards/solid/${card.toString()}.webp";
    cardStack.add(Center(
        child: Image(
          image: AssetImage(cardImagePath),
        )));

    if (dimming > 0) {
      cardStack.add(Container(color: Color.fromRGBO(0, 0, 0, dimming)));
    }

    // The card images don't have an edge border so we draw it manually.
    // Width of 0 makes the border one physical pixel.
    double cornerRadius = cardRect.width * 0.05;
    cardStack.add(Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: const Color.fromRGBO(64, 64, 64, 1.0),
          width: 0,
        ),
        borderRadius: BorderRadius.circular(cornerRadius),
      ),
    ));

    return Positioned.fromRect(
        rect: cardRect,
        child: Transform.rotate(angle: rotation, child: GestureDetector(
            onTapDown: onCardClicked != null ? ((tap) => onCardClicked!(card)) : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(cornerRadius),
              child: Container(
                color: bgColor,
                child: Stack(children: cardStack)
              )
            ) )));
  }
}

String catImageForIndex(int index) => "assets/cats/cat${index + 1}.png";

class AiPlayerImage extends StatelessWidget {
  final Layout layout;
  final int playerIndex;
  final int? catImageIndex;

  const AiPlayerImage({
    super.key,
    required this.layout,
    required this.playerIndex,
    this.catImageIndex,
  });

  @override
  Widget build(BuildContext context) {
    final imageIndex = (catImageIndex != null) ? catImageIndex! : playerIndex;
    final imagePath = catImageForIndex(imageIndex);
    const imageAspectRatio = 156 / 112;
    final displaySize = layout.displaySize;
    final playerSize = layout.playerHeight;

    final rect = (() {
      switch (playerIndex) {
        case 0:
          return Rect.fromLTWH(0, displaySize.height - playerSize, displaySize.width, playerSize);
        case 1:
          return Rect.fromLTWH(1, 0, playerSize, displaySize.height);
        case 2:
          return Rect.fromLTWH(0, 1, displaySize.width, playerSize);
        case 3:
          return Rect.fromLTWH(
              displaySize.width - playerSize - 1, 0, playerSize, displaySize.height);
        default:
          return const Rect.fromLTWH(0, 0, 0, 0);
      }
    })();
    final angle = (playerIndex - 2) * pi / 2;
    final scale = (playerIndex == 1 || playerIndex == 3) ? imageAspectRatio : 1.0;

    return Positioned.fromRect(
      rect: rect,
      child: Container(
        color: Colors.transparent,
        width: rect.width,
        height: rect.height,
        // The image won't naturally take up the full width if rotated 90 degrees,
        // so in that case scale by the aspect ratio.
        child: Transform.scale(
            scale: scale,
            child: Transform.rotate(
              angle: angle,
              child: Image.asset(imagePath, fit: BoxFit.contain),
            )),
      ),
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
    super.key,
    required this.layout,
    required this.playerIndex,
    required this.message,
    this.widthFraction = 0.2,
  });

  @override
  Widget build(BuildContext context) {
    var transform = Matrix4.identity();
    final dh = layout.displaySize.height;
    final dw = layout.displaySize.width;
    final playerHeight = layout.playerHeight;
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
        child: Stack(
          children: [
            SizedBox(
              width: imageWidth,
              height: imageHeight,
              child: Transform(
                  alignment: Alignment.center,
                  transform: transform,
                  child: const Image(
                    image: AssetImage(imagePath),
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                  )),
            ),
            // Center the message in the content part of the bubble, which is
            // the upper ~73%. Except for player 2 where it's the lower 73%.
            Positioned(
                width: imageWidth,
                height: imageHeight * 0.73,
                top: (playerIndex == 2) ? 0.27 * imageHeight : 0,
                child: Center(child:
                  Text(message, style: TextStyle(fontSize: fontSize, height: 1)))
            ),
          ],
        ));
  }
}

enum Mood { happy, veryHappy, mad }

class MoodBubble extends StatelessWidget {
  final Layout layout;
  final int playerIndex;
  final Mood mood;
  final double widthFraction;
  static const bubbleImageAspectRatio = 619.0 / 640;
  static const moodImageHeightFraction = 0.42;
  static const bubbleImagePath = "assets/misc/thought_bubble.png";
  static const moodImagePathPrefix = "assets/cats/";

  const MoodBubble({
    Key? key,
    required this.layout,
    required this.playerIndex,
    required this.mood,
    this.widthFraction = 0.2,
  }) : super(key: key);

  String _moodImagePath() {
    switch (mood) {
      case Mood.happy:
        return moodImagePathPrefix + "emoji_happy_u1f63a.png";
      case Mood.veryHappy:
        return moodImagePathPrefix + "emoji_grin_u1f638.png";
      case Mood.mad:
        return moodImagePathPrefix + "emoji_mad_u1f63e.png";
    }
  }

  @override
  Widget build(BuildContext context) {
    var transform = Matrix4.identity();
    final dh = layout.displaySize.height;
    final dw = layout.displaySize.width;
    final playerHeight = layout.playerHeight;
    final imageWidth = min(playerHeight * 1.5, widthFraction * dw);
    final imageHeight = imageWidth / bubbleImageAspectRatio;
    var top = 0.0;
    var left = 0.0;
    var moodXFrac = 0.0;
    var moodYFrac = 0.0;
    final moodSize = imageHeight * moodImageHeightFraction;
    switch (playerIndex) {
      case 1:
        left = playerHeight / 2;
        top = dh / 2 - playerHeight * 1.6 / 2 - imageHeight;
        moodXFrac = 0.30;
        moodYFrac = 0.15;
        break;
      case 2:
        transform = Matrix4.rotationX(pi);
        left = dw / 2;
        top = playerHeight * 1.1;
        moodXFrac = 0.33;
        moodYFrac = 0.48;
        break;
      case 3:
        transform = Matrix4.rotationY(pi);
        left = dw - playerHeight / 2 - imageWidth;
        top = dh / 2 - playerHeight * 1.6 / 2 - imageHeight;
        moodXFrac = 0.30;
        moodYFrac = 0.15;
        break;
      case 0:
        left = dw / 2 - playerHeight / 2;
        top = dh - playerHeight - imageHeight;
        moodXFrac = 0.33;
        moodYFrac = 0.12;
        break;
    }

    return Positioned(
        top: top,
        left: left,
        width: imageWidth,
        height: imageHeight,
        child: Opacity(
            opacity: 0.8,
            child: Stack(
              children: [
                SizedBox(
                  width: imageWidth,
                  height: imageHeight,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: transform,
                    child: Image.asset(bubbleImagePath, fit: BoxFit.contain),
                  ),
                ),
                Positioned(
                  top: moodYFrac * imageHeight,
                  left: moodXFrac * imageWidth,
                  width: moodSize,
                  height: moodSize,
                  child: Image.asset(_moodImagePath(), fit: BoxFit.contain),
                ),
              ],
            )));
  }
}

class PlayerMoods extends StatelessWidget {
  final Layout layout;
  final Map<int, Mood> moods;

  const PlayerMoods({Key? key, required this.layout, required this.moods}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (moods.isEmpty) return Container();
    final nonHuman = moods.entries.where((elem) => elem.key != 0);
    final moodWidgets = Stack(children: [
      ...nonHuman.map((elem) => MoodBubble(
            layout: layout,
            playerIndex: elem.key,
            mood: elem.value,
          ))
    ]);

    return TweenAnimationBuilder(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1000),
      child: moodWidgets,
      builder: (context, double val, child) => Opacity(opacity: val, child: child),
    );
  }
}

class PlayerMessagesOverlay extends StatelessWidget {
  final Layout layout;
  final List<String> messages;

  const PlayerMessagesOverlay({Key? key, required this.layout, required this.messages})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget makeTextContainer(String msg, Offset offset) {
      return Transform.translate(
          offset: offset,
          child: Container(
              decoration: BoxDecoration(
                  color: const Color.fromARGB(208, 255, 255, 255),
                  border: Border.all(
                    color: const Color.fromARGB(128, 0, 0, 0),
                  ),
                  borderRadius: const BorderRadius.all(Radius.circular(20))),
              child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(msg,
                      style: const TextStyle(
                        color: Color.fromARGB(224, 0, 0, 0),
                        fontSize: 18,
                      )))));
    }

    const spacer = Expanded(child: SizedBox());
    // Get approximate height of the containers so we can position them accurately.
    final messageLineCounts = [...messages.map((m) => m.split("\n").length)];
    final approxContainerHeights = [...messageLineCounts.map((n) => 24 + 20 * n)];
    final p1Offset = Offset(0, layout.playerHeight * 0.75 + approxContainerHeights[1] / 2);
    final p3Offset = Offset(0, layout.playerHeight * 0.75 + approxContainerHeights[3] / 2);
    final overlays = Column(children: [
      Row(children: [
        spacer,
        makeTextContainer(messages[2], Offset(0, layout.playerHeight)),
        spacer,
      ]),
      Expanded(
          child: Row(children: [
        const SizedBox(width: 5),
        makeTextContainer(messages[1], p1Offset),
        spacer,
        makeTextContainer(messages[3], p3Offset),
        const SizedBox(width: 5),
      ])),
      Row(children: [
        spacer,
        makeTextContainer(messages[0], Offset(0, -layout.playerHeight / 2)),
        spacer,
      ]),
    ]);

    return TweenAnimationBuilder(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 250),
      child: overlays,
      builder: (BuildContext context, double opacity, Widget? child) {
        return Opacity(opacity: opacity, child: child);
      },
    );
  }
}

class DisplayedHand {
  int playerIndex;
  List<PlayingCard> cards;
  HandDisplayStyle displayStyle;

  DisplayedHand({
    required this.playerIndex,
    required this.cards,
    this.displayStyle = HandDisplayStyle.normal,
  });
}

class TrickCards extends StatelessWidget {
  final Layout layout;
  final TrickInProgress currentTrick;
  final List<Trick> previousTricks;
  final AnimationMode animationMode;
  final int numPlayers;
  final void Function() onTrickCardAnimationFinished;
  final void Function() onTrickToWinnerAnimationFinished;
  final List<DisplayedHand>? displayedHands;
  final List<Suit>? suitOrder;
  final Suit? trumpSuit;
  final Map<PlayingCard, Color>? cardBackgroundColors;

  const TrickCards({
    super.key,
    required this.layout,
    required this.currentTrick,
    required this.previousTricks,
    required this.animationMode,
    required this.numPlayers,
    required this.onTrickCardAnimationFinished,
    required this.onTrickToWinnerAnimationFinished,
    this.displayedHands,
    this.suitOrder,
    this.trumpSuit,
    this.cardBackgroundColors,
  });

  @override
  Widget build(BuildContext context) {
    if (animationMode == AnimationMode.movingTrickToWinner) {
      return _trickCardsAnimatingToWinner(layout, previousTricks.last);
    }
    List<Widget> cardWidgets = [];
    if (currentTrick.cards.isNotEmpty) {
      if (animationMode == AnimationMode.movingTrickCard) {
        cardWidgets.addAll(_trickCardsWithLastAnimating(
            layout, currentTrick.leader, numPlayers, currentTrick.cards));
      } else {
        cardWidgets
            .addAll(_staticTrickCards(layout, currentTrick.leader, numPlayers, currentTrick.cards));
      }
    } else if (previousTricks.isNotEmpty) {
      final trick = previousTricks.last;
      if (animationMode == AnimationMode.movingTrickCard) {
        cardWidgets
            .addAll(_trickCardsWithLastAnimating(layout, trick.leader, numPlayers, trick.cards));
      } else {
        // Finished animating trick to winner, don't show any cards.
      }
    }
    return Stack(children: cardWidgets);
  }

  Widget _trickCardForPlayer(final Layout layout, final PlayingCard card, int playerIndex) {
    final cardRect = layout.trickCardAreaForPlayer(playerIndex);
    return PositionedCard(
        rect: cardRect,
        card: card,
        isTrump: card.suit == trumpSuit,
        backgroundColor: cardBackgroundColors?[card],
    );
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
    List<DisplayedHand> matchingDisplayedHands = displayedHands != null ? displayedHands!.where((d) => d.playerIndex == animPlayer).toList() : [];
    if (matchingDisplayedHands.isNotEmpty) {
      final dh = matchingDisplayedHands[0];
      // We want to know where the card was drawn in the player's hand. It's not
      // there now, so we have to compute the card rects as if it were.
      final previousHandCards = [...dh.cards, cards.last];
      startRect =
          playerHandCardRects(layout, previousHandCards, suitOrder!, playerIndex: animPlayer, displayStyle: dh.displayStyle)[cards.last]!;
    }

    cardWidgets.add(TweenAnimationBuilder(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 200),
        onEnd: onTrickCardAnimationFinished,
        builder: (BuildContext context, double frac, Widget? child) {
          Rect animRect = Rect.lerp(startRect, endRect, frac)!;
          // Starting size for human player is determined by where the card was shown before.
          // For AI players make the card grow as it comes from their card origin.
          if (animPlayer != 0) {
            final scale = 0.25 + (0.75 * frac);
            animRect = Rect.fromCenter(center: animRect.center, width: startRect.width * scale, height: startRect.height * scale);
          }
          return PositionedCard(
              rect: animRect,
              card: cards.last,
              isTrump: cards.last.suit == trumpSuit,
              backgroundColor: cardBackgroundColors?[cards.last],
          );
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
            final scale = (t < 0) ? 1 : 1 - 0.75 * t;
            Rect animRect =
                Rect.fromCenter(center: center, width: endRect.width * scale, height: endRect.height * scale);
            cardWidgets.add(
                PositionedCard(
                    rect: animRect,
                    card: trick.cards[i],
                    isTrump: trick.cards[i].suit == trumpSuit,
                    backgroundColor: cardBackgroundColors?[trick.cards[i]],
                ));
          }
          return Stack(children: cardWidgets);
        });
  }
}

class GameTypeDropdown extends StatelessWidget {
  final GameType gameType;
  final Function(GameType?) onChanged;
  final TextStyle textStyle;

  const GameTypeDropdown({
    super.key,
    required this.gameType,
    required this.onChanged,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton(
      value: gameType,
      items: [
        DropdownMenuItem(value: GameType.hearts, child: Text('Hearts', style: textStyle)),
        DropdownMenuItem(value: GameType.spades, child: Text('Spades', style: textStyle)),
        DropdownMenuItem(value: GameType.ohHell, child: Text('Oh Hell', style: textStyle)),
        // Bridge isn't enabled for release yet.
        // DropdownMenuItem(value: GameType.bridge, child: Text('Bridge', style: textStyle)),
      ],
      onChanged: onChanged,
    );
  }
}

Widget paddingAll(final double paddingPx, final Widget child) {
  return Padding(padding: EdgeInsets.all(paddingPx), child: child);
}

Widget paddingHorizontal(final double paddingPx, final Widget child) {
  return Padding(padding: EdgeInsets.only(left: paddingPx, right: paddingPx), child: child);
}

class ClaimRemainingTricksDialog extends StatelessWidget {
  final Function() onOk;
  final bool isHuman;
  final int? catImageIndex;

  const ClaimRemainingTricksDialog({
    super.key,
    required this.onOk,
    this.isHuman = false,
    this.catImageIndex,
  });

  @override
  Widget build(BuildContext context) {
    Layout layout = computeLayout(context);
    const dialogBackgroundColor = Color.fromARGB(0x80, 0xd8, 0xd8, 0xd8);

    final dialog = Center(
        child: Transform.scale(scale: layout.dialogScale(), child: Dialog(
          insetPadding: EdgeInsets.zero,
          backgroundColor: dialogBackgroundColor,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            paddingAll(15, Text("Remaining tricks claimed")),
            paddingAll(
                15,
                ElevatedButton(
                  onPressed: onOk,
                  child: const Text("OK"),
                )),
          ])
        ))
    );

    return dialog;
  }
}

enum HandDisplayStyle {
  normal,
  dummy,
}

class PlayerHandCards extends StatelessWidget {
  final Layout layout;
  final List<Suit> suitDisplayOrder;
  final List<PlayingCard> cards;
  final Iterable<PlayingCard> highlightedCards;
  final void Function(PlayingCard)? onCardClicked;
  final List<PlayingCard>? animateFromCards;
  final Suit? trumpSuit;
  final Map<PlayingCard, Color>? cardBackgroundColors;
  final int playerIndex;
  final HandDisplayStyle displayStyle;
  final double scaleMultiplier;

  const PlayerHandCards({
    super.key,
    required this.layout,
    required this.suitDisplayOrder,
    required this.cards,
    required this.highlightedCards,
    this.animateFromCards,
    this.trumpSuit,
    this.cardBackgroundColors,
    this.onCardClicked,
    this.playerIndex = 0,
    this.displayStyle = HandDisplayStyle.normal,
    this.scaleMultiplier = 1,
  });

  @override
  Widget build(BuildContext context) {
    final rects = playerHandCardRects(layout, cards, suitDisplayOrder, playerIndex: playerIndex, displayStyle: displayStyle, scaleMultiplier: scaleMultiplier);

    double rotation = (playerIndex == 1)
        ? pi / 2
        : (playerIndex == 3)
        ? -pi / 2
        : 0;

    if (animateFromCards != null) {
      final previousRects = playerHandCardRects(layout, animateFromCards!, suitDisplayOrder, playerIndex: playerIndex, displayStyle: displayStyle, scaleMultiplier: scaleMultiplier);
      return TweenAnimationBuilder(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 200),
          builder: (BuildContext context, double fraction, Widget? child) {
            final List<Widget> cardImages = [];
            for (final entry in rects.entries) {
              final card = entry.key;
              final startRect = previousRects[card]!;
              final endRect = entry.value;
              cardImages.add(PositionedCard(
                rect: Rect.lerp(startRect, endRect, fraction)!,
                card: card,
                isTrump: card.suit == trumpSuit,
                dimming: highlightedCards.contains(card) ? 0.0 : 0.5,
                onCardClicked: onCardClicked,
                rotation: rotation,
                backgroundColor: cardBackgroundColors?[card],
              ));
            }
            return Stack(children: cardImages);
          });
    }

    final List<Widget> cardImages = [];
    for (final entry in rects.entries) {
      final card = entry.key;
      cardImages.add(PositionedCard(
        rect: entry.value,
        card: card,
        isTrump: card.suit == trumpSuit,
        dimming: highlightedCards.contains(card) ? 0.0 : 0.5,
        onCardClicked: onCardClicked,
        rotation: rotation,
        backgroundColor: cardBackgroundColors?[card],
      ));
    }
    print("PlayerHandCards backgrounds: $cardBackgroundColors");
    return Stack(children: cardImages);
  }
}

class PlayerHandParams {
  final Key? key;
  final int playerIndex;
  final List<PlayingCard> cards;
  final Iterable<PlayingCard> highlightedCards;
  final void Function(PlayingCard)? onCardClicked;
  final List<PlayingCard>? animateFromCards;
  final HandDisplayStyle displayStyle;

  PlayerHandParams({
    this.key,
    required this.playerIndex,
    required this.cards,
    required this.highlightedCards,
    this.animateFromCards,
    this.onCardClicked,
    this.displayStyle = HandDisplayStyle.normal,
  });
}

class MultiplePlayerHandCards extends StatelessWidget {
  final Layout layout;
  final List<PlayerHandParams> playerHands;
  final List<Suit> suitOrder;
  final Suit? trumpSuit;
  final Map<PlayingCard, Color>? cardBackgroundColors;

  const MultiplePlayerHandCards({
    super.key,
    required this.layout,
    required this.playerHands,
    required this.suitOrder,
    this.trumpSuit,
    this.cardBackgroundColors,
  });

  static bool anyRectsIntersect(List<Rect> rects1, List<Rect> rects2) {
    for (final r1 in rects1) {
      for (final r2 in rects2) {
        if (!r1.intersect(r2).isEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  bool hasCardIntersectionAtScaleMultiplier(double scaleMultiplier) {
    if (playerHands.length <= 1) {
      return false;
    }
    List<List<Rect>> perPlayerRects = [];
    // Slightly expand the rects when checking for intersections so that
    // the cards won't go right up to each other's edges.
    // HACK: Swap width/height for sideways cards since they'll be rotated when drawn.
    const bufferScale = 1.03;
    for (final ph in playerHands) {
      final rects = playerHandCardRects(
        layout, ph.cards, suitOrder,
        playerIndex: ph.playerIndex,
        displayStyle: ph.displayStyle,
        scaleMultiplier: scaleMultiplier,
      ).values.toList(growable: false);
      if (ph.playerIndex == 1 || ph.playerIndex == 3) {
        for (int i = 0; i < rects.length; i++) {
          rects[i] = Rect.fromCenter(center: rects[i].center, width: rects[i].height * bufferScale, height: rects[i].width * bufferScale);
        }
      }
      else {
        for (int i = 0; i < rects.length; i++) {
          rects[i] = Rect.fromCenter(center: rects[i].center, width: rects[i].width * bufferScale, height: rects[i].height * bufferScale);
        }
      }
      perPlayerRects.add(rects);
    }

    // O(N**4) but hopefully ok.
    for (int i = 1; i < perPlayerRects.length; i++) {
      for (int j = 0; j < i; j++) {
        if (anyRectsIntersect(perPlayerRects[i], perPlayerRects[j])) {
          return true;
        }
      }
    }
    return false;
  }

  double computeBestScaleMultiplier() {
    // Get all the card rects and see if any rect for player A intersects
    // a rect for player B. If so, adjust scaleMultiplier until there are
    // no more intersections.
    if (!hasCardIntersectionAtScaleMultiplier(1)) {
      return 1;
    }
    double min = 0;
    double max = 1;
    double current = 0.5;
    double best = 0;
    const nIters = 8;
    for (int i = 0; i < nIters; i++) {
      current = (min + max) / 2.0;
      if (hasCardIntersectionAtScaleMultiplier(current)) {
        // Too big, need to reduce scale.
        max = current;
      }
      else {
        best = current;
        min = current;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final scaleMultiplier = computeBestScaleMultiplier();

    return Stack(children: [
      ...playerHands.map((ph) => PlayerHandCards(
        key: ph.key,
        layout: layout,
        playerIndex: ph.playerIndex,
        cards: ph.cards,
        highlightedCards: ph.highlightedCards,
        suitDisplayOrder: suitOrder,
        animateFromCards: ph.animateFromCards,
        trumpSuit: trumpSuit,
        cardBackgroundColors: cardBackgroundColors,
        onCardClicked: ph.onCardClicked,
        displayStyle: ph.displayStyle,
        scaleMultiplier: scaleMultiplier,
      ))
    ]);
  }
}

LinkedHashMap<PlayingCard, Rect> _playerHandCardRectsForTopOrBottom(
    Layout layout,
    List<PlayingCard> cards,
    List<Suit> suitOrder,
    {required int playerIndex, double scaleMultiplier = 1}
) {
  if (!(playerIndex == 0 || playerIndex == 2)) {
    throw Exception("invalid playerIndex: $playerIndex");
  }
  final rects = LinkedHashMap<PlayingCard, Rect>();
  const cardHeightFrac = 0.2;
  const cardOverlapFraction = 1.0 / 3;
  const upperRowHeightFracStart = 0.69;
  const lowerRowHeightFracStart = 0.79;
  const singleRowHeightFracStart = 0.74;
  final ds = layout.displaySize;
  final cardHeight = ds.height * cardHeightFrac;
  final cardWidth = cardHeight * layout.cardAspectRatio;
  final pxBetweenCards = cardWidth * (1 - cardOverlapFraction);
  final maxAllowedTotalWidth = 0.95 * ds.width;

  double widthOfNCards(int n) => cardWidth + (n - 1) * pxBetweenCards;

  List<PlayingCard> sortedCards = [];
  for (Suit suit in suitOrder) {
    sortedCards.addAll(sortedCardsInSuit(cards, suit));
  }
  final oneRowWidth = widthOfNCards(sortedCards.length);
  if (oneRowWidth < maxAllowedTotalWidth) {
    final scaledRowWidth = oneRowWidth * scaleMultiplier;
    final scaledCardWidth = cardWidth * scaleMultiplier;
    final scaledCardHeight = cardHeight * scaleMultiplier;
    // Show all cards in a single row.
    var startX = (ds.width - scaledRowWidth) / 2;
    var startY = singleRowHeightFracStart * ds.height;
    if (playerIndex == 2) {
      startY = layout.playerHeight;
    }
    for (int i = 0; i < sortedCards.length; i++) {
      final x = startX + i * pxBetweenCards * scaleMultiplier;
      final r = Rect.fromLTWH(x, startY, scaledCardWidth, scaledCardHeight);
      rects[sortedCards[i]] = r;
    }
    return rects;
  }
  final numUpperCards = sortedCards.length ~/ 2;
  final numLowerCards = sortedCards.length - numUpperCards;
  double twoRowWidth = widthOfNCards(numLowerCards);
  // Lower row is offset by half of cardOverlapFraction, so if it has the same
  // number of cards as the top row it extends the total width.
  if (numUpperCards == numLowerCards) {
    twoRowWidth += pxBetweenCards / 2;
  }
  final upperStartX = (ds.width - twoRowWidth) / 2;
  final lowerStartX = upperStartX + pxBetweenCards / 2;
  final scale = min(1.0, maxAllowedTotalWidth / twoRowWidth) * scaleMultiplier;
  final scaledCardWidth = scale * cardWidth;
  final scaledCardHeight = scale * cardHeight;
  var upperStartY = upperRowHeightFracStart * ds.height + (cardHeight - scaledCardHeight);
  var lowerStartY = lowerRowHeightFracStart * ds.height + (cardHeight - scaledCardHeight) / 2;
  if (playerIndex == 2) {
    double diff = lowerStartY - upperStartY;
    upperStartY = layout.playerHeight; // .height - (lowerStartY + scaledCardHeight);
    lowerStartY = upperStartY + diff;
  }
  final midX = ds.width / 2;
  for (int i = 0; i < numLowerCards; i++) {
    double baseLeft = upperStartX + i * pxBetweenCards;
    double scaledLeft = midX + (baseLeft - midX) * scale;
    // adjust Y for scale?
    final r = Rect.fromLTWH(scaledLeft, upperStartY, scaledCardWidth, scaledCardHeight);
    rects[sortedCards[i]] = r;
  }
  for (int i = 0; i < numUpperCards; i++) {
    double baseLeft = lowerStartX + i * pxBetweenCards;
    double scaledLeft = midX + (baseLeft - midX) * scale;
    // adjust Y for scale?
    final r = Rect.fromLTWH(scaledLeft, lowerStartY, scaledCardWidth, scaledCardHeight);
    rects[sortedCards[numLowerCards + i]] = r;
  }
  return rects;
}

LinkedHashMap<PlayingCard, Rect> _playerHandCardRectsForLeftOrRight(
    Layout layout,
    List<PlayingCard> cards,
    List<Suit> suitOrder,
    {required int playerIndex, double scaleMultiplier = 1.0}
    ) {
  if (!(playerIndex == 1 || playerIndex == 3)) {
    throw Exception("invalid playerIndex: $playerIndex");
  }
  List<PlayingCard> sortedCards = [];
  for (Suit suit in suitOrder) {
    sortedCards.addAll(sortedCardsInSuit(cards, suit));
  }

  final rects = LinkedHashMap<PlayingCard, Rect>();
  final ds = layout.displaySize;

  final preferredCardWidth = 0.2 * ds.height;
  final preferredCardHeight = preferredCardWidth * layout.cardAspectRatio;

  final availableHeight = 0.6 * ds.height;
  final availableWidth = 0.4 * ds.width;

  const cardOverlapFraction = 0.4;
  final preferredTotalHeight = (1 + (cards.length - 1) * cardOverlapFraction) * preferredCardHeight;

  double scale = 1.0;
  scale = min(scale, availableWidth / preferredCardWidth);
  scale = min(scale, availableHeight / preferredTotalHeight);
  scale *= scaleMultiplier;

  final actualCardWidth = scale * preferredCardWidth;
  final actualCardHeight = scale * preferredCardHeight;

  // final xCenter = 0.05 * ds.width + actualCardWidth / 2;
  final xCenter = layout.playerHeight + actualCardWidth / 2;
  final yDistanceBetweenCenters = cardOverlapFraction * actualCardHeight;

  if (playerIndex == 1) {
    // Left side, start at bottom and go up.
    final yCenterStart = ds.height / 2 + (sortedCards.length - 1) * yDistanceBetweenCenters / 2;
    for (int i = 0; i < sortedCards.length; i++) {
      final yCenter = yCenterStart - i * yDistanceBetweenCenters;
      // Because the card images get rotated 90 degrees, we need to swap width and height.
      Rect r = Rect.fromCenter(center: Offset(xCenter, yCenter), width: actualCardHeight, height: actualCardWidth);
      rects[sortedCards[i]] = r;
    }
  }
  else {
    // Right side, start at top and go down.
    final yCenterStart = ds.height / 2 - (sortedCards.length - 1) * yDistanceBetweenCenters / 2;
    for (int i = 0; i < sortedCards.length; i++) {
      final yCenter = yCenterStart + i * yDistanceBetweenCenters;
      Rect r = Rect.fromCenter(center: Offset(ds.width - xCenter, yCenter), width: actualCardHeight, height: actualCardWidth);
      rects[sortedCards[i]] = r;
    }
  }

  return rects;
}

LinkedHashMap<PlayingCard, Rect> _dummyCardRects({
  required Layout layout,
  required List<PlayingCard> cards,
  required List<Suit> suitOrder,
  required int playerIndex,
  double scaleMultiplier = 1,
}) {
  final rects = LinkedHashMap<PlayingCard, Rect>();
  if (cards.isEmpty) {
    return rects;
  }

  const preferredCardHeightFraction = 0.2;
  const cardOverlapFraction = 0.25;
  const cardColumnGapFraction = 0.1;

  final ds = layout.displaySize;
  final preferredCardHeight = ds.height * preferredCardHeightFraction;
  final preferredCardWidth = preferredCardHeight * layout.cardAspectRatio;

  List<List<PlayingCard>> cardsBySuit = [];
  int numCardsInLongestSuit = 0;
  for (final suit in suitOrder) {
    cardsBySuit.add(sortedCardsInSuit(cards, suit));
    if (cardsBySuit.last.length > numCardsInLongestSuit) {
      numCardsInLongestSuit = cardsBySuit.last.length;
    }
  }

  if (playerIndex == 0 || playerIndex == 2) {
    // 4 columns, 3 gaps.
    final requiredWidth = (4 + 3 * cardColumnGapFraction) * preferredCardWidth;
    final requiredHeight = (1 + ((numCardsInLongestSuit - 1) * cardOverlapFraction)) * preferredCardHeight;
    final availableWidth = ds.width * 0.95;
    final availableHeight = ds.height * 0.6;

    double scale = 1.0;
    scale = min(scale, availableWidth / requiredWidth);
    scale = min(scale, availableHeight / requiredHeight);
    scale *= scaleMultiplier;
    final actualCardWidth = preferredCardWidth * scale;
    final actualCardHeight = preferredCardHeight * scale;
    final actualOverlap = cardOverlapFraction * actualCardHeight;
    final actualGap = cardColumnGapFraction * actualCardWidth;

    final cx = ds.width / 2;
    final xCenters = [
      cx - 1.5 * actualCardWidth - 1.5 * actualGap,
      cx - 0.5 * actualCardWidth - 0.5 * actualGap,
      cx + 0.5 * actualCardWidth + 0.5 * actualGap,
      cx + 1.5 * actualCardWidth + 1.5 * actualGap,
    ];

    final firstYCenter = (playerIndex == 0)
        ? 0.975 * ds.height - actualCardHeight / 2
        : 0.025 * ds.height + actualCardHeight / 2;
    final centerYDelta = (playerIndex == 0) ? -actualOverlap : actualOverlap;

    for (int i = 0; i < 4; i++) {
      final cardsInColumn = cardsBySuit[i];
      for (int j = 0; j < cardsInColumn.length; j++) {
        final center = Offset(xCenters[i], firstYCenter + j * centerYDelta);
        Rect rect = Rect.fromCenter(center: center, width: actualCardWidth, height: actualCardHeight);
        rects[cardsInColumn[j]] = rect;
      }
    }
  }
  else {
    assert(playerIndex == 1 || playerIndex == 3);
    final availableHeight = ds.height * 0.5;
    final availableWidth = ds.width * 0.5;
    // Rotated, so card "width" and column gap are the height.
    final requiredHeight = (4 + 3 * cardColumnGapFraction) * preferredCardWidth;
    final requiredWidth = (1 + ((numCardsInLongestSuit - 1) * cardOverlapFraction)) * preferredCardHeight;

    double scale = 1.0;
    scale = min(scale, availableWidth / requiredWidth);
    scale = min(scale, availableHeight / requiredHeight);
    scale *= scaleMultiplier;
    final actualCardWidth = preferredCardWidth * scale;
    final actualCardHeight = preferredCardHeight * scale;
    final actualOverlap = cardOverlapFraction * actualCardHeight;
    final actualGap = cardColumnGapFraction * actualCardWidth;

    final firstXCenter = (playerIndex == 1)
        ? 0.025 * ds.width + actualCardHeight / 2
        : 0.975 * ds.width - actualCardHeight / 2;
    final cy = ds.height * 0.4;
    final yDir = (playerIndex == 1) ? -1 : 1;
    final yCenters = [
      cy - yDir * (1.5 * actualCardWidth + 1.5 * actualGap),
      cy - yDir * (0.5 * actualCardWidth + 0.5 * actualGap),
      cy + yDir * (0.5 * actualCardWidth + 0.5 * actualGap),
      cy + yDir * (1.5 * actualCardWidth + 1.5 * actualGap),
    ];
    final centerXDelta = (playerIndex == 1) ? actualOverlap : -actualOverlap;

    for (int i = 0; i < 4; i++) {
      final cardsInColumn = cardsBySuit[i];
      for (int j = 0; j < cardsInColumn.length; j++) {
        final center = Offset(firstXCenter + j * centerXDelta, yCenters[i]);
        Rect rect = Rect.fromCenter(center: center, width: actualCardWidth, height: actualCardHeight);
        rects[cardsInColumn[j]] = rect;
      }
    }
  }

  return rects;
}

LinkedHashMap<PlayingCard, Rect> _normalCardRects(
    Layout layout,
    List<PlayingCard> cards,
    List<Suit> suitOrder,
    {int playerIndex = 0, double scaleMultiplier = 1}
) {
  if (playerIndex == 0 || playerIndex == 2) {
    return _playerHandCardRectsForTopOrBottom(layout, cards, suitOrder, playerIndex: playerIndex, scaleMultiplier: scaleMultiplier);
  }
  else {
    return _playerHandCardRectsForLeftOrRight(layout, cards, suitOrder, playerIndex: playerIndex, scaleMultiplier: scaleMultiplier);
  }
  throw Exception();
}

LinkedHashMap<PlayingCard, Rect> playerHandCardRects(
    Layout layout,
    List<PlayingCard> cards,
    List<Suit> suitOrder,
    {int playerIndex = 0, HandDisplayStyle displayStyle = HandDisplayStyle.normal, scaleMultiplier = 1.0}) {
  return switch (displayStyle) {
    HandDisplayStyle.dummy => _dummyCardRects(layout: layout, cards: cards, suitOrder: suitOrder, playerIndex: playerIndex, scaleMultiplier: scaleMultiplier),
    HandDisplayStyle.normal => _normalCardRects(layout, cards, suitOrder, playerIndex: playerIndex, scaleMultiplier: scaleMultiplier),
  };
}

Layout computeLayout(BuildContext context) {
  final baseSize = MediaQuery.sizeOf(context);
  // paddingOf returns the padding needed to avoid display cutouts.
  final padding = MediaQuery.paddingOf(context);
  final adjustedSize = Size(
      baseSize.width - padding.left - padding.right,
      baseSize.height - padding.top - padding.bottom);

  return Layout()
    ..displaySize = adjustedSize
    ..playerHeight = adjustedSize.shortestSide * 0.125
    ..padding = padding
    ;
}
