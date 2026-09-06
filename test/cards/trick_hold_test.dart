import 'package:cards_with_cats/cards/card.dart';
import 'package:cards_with_cats/cards/trick.dart';
import 'package:cards_with_cats/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives `TrickCards` through the same state machine the game screens use,
/// so the tests below exercise the real transitions rather than a stand-in.
class _TrickHarness extends StatefulWidget {
  final TrickInProgress currentTrick;
  final List<Trick> previousTricks;
  final void Function(AnimationMode)? onModeChanged;

  const _TrickHarness({
    required this.currentTrick,
    required this.previousTricks,
    this.onModeChanged,
  });

  @override
  State<_TrickHarness> createState() => _TrickHarnessState();
}

class _TrickHarnessState extends State<_TrickHarness> {
  AnimationMode mode = AnimationMode.movingTrickCard;

  void _setMode(AnimationMode m) {
    setState(() => mode = m);
    widget.onModeChanged?.call(m);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      TrickCards(
        layout: computeLayout(context),
        currentTrick: widget.currentTrick,
        previousTricks: widget.previousTricks,
        animationMode: mode,
        numPlayers: 4,
        onTrickCardAnimationFinished: () =>
            _setMode(AnimationMode.holdingCompletedTrick),
        onTrickHoldFinished: () => _setMode(AnimationMode.movingTrickToWinner),
        onTrickToWinnerAnimationFinished: () => _setMode(AnimationMode.none),
      ),
    ]);
  }
}

void main() {
  final trickCards = PlayingCard.cardsFromString("2C 5C AC 9C");
  // Player 2 wins with the ace: the play that closes the trick.
  final finishedTrick = Trick(0, trickCards, 2);

  Widget harness({void Function(AnimationMode)? onModeChanged}) => MaterialApp(
        home: Scaffold(
          body: _TrickHarness(
            currentTrick: TrickInProgress(0, const []),
            previousTricks: [finishedTrick],
            onModeChanged: onModeChanged,
          ),
        ),
      );

  testWidgets("the card that closes a trick stays on the table during the hold",
      (tester) async {
    final modes = <AnimationMode>[];
    await tester.pumpWidget(harness(onModeChanged: modes.add));

    // The closing card animates into place first (issue #14: it must render at
    // all before anything is swept away).
    await tester.pump(const Duration(milliseconds: 250));
    expect(modes, contains(AnimationMode.holdingCompletedTrick));
    expect(find.byType(PositionedCard), findsNWidgets(4));

    // Most of the way through the hold every card is still face up and none of
    // them has started moving to the winner.
    await tester.pump(defaultTrickHoldDuration * 0.8);
    expect(modes.last, AnimationMode.holdingCompletedTrick);
    expect(find.byType(PositionedCard), findsNWidgets(4));

    // Only after the full hold does the trick move to the winner and clear.
    await tester.pump(defaultTrickHoldDuration);
    expect(modes.last, AnimationMode.movingTrickToWinner);
    await tester.pump(trickToWinnerDuration * 2);
    expect(modes.last, AnimationMode.none);
    expect(find.byType(PositionedCard), findsNothing);
  });
}
