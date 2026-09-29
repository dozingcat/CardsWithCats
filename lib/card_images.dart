// Card image sets: the data model, persisting the selected set, and the UI for
// choosing and importing sets. This file doesn't depend on app-specific code, so
// it can be shared between apps. Cards are identified by names like "2C" or "TH".

import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'custom_card_images.dart';

enum CardImageSource {
  assets,
  filesystem,
}

class CardImageSet {
  // Unique identifier, stored in preferences.
  final String name;
  final String displayName;
  final CardImageSource source;
  final String basePath;
  // Width divided by height.
  final double aspectRatio;

  const CardImageSet(this.name, this.displayName, this.source, this.basePath, this.aspectRatio);

  String imagePath(String cardName) => "$basePath/$cardName.webp";

  ImageProvider imageProvider(String cardName) {
    final path = imagePath(cardName);
    return switch (source) {
      CardImageSource.assets => AssetImage(path),
      CardImageSource.filesystem => FileImage(File(path)),
    };
  }
}

// Returns the set with the given name, or the first set if there isn't one.
CardImageSet cardImageSetForName(String? name, List<CardImageSet> imageSets) {
  return imageSets.firstWhere((s) => s.name == name, orElse: () => imageSets.first);
}

// Holds the available card image sets (built-in and user-imported) and the
// selected set, which is stored in preferences.
class CardImageSettings extends ChangeNotifier {
  // The app's bundled image sets. The first one is the default.
  final List<CardImageSet> builtInSets;
  final String prefsKey;
  SharedPreferences? _preferences;
  late CardImageSet _selectedSet;
  // Built-in image sets followed by user-imported sets.
  late List<CardImageSet> _availableSets;
  bool _isImporting = false;

  CardImageSettings({
    required this.builtInSets,
    this.prefsKey = "cardImageSet",
  }) {
    assert(builtInSets.isNotEmpty);
    _selectedSet = builtInSets.first;
    _availableSets = builtInSets;
  }

  CardImageSet get defaultSet => builtInSets.first;
  CardImageSet get selectedSet => _selectedSet;
  List<CardImageSet> get availableSets => _availableSets;
  bool get isImporting => _isImporting;

  static Future<Directory> customImagesDir() async =>
      Directory(p.join((await getApplicationSupportDirectory()).path, "card_images"));

  Future<void> load(SharedPreferences preferences) async {
    _preferences = preferences;
    final customSets = await loadCustomCardImageSets(await customImagesDir());
    _availableSets = [...builtInSets, ...customSets];
    _selectedSet = cardImageSetForName(preferences.getString(prefsKey), _availableSets);
    notifyListeners();
  }

  void select(CardImageSet imageSet) {
    _selectedSet = imageSet;
    _preferences?.setString(prefsKey, imageSet.name);
    notifyListeners();
  }

