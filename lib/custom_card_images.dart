import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'card_images.dart';

// User-imported card images are stored in subdirectories of the base directory,
// using the same layout as the bundled assets: 2C.webp, 3C.webp, etc, optionally
// in a subdirectory for each variant (see CardImageVariant).
// Each subdirectory also has an info.json file with the display name and aspect ratio.
// Absolute paths aren't stored, because on iOS the app's container directory
// can change between launches.

const _infoFilename = "info.json";
const _sourceExtensions = [".webp", ".png", ".jpg", ".jpeg"];
const _webpQuality = 90;
// Guards against zip files with huge (or maliciously compressed) entries.
const _maxZipEntrySize = 25 * 1024 * 1024;

final _allCardNames = [for (final s in "CDHS".split("")) for (final r in "23456789TJQKA".split("")) "$r$s"];

// A version of each card image that an app needs. Each variant is stored in its
// own subdirectory, or directly in the image set directory if `subdirectory` is
// null. If `transform` is set, the variant is created by applying it to the
// imported image. `transform` must be a top-level or static function, because
// it's called in background isolates.
class CardImageVariant {
  final String? subdirectory;
  final img.Image Function(img.Image)? transform;

  const CardImageVariant([this.subdirectory, this.transform]);
}

// Stores the imported images as-is (converted to webp if needed) directly in the
// image set directory.
const defaultCardImageVariants = [CardImageVariant()];

class CardImageImportException implements Exception {
  final String message;
  CardImageImportException(this.message);

  @override
  String toString() => message;
}

Future<List<CardImageSet>> loadCustomCardImageSets(Directory baseDir) async {
  final result = <CardImageSet>[];
  if (!await baseDir.exists()) {
    return result;
  }
  await for (final entry in baseDir.list()) {
    if (entry is! Directory) continue;
    if (entry.path.endsWith(".tmp")) {
      // Left over from an import that didn't finish.
      try {
        await entry.delete(recursive: true);
      } catch (ex) {
        print("Failed to delete ${entry.path}: $ex");
      }
      continue;
    }
    final infoFile = File(p.join(entry.path, _infoFilename));
    if (!await infoFile.exists()) continue;
    try {
      final info = jsonDecode(await infoFile.readAsString());
      result.add(CardImageSet(
          p.basename(entry.path),
          info["displayName"] as String,
          CardImageSource.filesystem,
          entry.path,
          (info["aspectRatio"] as num).toDouble(),
      ));
    } catch (ex) {
      print("Failed to read card image set in ${entry.path}: $ex");
    }
  }
  result.sort((a, b) => a.name.compareTo(b.name));
  return result;
}

Future<void> deleteCustomCardImageSet(CardImageSet imageSet) async {
  if (imageSet.source != CardImageSource.filesystem) {
    throw ArgumentError("Can only delete filesystem card image sets");
  }
  await Directory(imageSet.basePath).delete(recursive: true);
}

