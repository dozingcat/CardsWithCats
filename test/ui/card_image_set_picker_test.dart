import 'package:cards_with_cats/card_images.dart';
import 'package:cards_with_cats/common_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const customSet = CardImageSet("custom_1", "My Cards", CardImageSource.filesystem, "/nonexistent", 0.7);
  final imageSets = [...cardImageSets, customSet];

  Future<void> pumpPicker(WidgetTester tester, {
    required CardImageSet selected,
    void Function(CardImageSet)? onSelected,
    void Function(CardImageSet)? onDelete,
    List<(String, void Function())> addActions = const [],
  }) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 350, child: CardImageSetPicker(
      imageSets: imageSets,
      selectedSet: selected,
      onSelected: onSelected ?? (_) {},
      onDelete: onDelete,
      addActions: addActions,
      addHelpText: "Help text",
      previewVariant: solidCardImageVariant,
    )))));
  }

  Future<void> expand(WidgetTester tester) async {
    await tester.tap(find.text("Change"));
    await tester.pump();
  }

  testWidgets('shows label and sample cards until expanded', (tester) async {
    await pumpPicker(tester, selected: cardImageSets[1], addActions: [("Choose file...", () {})]);
    expect(find.text("Cards"), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(CardImageSetPicker.sampleCards.length));
    for (final s in imageSets) {
      expect(find.text(s.displayName), findsNothing);
    }
    expect(find.text("Add..."), findsNothing);

    await expand(tester);
    for (final s in imageSets) {
      expect(find.text(s.displayName), findsOneWidget);
    }
    expect(find.byType(Image), findsNWidgets(CardImageSetPicker.sampleCards.length * imageSets.length));
    expect(find.text("Add..."), findsOneWidget);

    await tester.tap(find.text("Done"));
    await tester.pump();
    expect(find.text("Default"), findsNothing);
  });

  testWidgets('shows sets in two columns', (tester) async {
    await pumpPicker(tester, selected: cardImageSets[0]);
    await expand(tester);
    final y0 = tester.getCenter(find.text(imageSets[0].displayName)).dy;
    final y1 = tester.getCenter(find.text(imageSets[1].displayName)).dy;
    final y2 = tester.getCenter(find.text(imageSets[2].displayName)).dy;
    expect(y1, y0);
    expect(y2, greaterThan(y0));
    expect(tester.getCenter(find.text(imageSets[1].displayName)).dx,
        greaterThan(tester.getCenter(find.text(imageSets[0].displayName)).dx));
  });

  testWidgets('selecting a set calls onSelected and stays expanded', (tester) async {
    CardImageSet? selected;
    await pumpPicker(tester, selected: cardImageSets[0], onSelected: (s) => selected = s);
    await expand(tester);
    await tester.tap(find.text("Original"));
    await tester.pump();
    expect(selected?.name, "original");
    expect(find.text("Done"), findsOneWidget);
  });

  test('cardImageSetForName falls back to the first set', () {
    expect(cardImageSetForName("original", imageSets).name, "original");
    expect(cardImageSetForName("missing", imageSets).name, "default");
    expect(cardImageSetForName(null, imageSets).name, "default");
  });

  testWidgets('delete button is only shown for filesystem sets', (tester) async {
    CardImageSet? deleted;
    await pumpPicker(tester, selected: cardImageSets[0], onDelete: (s) => deleted = s);
    await expand(tester);
    expect(find.byTooltip("Delete"), findsOneWidget);
    await tester.tap(find.byTooltip("Delete"));
    expect(deleted?.name, "custom_1");
  });

  testWidgets('add shows help text before choosing a file', (tester) async {
    var chosen = "";
    await pumpPicker(tester, selected: cardImageSets[0], addActions: [
      ("Choose zip file...", () => chosen = "zip"),
      ("Choose folder...", () => chosen = "folder"),
    ]);
    await expand(tester);
    expect(find.text("Help text"), findsNothing);
    await tester.tap(find.text("Add..."));
    await tester.pump();
    expect(find.text("Help text"), findsOneWidget);
    expect(chosen, "");

    await tester.tap(find.text("Cancel"));
    await tester.pump();
    expect(find.text("Help text"), findsNothing);
    expect(chosen, "");

    await tester.tap(find.text("Add..."));
    await tester.pump();
    await tester.tap(find.text("Choose folder..."));
    await tester.pump();
    expect(chosen, "folder");
    expect(find.text("Help text"), findsNothing);
  });

  testWidgets('no add button without add actions', (tester) async {
    await pumpPicker(tester, selected: cardImageSets[0]);
    await expand(tester);
    expect(find.text("Add..."), findsNothing);
  });
}