  // Imports a new image set into the custom images directory and selects it.
  // Throws if the import fails.
  Future<void> importSet(Future<CardImageSet> Function(Directory baseDir) importFn) async {
    _isImporting = true;
    notifyListeners();
    try {
      final imageSet = await importFn(await customImagesDir());
      _availableSets = [..._availableSets, imageSet];
      select(imageSet);
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  Future<void> deleteSet(CardImageSet imageSet) async {
    if (imageSet.name == _selectedSet.name) {
      select(defaultSet);
    }
    _availableSets = _availableSets.where((s) => s.name != imageSet.name).toList();
    notifyListeners();
    try {
      await deleteCustomCardImageSet(imageSet);
    } catch (ex) {
      print("Failed to delete card images in ${imageSet.basePath}: $ex");
    }
  }
}

// Preferences row for choosing a card image set, including importing and deleting
// custom sets.
class CardImageSetPreference extends StatelessWidget {
  final CardImageSettings settings;
  final TextStyle? labelStyle;
  final double cardHeight;

  const CardImageSetPreference({
    super.key,
    required this.settings,
    this.labelStyle,
    this.cardHeight = 56,
  });

  // Folder access is unreliable on mobile because of platform sandboxing,
  // so only zip files are supported there.
  bool get _canImportFromDirectory => Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  List<(String, void Function())> _importActions(BuildContext context) {
    if (Platform.isMacOS) {
      // macOS has a native picker that can choose either a file or a folder.
      return [("Choose file or folder...", () => _importFromZipOrDirectory(context))];
    }
    if (_canImportFromDirectory) {
      return [
        ("Choose zip file...", () => _importFromZip(context)),
        ("Choose folder...", () => _importFromDirectory(context)),
      ];
    }
    return [("Choose file...", () => _importFromZip(context))];
  }

  String _importHelpText() {
    final source = _canImportFromDirectory ? "a zip file or folder" : "a zip file";
    return "Choose $source with an image for each of the 52 cards. "
        "Name each image with the card's rank (2-9, T, J, Q, K, A) and suit (C, D, H, S), "
        "like 2C.png, TD.jpg, or QS.webp.";
  }

  Future<void> _importFromZipOrDirectory(BuildContext context) async {
    final paths = await FilePicker.pickFileAndDirectoryPaths(
        dialogTitle: "Select zip file or folder with card images",
        type: FileType.custom,
        allowedExtensions: ["zip"],
    );
    if (paths.isEmpty || !context.mounted) {
      return;
    }
    final path = paths.first;
    if (await FileSystemEntity.isDirectory(path)) {
      if (!context.mounted) return;
      await _importSet(context, path, (baseDir) =>
          importCardImageSet(sourceDir: path, baseDir: baseDir));
    } else {
      if (!context.mounted) return;
      await _importSet(context, path, (baseDir) =>
          importCardImageSetFromZip(zipPath: path, baseDir: baseDir));
    }
  }

  Future<void> _importFromDirectory(BuildContext context) async {
    final sourceDir = await FilePicker.getDirectoryPath(dialogTitle: "Select folder with card images");
    if (sourceDir == null || !context.mounted) {
      return;
    }
    await _importSet(context, sourceDir, (baseDir) =>
        importCardImageSet(sourceDir: sourceDir, baseDir: baseDir));
  }

  Future<void> _importFromZip(BuildContext context) async {
    final file = await FilePicker.pickFile(
        dialogTitle: "Select zip file with card images",
        type: FileType.custom,
        allowedExtensions: ["zip"],
    );
    final zipPath = file?.path;
    if (file == null || zipPath == null || !context.mounted) {
      return;
    }
    try {
      await _importSet(context, file.name, (baseDir) => importCardImageSetFromZip(
          zipPath: zipPath,
          baseDir: baseDir,
          displayName: file.name.replaceFirst(RegExp(r"\.zip$", caseSensitive: false), ""),
      ));
    } finally {
      // On mobile the picked file is copied to a temporary location.
      if (Platform.isAndroid || Platform.isIOS) {
        FilePicker.clearTemporaryFiles();
      }
    }
  }

  Future<void> _importSet(BuildContext context, String source,
      Future<CardImageSet> Function(Directory baseDir) importFn) async {
    // The preferences UI may be closed during the import, so show any error
    // message using the navigator rather than this widget's context.
    final navigator = Navigator.of(context);
    try {
      await settings.importSet(importFn);
    } catch (ex) {
      print("Failed to import card images from $source: $ex");
      if (navigator.mounted) {
        _showMessageDialog(navigator.context, "Unable to import card images",
            "$ex\n\nThere should be an image for each card, "
            "with names like 2C.png, TD.webp, or QS.jpg.");
      }
    }
  }

  Future<void> _deleteSet(BuildContext context, CardImageSet imageSet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete card images?"),
        content: Text("Remove \"${imageSet.displayName}\" from the available card images?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete")),
        ],
      ),
    );
    if (confirmed == true) {
      await settings.deleteSet(imageSet);
    }
  }

  void _showMessageDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => CardImageSetPicker(
        imageSets: settings.availableSets,
        selectedSet: settings.selectedSet,
        onSelected: settings.select,
        labelStyle: labelStyle,
        addActions: _importActions(context),
        addHelpText: _importHelpText(),
        onDelete: (imageSet) => _deleteSet(context, imageSet),
        isImporting: settings.isImporting,
        cardHeight: cardHeight,
      ),
    );
  }
}

// Shows sample cards from the selected image set, with a button to show all
// available sets in a grid and choose a different one.
class CardImageSetPicker extends StatefulWidget {
  final List<CardImageSet> imageSets;
  final CardImageSet selectedSet;
  final void Function(CardImageSet) onSelected;
  final String label;
  final TextStyle? labelStyle;
  // Buttons shown after tapping "Add...", as (label, callback) pairs. If empty,
  // there's no add button.
  final List<(String, void Function())> addActions;
  // Explanation shown above the add action buttons.
  final String addHelpText;
  // If set, shows a delete button on filesystem (user-imported) image sets.
  final void Function(CardImageSet)? onDelete;
  // Shows a progress indicator in place of the add button.
  final bool isImporting;
  final double cardHeight;

  static const sampleCards = ["AS", "KH", "7D"];

  const CardImageSetPicker({
    super.key,
    required this.imageSets,
    required this.selectedSet,
    required this.onSelected,
    this.label = "Cards",
    this.labelStyle,
    this.addActions = const [],
    this.addHelpText = "",
    this.onDelete,
    this.isImporting = false,
    this.cardHeight = 56,
  });

  @override
  State<CardImageSetPicker> createState() => _CardImageSetPickerState();
}

class _CardImageSetPickerState extends State<CardImageSetPicker> {
  bool expanded = false;
  bool showingAddHelp = false;

  static const nameStyle = TextStyle(fontSize: 14);
  static const cellMargin = EdgeInsets.all(2);
  static const cellPadding = EdgeInsets.only(top: 6, left: 6, right: 6, bottom: 0);
  static const cellBorderWidth = 2.0;

