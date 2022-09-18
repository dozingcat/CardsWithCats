import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cards_with_cats/soundeffects.dart';
import 'package:cards_with_cats/stats/stats_json.dart';
import 'package:cards_with_cats/stats/stats_store.dart';
import 'package:cards_with_cats/stats_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'hearts/hearts.dart';
import 'spades/spades.dart';

import 'common_ui.dart';
import 'hearts_ui.dart';
import 'spades_ui.dart';

const appTitle = "Cards With Cats";

void main() {
  runApp(const MyApp());
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // debugShowCheckedModeBanner: false,
      title: appTitle,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Cards With Cats'),
    );
  }
}

const dialogBackgroundColor = Color.fromARGB(0xd0, 0xd8, 0xd8, 0xd8);
const dialogTableBackgroundColor = Color.fromARGB(0x80, 0xc0, 0xc0, 0xc0);

Widget _paddingAll(final double paddingPx, final Widget child) {
  return Padding(padding: EdgeInsets.all(paddingPx), child: child);
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

List<int> randomizedCatImageIndices(Random rng) {
  final indices = [0, 1, 2, 3];
  indices.shuffle(rng);
  return indices;
}

enum GameType { none, hearts, spades }

enum DialogMode { none, mainMenu, preferences, statistics }

class _MyHomePageState extends State<MyHomePage> {
  final rng = Random();
  var loaded = false;
  var matchType = GameType.none;
  late final SharedPreferences preferences;
  late final StatsStore statsStore;
  DialogMode dialogMode = DialogMode.none;
  var prefsGameType = GameType.hearts;
  late HeartsRuleSet heartsRulesFromPrefs;
  late SpadesRuleSet spadesRulesFromPrefs;
  final matchUpdateNotifier = StreamController.broadcast();
  List<int> catIndices = [0, 1, 2, 3];
  final soundPlayer = SoundEffectPlayer();

  @override
  void initState() {
    super.initState();
    catIndices = randomizedCatImageIndices(rng);
    soundPlayer.init();
    _readPreferences();
  }

  void _readPreferences() async {
    final statsDir = await getApplicationSupportDirectory();
    print("Application support directory: $statsDir");
    preferences = await SharedPreferences.getInstance();
    // preferences.clear();
    // preferences.remove("matchType");
    setState(() {
      loaded = true;
      heartsRulesFromPrefs = _readHeartsRulesFromPrefs();
      spadesRulesFromPrefs = _readSpadesRulesFromPrefs();

      String? savedMatchType = preferences.getString("matchType") ?? "";
      if (savedMatchType == "hearts") {
        matchType = GameType.hearts;
      } else if (savedMatchType == "spades") {
        matchType = GameType.spades;
      } else {
        dialogMode = DialogMode.mainMenu;
      }

      soundPlayer.enabled = preferences.getBool("soundEnabled") ?? true;

      statsStore = JsonFileStatsStore(baseDirectory: statsDir);
    });
  }

  HeartsRuleSet _readHeartsRulesFromPrefs() {
    String? json = preferences.getString("heartsRules");
    if (json != null) {
      try {
        return HeartsRuleSet.fromJson(jsonDecode(json));
      } catch (ex) {
        print("Failed to read hearts rules from JSON: $ex");
      }
    }
    return HeartsRuleSet();
  }

  void updateHeartsRules(Function(HeartsRuleSet) updateRulesFn) {
    setState(() {
      updateRulesFn(heartsRulesFromPrefs);
    });
    preferences.setString("heartsRules", jsonEncode(heartsRulesFromPrefs.toJson()));
  }

  SpadesRuleSet _readSpadesRulesFromPrefs() {
    String? json = preferences.getString("spadesRules");
    if (json != null) {
      try {
        return SpadesRuleSet.fromJson(jsonDecode(json));
      } catch (ex) {
        print("Failed to read spades rules from JSON: $ex");
      }
    }
    return SpadesRuleSet();
  }

  void updateSpadesRules(Function(SpadesRuleSet) updateRulesFn) {
    setState(() {
      updateRulesFn(spadesRulesFromPrefs);
    });
    preferences.setString("spadesRules", jsonEncode(spadesRulesFromPrefs.toJson()));
  }

  void setSoundEnabled(bool enabled) {
    setState(() {
      soundPlayer.enabled = enabled;
    });
    preferences.setBool("soundEnabled", enabled);
    soundPlayer.playMadSound();
  }

  void _showMainMenu() {
    setState(() {
      dialogMode = DialogMode.mainMenu;
    });
  }

  void _showPreferences() {
    setState(() {
      dialogMode = DialogMode.preferences;
    });
  }

  void _showStats() {
    setState(() {
      dialogMode = DialogMode.statistics;
    });
  }

  void _saveHeartsMatch(final HeartsMatch? match) {
    if (match != null) {
      preferences.setString("matchType", "hearts");
      preferences.setString("heartsMatch", jsonEncode(match.toJson()));
    } else {
      preferences.remove("matchType");
      preferences.remove("heartsMatch");
      matchType = GameType.none;
      dialogMode = DialogMode.mainMenu;
    }
  }

  void _saveSpadesMatch(final SpadesMatch? match) {
    if (match != null) {
      preferences.setString("matchType", "spades");
      preferences.setString("spadesMatch", jsonEncode(match.toJson()));
    } else {
      preferences.remove("matchType");
      preferences.remove("spadesMatch");
      matchType = GameType.none;
      dialogMode = DialogMode.mainMenu;
    }
  }

  HeartsMatch _initialHeartsMatch() {
    if (preferences.getString("matchType") == "hearts") {
      String? json = preferences.getString("heartsMatch");
      if (json != null) {
        return HeartsMatch.fromJson(jsonDecode(json), rng);
      }
    }
    return _createHeartsMatch();
  }

  SpadesMatch _initialSpadesMatch() {
    if (preferences.getString("matchType") == "spades") {
      String? json = preferences.getString("spadesMatch");
      if (json != null) {
        return SpadesMatch.fromJson(jsonDecode(json), rng);
      }
    }
    return _createSpadesMatch();
  }

  HeartsMatch _createHeartsMatch() {
    catIndices = randomizedCatImageIndices(rng);
    return HeartsMatch(heartsRulesFromPrefs, rng);
  }

  SpadesMatch _createSpadesMatch() {
    catIndices = randomizedCatImageIndices(rng);
    return SpadesMatch(spadesRulesFromPrefs, Random());
  }

  void _continueGame() {
    setState(() {
      dialogMode = DialogMode.none;
    });
  }

  bool isMatchInProgress() {
    if (matchType == GameType.hearts) {
      return preferences.getString("heartsMatch") != null;
    }
    if (matchType == GameType.spades) {
      return preferences.getString("spadesMatch") != null;
    }
    return false;
  }

  void startNewHeartsMatch() {
    preferences.remove("heartsMatch");
    final newMatch = _createHeartsMatch();
    _saveHeartsMatch(newMatch);
    matchUpdateNotifier.sink.add(newMatch);
    setState(() {
      dialogMode = DialogMode.none;
      matchType = GameType.hearts;
    });
  }

  void startNewSpadesMatch() {
    preferences.remove("spadesMatch");
    final newMatch = _createSpadesMatch();
    _saveSpadesMatch(newMatch);
    matchUpdateNotifier.sink.add(newMatch);
    setState(() {
      dialogMode = DialogMode.none;
      matchType = GameType.spades;
    });
  }

  void showNewMatchConfirmationDialog(Function() doNewMatch) {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text("New match"),
            content:
                const Text("Are you sure you want to end the current match and start a new one?"),
            actions: [
              TextButton(
                  child: const Text("Don't end match"),
                  onPressed: () {
                    Navigator.of(context).pop();
                  }),
              TextButton(
                  child: const Text("End match"),
                  onPressed: () {
                    Navigator.of(context).pop();
                    doNewMatch();
                  }),
            ],
          );
        });
  }

  void handleNewHeartsMatchClicked() {
    if (isMatchInProgress()) {
      showNewMatchConfirmationDialog(startNewHeartsMatch);
    } else {
      startNewHeartsMatch();
    }
  }

  void handleNewSpadesMatchClicked() {
    if (isMatchInProgress()) {
      showNewMatchConfirmationDialog(startNewSpadesMatch);
    } else {
      startNewSpadesMatch();
    }
  }

  static const gameBackgroundColor = Color.fromRGBO(32, 160, 32, 0.3);
  static const gameTableColor = Color.fromRGBO(0, 128, 0, 1.0);

  Widget _gameTable(final Layout layout) {
    final rect = Rect.fromLTWH(0, 0, layout.displaySize.width, layout.displaySize.height);
    return Stack(children: [
      Positioned.fromRect(rect: rect, child: Container(color: gameBackgroundColor)),
      Positioned.fromRect(rect: layout.cardArea(), child: Container(color: gameTableColor)),
    ]);
  }

  TableRow _makeButtonRow(String title, void Function() onPressed) {
    return TableRow(children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: ElevatedButton(onPressed: onPressed, child: Text(title)),
      ),
    ]);
  }

  void _showAboutDialog(BuildContext context) async {
    final aboutText = await DefaultAssetBundle.of(context).loadString('assets/doc/about.md');
    showAboutDialog(
      context: context,
      applicationName: appTitle,
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2022 Brian Nenninger',
      children: [
        Container(height: 15),
        MarkdownBody(
          data: aboutText,
          onTapLink: (text, href, title) => launch(href!),
          // https://github.com/flutter/flutter_markdown/issues/311
          listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.start,
        ),
      ],
    );
  }

  Widget _mainMenuDialog(final BuildContext context, final Layout layout) {
    return SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Center(
            child: Transform.scale(scale: layout.dialogScale(), child: Dialog(
                backgroundColor: dialogBackgroundColor,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _paddingAll(
                        20, const Text(appTitle, style: TextStyle( fontSize: 26))),
                    _paddingAll(
                        10,
                        Table(
                          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                          defaultColumnWidth: const IntrinsicColumnWidth(),
                          children: [
                            if (matchType != GameType.none)
                              _makeButtonRow("Continue match", _continueGame),
                            _makeButtonRow("New hearts match", handleNewHeartsMatchClicked),
                            _makeButtonRow("New spades match", handleNewSpadesMatchClicked),
                            _makeButtonRow('Preferences...', _showPreferences),
                            _makeButtonRow('Statistics...', _showStats),
                            _makeButtonRow('About...', () => _showAboutDialog(context)),
                          ],
                        )),
                  ],
                )))));
  }

  Widget _preferencesDialog(final BuildContext context, final Layout layout) {
    final minDim = layout.displaySize.shortestSide;
    const baseFontSize = 18.0;
    const labelStyle = TextStyle(fontSize: 14.0);

    Widget makeHeartsRuleCheckboxRow(
        String title, bool isChecked, Function(HeartsRuleSet, bool) updateRulesFn) {
      return CheckboxListTile(
        dense: true,
        title: Text(title, style: labelStyle),
        isThreeLine: false,
        onChanged: (bool? checked) {
          updateHeartsRules((rules) => updateRulesFn(rules, checked == true));
        },
        value: isChecked,
      );
    }

    Widget makeSpadesRuleCheckboxRow(
        String title, bool isChecked, Function(SpadesRuleSet, bool) updateRulesFn) {
      return CheckboxListTile(
        dense: true,
        title: Text(title, style: labelStyle),
        isThreeLine: false,
        onChanged: (bool? checked) {
          updateSpadesRules((rules) => updateRulesFn(rules, checked == true));
        },
        value: isChecked,
      );
    }

    final dialogWidth = min(350, 0.8 * minDim / layout.dialogScale());
    final dialogPadding = (layout.displaySize.width - dialogWidth) / 2;
    final maxDialogHeight = layout.displaySize.height * 0.9 / layout.dialogScale();

    return Transform.scale(scale: layout.dialogScale(), child: Dialog(
        insetPadding: EdgeInsets.only(left: dialogPadding, right: dialogPadding),
        backgroundColor: dialogBackgroundColor,
        child: ConstrainedBox(constraints: BoxConstraints(maxHeight: maxDialogHeight), child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _paddingAll(
                20,
                const Text(
                  "Preferences",
                  style: TextStyle(fontSize: 24)),
                ),
            const Text("Rule changes take effect in the next match.",
                style: TextStyle(fontSize: baseFontSize * 0.65)),
            const SizedBox(height: baseFontSize),

            Flexible(child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                    primary: true,
                    child: Container(
                        color: dialogTableBackgroundColor,
                        child: Column(children: [
                          CheckboxListTile(
                            dense: true,
                            title: const Text("Enable sound", style: labelStyle),
                            value: soundPlayer.enabled,
                            onChanged: (bool? checked) {
                              setSoundEnabled(checked == true);
                            },
                          ),
                            const ListTile(
                                title: Text("Hearts",
                                    style: TextStyle(fontSize: baseFontSize, fontWeight: FontWeight.bold))),
                            makeHeartsRuleCheckboxRow(
                              "J♦ is -10 points",
                              heartsRulesFromPrefs.jdMinus10,
                              (rules, checked) {
                                rules.jdMinus10 = checked;
                              },
                            ),
                            makeHeartsRuleCheckboxRow(
                              "Q♠ breaks hearts",
                              heartsRulesFromPrefs.queenBreaksHearts,
                              (rules, checked) {
                                rules.queenBreaksHearts = checked;
                              },
                            ),
                            makeHeartsRuleCheckboxRow(
                              "Allow points on first trick",
                              heartsRulesFromPrefs.pointsOnFirstTrick,
                              (rules, checked) {
                                rules.pointsOnFirstTrick = checked;
                              },
                            ),
                            const ListTile(
                                title: Text("Spades",
                                    style: TextStyle(fontSize: baseFontSize, fontWeight: FontWeight.bold))),
                            makeSpadesRuleCheckboxRow(
                              "Penalize sandbags",
                              spadesRulesFromPrefs.penalizeBags,
                              (rules, checked) {
                                rules.penalizeBags = checked;
                              },
                            ),
                            makeSpadesRuleCheckboxRow(
                              "No leading spades until broken",
                              spadesRulesFromPrefs.spadeLeading == SpadeLeading.after_broken,
                              (rules, checked) {
                                rules.spadeLeading = checked ? SpadeLeading.after_broken : SpadeLeading.always;
                              },
                            ),
                        ],
            ))))),
            _paddingAll(20, ElevatedButton(onPressed: _showMainMenu, child: const Text("OK"))),
          ],
        ))));
  }

  Widget _menuIcon() {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: FloatingActionButton(
        onPressed: _showMainMenu,
        child: const Icon(Icons.menu),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = computeLayout(context);
    if (!loaded) {
      return Scaffold(body: Container());
    }
    return Scaffold(
      body: Stack(children: [
        Text(layout.displaySize.shortestSide.toString()),
        _gameTable(layout),
        ...[
          1,
          2,
          3
        ].map((i) => AiPlayerImage(layout: layout, playerIndex: i, catImageIndex: catIndices[i])),
        if (matchType == GameType.hearts)
          HeartsMatchDisplay(
            initialMatchFn: _initialHeartsMatch,
            createMatchFn: _createHeartsMatch,
            saveMatchFn: _saveHeartsMatch,
            mainMenuFn: _showMainMenu,
            matchUpdateStream: matchUpdateNotifier.stream,
            dialogVisible: dialogMode != DialogMode.none,
            catImageIndices: catIndices,
            soundPlayer: soundPlayer,
            statsStore: statsStore,
          ),
        if (matchType == GameType.spades)
          SpadesMatchDisplay(
            initialMatchFn: _initialSpadesMatch,
            createMatchFn: _createSpadesMatch,
            saveMatchFn: _saveSpadesMatch,
            mainMenuFn: _showMainMenu,
            matchUpdateStream: matchUpdateNotifier.stream,
            dialogVisible: dialogMode != DialogMode.none,
            catImageIndices: catIndices,
            soundPlayer: soundPlayer,
            statsStore: statsStore,
          ),
        if (dialogMode == DialogMode.mainMenu) _mainMenuDialog(context, layout),
        if (dialogMode == DialogMode.preferences) _preferencesDialog(context, layout),
        if (dialogMode == DialogMode.statistics) StatsDialog(
            layout: layout,
            statsStore: statsStore,
            onClose: _showMainMenu,
        ),
        if (dialogMode == DialogMode.none) _menuIcon(),
      ]),
    );
  }
}
