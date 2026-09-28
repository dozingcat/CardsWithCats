import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cards_with_cats/card_images.dart';
import 'package:cards_with_cats/custom_card_images.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
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
      final imageSet = await importCardImageSet(sourceDir: sourceDir.path, baseDir: baseDir);
      expect(imageSet.displayName, 'My Cards');
      expect(imageSet.source, CardImageSource.filesystem);
      expect(imageSet.aspectRatio, closeTo(50 / 70, 1e-9));
      expect(imageSet.imagePath('AS'), p.join(imageSet.basePath, 'AS.webp'));
      for (final s in suits) {
        for (final r in ranks) {
          final f = File(p.join(imageSet.basePath, '$r$s.webp'));
          expect(f.existsSync(), true, reason: f.path);
          final decoded = img.decodeWebP(f.readAsBytesSync())!;
          expect([decoded.width, decoded.height], [50, 70]);
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
          importCardImageSet(sourceDir: sourceDir.path, baseDir: baseDir),
          throwsA(isA<CardImageImportException>().having(
              (e) => e.message, 'message', contains('2 cards: 2H, QS'))));
      expect(baseDir.existsSync() ? baseDir.listSync() : [], isEmpty);
    });

    test('fails on unreadable image', () async {
      writeCards();
      File(p.join(sourceDir.path, 'AS.webp')).writeAsStringSync('not an image');
      await expectLater(
          importCardImageSet(sourceDir: sourceDir.path, baseDir: baseDir),
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
          final f = File(p.join(imageSet.basePath, '$r$s.webp'));
          final decoded = img.decodeWebP(f.readAsBytesSync())!;
          expect([decoded.width, decoded.height], [width, height], reason: f.path);
        }
      }
    }

    test('imports from zip', () async {
      final zipPath = writeZip();
      final imageSet = await importCardImageSetFromZip(zipPath: zipPath, baseDir: baseDir);
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
      final imageSet = await importCardImageSetFromZip(zipPath: zipPath, baseDir: baseDir);
      expectCompleteSet(imageSet, 40, 60);
    });

    test('fails if zip is missing cards', () async {
      final zipPath = writeZip(skip: {'TD'});
      await expectLater(
          importCardImageSetFromZip(zipPath: zipPath, baseDir: baseDir),
          throwsA(isA<CardImageImportException>().having(
              (e) => e.message, 'message', contains('1 card: TD'))));
      expect(baseDir.existsSync() ? baseDir.listSync() : [], isEmpty);
    });

    test('fails on invalid zip', () async {
      final zipPath = p.join(tmp.path, 'bad.zip');
      File(zipPath).writeAsStringSync('not a zip file');
      await expectLater(
          importCardImageSetFromZip(zipPath: zipPath, baseDir: baseDir),
          throwsA(isA<CardImageImportException>().having(
              (e) => e.message, 'message', contains('Unable to read zip file'))));
    });

    test('loads nothing if base directory does not exist', () async {
      expect(await loadCustomCardImageSets(baseDir), isEmpty);
    });
  });
}