  Widget _sampleCard(CardImageSet imageSet, String cardName, double cardHeight) {
    final cornerRadius = cardHeight * imageSet.aspectRatio * 0.05;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        border: Border.all(color: const Color.fromRGBO(64, 64, 64, 1.0), width: 0),
        borderRadius: BorderRadius.circular(cornerRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(cornerRadius),
        child: Image(
          image: imageSet.imageProvider(cardName),
          height: cardHeight,
          width: cardHeight * imageSet.aspectRatio,
          fit: BoxFit.fill,
        ),
      ),
    );
  }

  // Uses a fixed width so that layout doesn't depend on each set's aspect ratio.
  static double _sampleCardsWidth(double cardHeight) =>
      CardImageSetPicker.sampleCards.length * (cardHeight * 0.75 + 2);

  // Inverse of _sampleCardsWidth: the card height that fits in the given width.
  static double _sampleCardHeightForWidth(double width) =>
      (width / CardImageSetPicker.sampleCards.length - 2) / 0.75;

  Widget _sampleCards(CardImageSet imageSet, double cardHeight) {
    return SizedBox(
      width: _sampleCardsWidth(cardHeight),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: CardImageSetPicker.sampleCards.map((c) => _sampleCard(imageSet, c, cardHeight)).toList(),
      ),
    );
  }

  Widget _collapsed() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(children: [
        Text(widget.label, style: widget.labelStyle),
        const SizedBox(width: 16),
        Expanded(child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: _sampleCards(widget.selectedSet, widget.cardHeight),
        )),
        TextButton(
          onPressed: () => setState(() {expanded = true;}),
          child: Text("Change", style: widget.labelStyle),
        ),
      ]),
    );
  }

  Widget _imageSetCell(CardImageSet imageSet, double cardHeight) {
    final isSelected = imageSet.name == widget.selectedSet.name;
    final canDelete = widget.onDelete != null && imageSet.source == CardImageSource.filesystem;
    final baseLabelStyle = widget.labelStyle ?? const TextStyle();
    final cell = GestureDetector(
      onTap: () {
        widget.onSelected(imageSet);
        setState(() {
          showingAddHelp = false;
        });
      },
      child: Container(
        margin: cellMargin,
        padding: cellPadding,
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withValues(alpha: 0.15) : null,
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.transparent,
            width: cellBorderWidth,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          _sampleCards(imageSet, cardHeight),
          const SizedBox(height: 4),
          Text(
            imageSet.displayName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: isSelected ? baseLabelStyle.copyWith(fontWeight: FontWeight.bold) : baseLabelStyle,
          ),
        ]),
      ),
    );
    if (!canDelete) {
      return cell;
    }
    // StackFit.expand makes the cell fill the grid row height like cells without a delete button.
    return Stack(fit: StackFit.expand, children: [
      cell,
      Positioned(top: 0, right: 0, child: Tooltip(
        message: "Delete",
        child: GestureDetector(
          onTap: () => widget.onDelete!(imageSet),
          child: const CircleAvatar(
            radius: 11,
            backgroundColor: Colors.black54,
            child: Icon(Icons.close, size: 15, color: Colors.white),
          ),
        ),
      )),
    ]);
  }

  Widget _grid() {
    const numColumns = 2;
    final sets = widget.imageSets;
    // Shrink the sample cards if they don't fit in the cells. This computes the
    // size directly rather than using FittedBox, because IntrinsicHeight would use
    // the unscaled height of the FittedBox's child and leave extra space.
    return LayoutBuilder(builder: (context, constraints) {
      final cellContentWidth = constraints.maxWidth / numColumns -
          cellMargin.horizontal - cellPadding.horizontal - 2 * cellBorderWidth;
      final cardHeight = min(widget.cardHeight, _sampleCardHeightForWidth(cellContentWidth));
      return Column(children: [
        for (int i = 0; i < sets.length; i += numColumns)
          // IntrinsicHeight and stretch make cells in the same row the same height.
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (int j = i; j < i + numColumns; j++)
              Expanded(child: j < sets.length ? _imageSetCell(sets[j], cardHeight) : const SizedBox()),
          ])),
      ]);
    });
  }

  Widget _addHelp() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.addHelpText, style: nameStyle),
        const SizedBox(height: 4),
        Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
          TextButton(
            onPressed: () => setState(() {showingAddHelp = false;}),
            child: const Text("Cancel"),
          ),
          for (final (label, action) in widget.addActions)
            FilledButton.tonal(
              onPressed: () {
                setState(() {showingAddHelp = false;});
                action();
              },
              child: Text(label),
            ),
        ]),
      ]),
    );
  }

  Widget _bottomRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        if (widget.addActions.isNotEmpty && widget.isImporting) ...const [
          Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          Flexible(child: Text("Importing...", overflow: TextOverflow.ellipsis)),
        ],
        if (widget.addActions.isNotEmpty && !widget.isImporting)
          TextButton.icon(
            onPressed: () => setState(() {showingAddHelp = true;}),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text("Add...", overflow: TextOverflow.ellipsis, style: widget.labelStyle),
          ),
        const Spacer(),
        TextButton(
          onPressed: () => setState(() {
            expanded = false;
            showingAddHelp = false;
          }),
          child: Text("Done", style: widget.labelStyle),
        ),
      ]),
    );
  }

  Widget _expanded() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _grid(),
        if (showingAddHelp && !widget.isImporting) _addHelp() else _bottomRow(),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return expanded ? _expanded() : _collapsed();
  }
}