// Imports card images from `sourceDir`, which must contain an image for each card
// named like "2C.webp" or "TH.png". Writes each of `variants` as webp images in a
// new subdirectory of `baseDir`. The display name defaults to the name of `sourceDir`.
Future<CardImageSet> importCardImageSet({
  required String sourceDir,
  required Directory baseDir,
  String? displayName,
  List<CardImageVariant> variants = defaultCardImageVariants,
}) async {
  displayName ??= p.basename(sourceDir);
  final sourceFiles = await _findCardImageFiles(sourceDir);
  final name = "custom_${DateTime.now().millisecondsSinceEpoch}";
  final destDir = p.join(baseDir.path, name);
  // Write to a temporary directory and rename when done, so that a partial import
  // won't be picked up by loadCustomCardImageSets.
  final tmpDir = "$destDir.tmp";
  try {
    final aspectRatio = await _convertCardImages(sourceFiles, tmpDir, variants);
    await File(p.join(tmpDir, _infoFilename)).writeAsString(jsonEncode({
      "displayName": displayName,
      "aspectRatio": aspectRatio,
    }));
    await Directory(tmpDir).rename(destDir);
    return CardImageSet(name, displayName, CardImageSource.filesystem, destDir, aspectRatio);
  } catch (ex) {
    final dir = Directory(tmpDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    rethrow;
  }
}

// Imports card images from a zip file. The images can be at the top level of the
// zip or in a subdirectory; if there are multiple images for the same card, the
// one closest to the top level is used. The display name defaults to the name of
// the zip file without the extension.
Future<CardImageSet> importCardImageSetFromZip({
  required String zipPath,
  required Directory baseDir,
  String? displayName,
  List<CardImageVariant> variants = defaultCardImageVariants,
}) async {
  final extractDir = await Directory.systemTemp.createTemp("card_images_zip");
  try {
    await Isolate.run(() => _extractCardImagesFromZip(zipPath, extractDir.path));
    return await importCardImageSet(
        sourceDir: extractDir.path,
        baseDir: baseDir,
        displayName: displayName ?? p.basenameWithoutExtension(zipPath),
        variants: variants,
    );
  } finally {
    await extractDir.delete(recursive: true);
  }
}

bool _isCardImageFilename(String filename) {
  return _sourceExtensions.contains(p.extension(filename).toLowerCase()) &&
      _allCardNames.contains(p.basenameWithoutExtension(filename).toUpperCase());
}

// Writes card images from the zip file to `destDir`, without any subdirectories.
void _extractCardImagesFromZip(String zipPath, String destDir) {
  final input = InputFileStream(zipPath);
  try {
    Archive? archive;
    try {
      archive = ZipDecoder().decodeStream(input);
    } catch (ex) {
      // Handled below.
    }
    // The decoder returns an empty archive for some invalid files instead of throwing.
    if (archive == null || archive.isEmpty) {
      throw CardImageImportException("Unable to read zip file: ${p.basename(zipPath)}");
    }
    // Zip entry names always use "/". Skip macOS metadata like "__MACOSX/2C.png"
    // and "._2C.png", and anything else hidden.
    final entries = archive.files.where((f) =>
        f.isFile &&
        _isCardImageFilename(p.posix.basename(f.name)) &&
        !f.name.split("/").any((part) => part.startsWith(".") || part == "__MACOSX")
    ).toList();
    int depth(ArchiveFile f) => "/".allMatches(f.name).length;
    entries.sort((a, b) => depth(a).compareTo(depth(b)));
    // Lowercase to avoid collisions on case-insensitive filesystems.
    final extracted = <String>{};
    for (final f in entries) {
      final filename = p.posix.basename(f.name);
      if (!extracted.add(filename.toLowerCase())) continue;
      if (f.size > _maxZipEntrySize) {
        throw CardImageImportException("Image is too large: $filename");
      }
      // Only the base filename is used, so entries can't write outside of destDir.
      final output = OutputFileStream(p.join(destDir, filename));
      try {
        f.writeContent(output);
      } finally {
        output.closeSync();
      }
    }
  } finally {
    input.closeSync();
  }
}

// Returns a map from card name ("2C") to file path, or throws if any cards are missing.
Future<Map<String, String>> _findCardImageFiles(String sourceDir) async {
  final dir = Directory(sourceDir);
  if (!await dir.exists()) {
    throw CardImageImportException("Directory not found: $sourceDir");
  }
  final filesByCard = <String, String>{};
  await for (final entry in dir.list()) {
    if (entry is! File) continue;
    final filename = p.basename(entry.path);
    final ext = p.extension(filename).toLowerCase();
    if (!_sourceExtensions.contains(ext)) continue;
    final cardName = p.basenameWithoutExtension(filename).toUpperCase();
    // If there are multiple files for the same card, prefer webp.
    if (!filesByCard.containsKey(cardName) || ext == ".webp") {
      filesByCard[cardName] = entry.path;
    }
  }
  final missing = _allCardNames.where((c) => !filesByCard.containsKey(c)).toList();
  if (missing.isNotEmpty) {
    final missingStr = missing.length > 8 ? "${missing.take(8).join(", ")}..." : missing.join(", ");
    throw CardImageImportException(
        "Missing images for ${missing.length} ${missing.length == 1 ? 'card' : 'cards'}: $missingStr");
  }
  return {for (final c in _allCardNames) c: filesByCard[c]!};
}

// Writes webp images for each card and variant to `destDir`, and returns the aspect
// ratio. Conversion is CPU-intensive so it's split across background isolates.
Future<double> _convertCardImages(
    Map<String, String> sourceFiles, String destDir, List<CardImageVariant> variants) async {
  for (final v in variants) {
    await Directory(_variantDir(destDir, v)).create(recursive: true);
  }

  final entries = sourceFiles.entries.toList();
  final numWorkers = Platform.numberOfProcessors.clamp(1, 8);
  final batches = List.generate(numWorkers, (i) => [
    for (int j = i; j < entries.length; j += numWorkers) (entries[j].key, entries[j].value)
  ]);
  final sizes = await Future.wait(batches.map((batch) => Isolate.run(() {
    final result = <String, (int, int)>{};
    for (final (cardName, path) in batch) {
      result[cardName] = _convertCardImage(cardName, path, destDir, variants);
    }
    return result;
  })));
  final (width, height) = sizes.firstWhere((m) => m.containsKey("AS"))["AS"]!;
  return width / height;
}

String _variantDir(String destDir, CardImageVariant variant) {
  final subdirectory = variant.subdirectory;
  return subdirectory == null ? destDir : p.join(destDir, subdirectory);
}

// Returns the (width, height) of the image.
(int, int) _convertCardImage(
    String cardName, String sourcePath, String destDir, List<CardImageVariant> variants) {
  final bytes = File(sourcePath).readAsBytesSync();
  final image = img.decodeNamedImage(sourcePath, bytes);
  if (image == null) {
    throw CardImageImportException("Unable to read image: ${p.basename(sourcePath)}");
  }
  for (final variant in variants) {
    final destPath = p.join(_variantDir(destDir, variant), "$cardName.webp");
    final transform = variant.transform;
    if (transform != null) {
      // Transforms may add transparency, so keep full alpha quality.
      File(destPath).writeAsBytesSync(img.encodeWebP(
          transform(image), lossless: false, quality: _webpQuality, alphaQuality: 100));
    } else if (p.extension(sourcePath).toLowerCase() == ".webp") {
      File(destPath).writeAsBytesSync(bytes);
    } else {
      File(destPath).writeAsBytesSync(img.encodeWebP(image, lossless: false, quality: _webpQuality));
    }
  }
  return (image.width, image.height);
}
