import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cards_with_cats/card_images.dart';
import 'package:cards_with_cats/common_ui.dart';
import 'package:cards_with_cats/custom_card_images.dart';
import 'package:cards_with_cats/transparent_card_images.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  group('makeTransparentCardImage', () {
    List<num> convertPixel(int r, int g, int b, [int a = 255]) {
      final src = img.Image(width: 1, height: 1, numChannels: 4)..setPixelRgba(0, 0, r, g, b, a);
      final px = makeTransparentCardImage(src).getPixel(0, 0);
      return [px.r, px.g, px.b, px.a];
    }

    test('white becomes transparent', () {
      expect(convertPixel(255, 255, 255)[3], 1);
    });

    test('black is unchanged', () {
      expect(convertPixel(0, 0, 0), [0, 0, 0, 255]);
    });

    test('colors are separated into color and alpha', () {
      // Examples from scripts/make_transparent_cards.py.
      expect(convertPixel(255, 128, 128), [255, 0, 0, 127]);
      expect(convertPixel(255, 128, 64), [255, 85, 0, 191]);
    });

    test('fully transparent pixels are unchanged', () {
      expect(convertPixel(10, 20, 30, 0), [10, 20, 30, 0]);
    });

    test('works with RGB images', () {
      final src = img.Image(width: 2, height: 1)
        ..setPixelRgb(0, 0, 255, 255, 255)
        ..setPixelRgb(1, 0, 255, 0, 0);
      final dst = makeTransparentCardImage(src);
      expect(dst.getPixel(0, 0).a, 1);
      final red = dst.getPixel(1, 0);
      expect([red.r, red.g, red.b, red.a], [255, 0, 0, 255]);
    });
  });

  group('import', () {
    late Directory tmp;
    late Directory sourceDir;
    late Directory baseDir;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('card_images_test');
      sourceDir = Directory(p.join(tmp.path, 'My Cards'))..createSync();
      baseDir = Directory(p.join(tmp.path, 'card_images'));
    });

    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    const suits = ['C', 'D', 'H', 'S'];
    const ranks = ['2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A'];

    void writeCards({Set<String> skip = const {}}) {
      final image = img.Image(width: 50, height: 70)..clear(img.ColorRgb8(255, 0, 0));
      int i = 0;
      for (final s in suits) {
        for (final r in ranks) {
          final card = '$r$s';
          if (skip.contains(card)) continue;
          // Use a mix of formats and filename cases.
          final path = p.join(sourceDir.path, switch (i++ % 3) {
            0 => '$card.png',
            1 => '${card.toLowerCase()}.jpg',
            _ => '$card.webp',
          });
          final bytes = switch (p.extension(path)) {
            '.png' => img.encodePng(image),
            '.jpg' => img.encodeJpg(image),
            _ => img.encodeWebP(image),
          };
          File(path).writeAsBytesSync(bytes);
        }
      }
    }

    test('imports and reloads', () async {
      writeCards();
      final imageSet = await importCardImageSet(sourceDir: sourceDir.path, baseDir: baseDir, variants: cardImageVariants);
      expect(imageSet.displayName, 'My Cards');
      expect(imageSet.source, CardImageSource.filesystem);
      expect(imageSet.aspectRatio, closeTo(50 / 70, 1e-9));
      for (final s in suits) {
        for (final r in ranks) {
          for (final kind in ['solid', 'transparent']) {
            final f = File(p.join(imageSet.basePath, kind, '$r$s.webp'));
            expect(f.existsSync(), true, reason: f.path);
            final decoded = img.decodeWebP(f.readAsBytesSync())!;
            expect([decoded.width, decoded.height], [50, 70]);
          }
        }
      }

      final loaded = await loadCustomCardImageSets(baseDir);
      expect(loaded.length, 1);
      expect(loaded[0].name, imageSet.name);
      expect(loaded[0].displayName, 'My Cards');
      expect(loaded[0].basePath, imageSet.basePath);
      expect(loaded[0].aspectRatio, closeTo(50 / 70, 1e-9));

      await deleteCustomCardImageSet(loaded[0]);
      expect(await loadCustomCardImageSets(baseDir), isEmpty);
    });

    test('fails if cards are missing', () async {
      writeCards(skip: {'QS', '2H'});
      await expectLater(
          importCardImageSet(sourceDir: sourceDir.path, baseDir: baseDir, variants: cardImageVariants),
          throwsA(isA<CardImageImportException>().having(
              (e) => e.message, 'message', contains('2 cards: 2H, QS'))));
      expect(baseDir.existsSync() ? baseDir.listSync() : [], isEmpty);
    });

    test('fails on unreadable image', () async {
      writeCards();
      File(p.join(sourceDir.path, 'AS.webp')).writeAsStringSync('not an image');
      await expectLater(
          importCardImageSet(sourceDir: sourceDir.path, baseDir: baseDir, variants: cardImageVariants),
          throwsA(isA<CardImageImportException>()));
      expect(baseDir.listSync(), isEmpty);
    });

    test('ignores and removes incomplete imports', () async {
      final tmpImport = Directory(p.join(baseDir.path, 'custom_123.tmp'))..createSync(recursive: true);
      File(p.join(tmpImport.path, 'info.json')).writeAsStringSync('{"displayName": "x", "aspectRatio": 0.7}');
      expect(await loadCustomCardImageSets(baseDir), isEmpty);
      expect(tmpImport.existsSync(), false);
    });

    // Creates a zip file with an image for each card, with optional path prefix and
    // extra entries. Returns the path of the zip file.
    String writeZip({String prefix = '', Set<String> skip = const {}, Map<String, List<int>> extra = const {}}) {
      final image = img.Image(width: 40, height: 60)..clear(img.ColorRgb8(0, 0, 255));
      final png = img.encodePng(image);
      final archive = Archive();
      for (final s in suits) {
        for (final r in ranks) {
          if (skip.contains('$r$s')) continue;
          archive.addFile(ArchiveFile.bytes('$prefix$r$s.png', png));
        }
      }
      extra.forEach((name, bytes) => archive.addFile(ArchiveFile.bytes(name, bytes)));
      final zipPath = p.join(tmp.path, 'Zipped Cards.zip');
      File(zipPath).writeAsBytesSync(ZipEncoder().encode(archive));
      return zipPath;
    }

    void expectCompleteSet(CardImageSet imageSet, int width, int height) {
      for (final s in suits) {
        for (final r in ranks) {
          for (final kind in ['solid', 'transparent']) {
            final f = File(p.join(imageSet.basePath, kind, '$r$s.webp'));
            final decoded = img.decodeWebP(f.readAsBytesSync())!;
            expect([decoded.width, decoded.height], [width, height], reason: f.path);
          }
        }
      }
    }

    test('imports from zip', () async {
      final zipPath = writeZip();
      final imageSet = await importCardImageSetFromZip(zipPath: zipPath, baseDir: baseDir, variants: cardImageVariants);
      expect(imageSet.displayName, 'Zipped Cards');
      expect(imageSet.aspectRatio, closeTo(40 / 60, 1e-9));
      expectCompleteSet(imageSet, 40, 60);
      expect((await loadCustomCardImageSets(baseDir)).map((s) => s.name), [imageSet.name]);
    });

    test('imports from zip subdirectory and ignores other files', () async {
      final junk = [1, 2, 3];
      // A different-sized image in a deeper directory, which should be ignored.
      final deeperImage = img.encodePng(img.Image(width: 10, height: 10));
      final zipPath = writeZip(prefix: 'cards/', extra: {
        '__MACOSX/cards/._AS.png': junk,
        'cards/._AS.png': junk,
        'cards/README.txt': junk,
        'cards/back.png': deeperImage,
        'cards/extra/AS.png': deeperImage,
      });
      final imageSet = await importCardImageSetFromZip(zipPath: zipPath, baseDir: baseDir, variants: cardImageVariants);
      expectCompleteSet(imageSet, 40, 60);
    });

    test('fails if zip is missing cards', () async {
      final zipPath = writeZip(skip: {'TD'});
      await expectLater(
          importCardImageSetFromZip(zipPath: zipPath, baseDir: baseDir, variants: cardImageVariants),
          throwsA(isA<CardImageImportException>().having(
              (e) => e.message, 'message', contains('1 card: TD'))));
      expect(baseDir.existsSync() ? baseDir.listSync() : [], isEmpty);
    });

    test('fails on invalid zip', () async {
      final zipPath = p.join(tmp.path, 'bad.zip');
      File(zipPath).writeAsStringSync('not a zip file');
      await expectLater(
          importCardImageSetFromZip(zipPath: zipPath, baseDir: baseDir, variants: cardImageVariants),
          throwsA(isA<CardImageImportException>().having(
              (e) => e.message, 'message', contains('Unable to read zip file'))));
    });

    test('default variant stores images in the set directory', () async {
      writeCards();
      final imageSet = await importCardImageSet(sourceDir: sourceDir.path, baseDir: baseDir);
      for (final s in suits) {
        for (final r in ranks) {
          final f = File(p.join(imageSet.basePath, '$r$s.webp'));
          final decoded = img.decodeWebP(f.readAsBytesSync())!;
          expect([decoded.width, decoded.height], [50, 70], reason: f.path);
        }
      }
      expect(Directory(p.join(imageSet.basePath, 'solid')).existsSync(), false);
      expect(imageSet.imagePath('AS'), p.join(imageSet.basePath, 'AS.webp'));
    });

    test('transform variants are generated from the source image', () async {
      writeCards();
      final imageSet = await importCardImageSet(sourceDir: sourceDir.path, baseDir: baseDir, variants: const [
        CardImageVariant('original'),
        CardImageVariant('green', _greenImage),
      ]);
      // The source images are solid red. Lossy compression can change values slightly.
      final original = img.decodeWebP(File(imageSet.imagePath('AS', variant: 'original')).readAsBytesSync())!;
      final green = img.decodeWebP(File(imageSet.imagePath('AS', variant: 'green')).readAsBytesSync())!;
      final op = original.getPixel(10, 10);
      final gp = green.getPixel(10, 10);
      expect([op.r > 200, op.g < 50], [true, true]);
      expect([gp.r < 50, gp.g > 200], [true, true]);
      expect([green.width, green.height], [50, 70]);
    });

    test('loads nothing if base directory does not exist', () async {
      expect(await loadCustomCardImageSets(baseDir), isEmpty);
    });
  });
}

// Transforms must be top-level functions because they run in background isolates.
img.Image _greenImage(img.Image src) =>
    img.Image(width: src.width, height: src.height)..clear(img.ColorRgb8(0, 255, 0));
