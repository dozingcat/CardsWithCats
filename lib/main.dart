import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

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

enum DialogMode { none, mainMenu, preferences }

class _MyHomePageState extends State<MyHomePage> {
  final rng = Random();
  var loaded = false;
  var matchType = GameType.none;
  late final SharedPreferences preferences;
  DialogMode dialogMode = DialogMode.none;
  var prefsGameType = GameType.hearts;
  late HeartsRuleSet heartsRulesFromPrefs;
  late SpadesRuleSet spadesRulesFromPrefs;
  final matchUpdateNotifier = StreamController.broadcast();
  List<int> catIndices = [0, 1, 2, 3];

  @override
  void initState() {
    super.initState();
    catIndices = randomizedCatImageIndices(rng);
    _readPreferences();
  }

  void _readPreferences() async {
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
      startNewHeartsMatch();
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
        padding: EdgeInsets.all(8),
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
    final minDim = layout.displaySize.shortestSide;
    return SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Center(
            child: Dialog(
                backgroundColor: dialogBackgroundColor,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _paddingAll(
                        20,
                        Text(appTitle,
                            style: TextStyle(
                              fontSize: min(minDim / 18, 40),
                            ))),
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
                            _makeButtonRow('About...', () => _showAboutDialog(context)),
                          ],
                        )),
                  ],
                ))));
  }

  Widget _preferencesDialog(final BuildContext context, final Layout layout) {
    final minDim = layout.displaySize.shortestSide;
    const baseFontSize = 18.0;
    const optionFontSize = 14.0;

    Widget makeHeartsRuleCheckboxRow(
        String title, bool isChecked, Function(HeartsRuleSet, bool) updateRulesFn) {
      return CheckboxListTile(
        dense: true,
        title: Text(title, style: TextStyle(fontSize: optionFontSize)),
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
        title: Text(title, style: TextStyle(fontSize: optionFontSize)),
        isThreeLine: false,
        onChanged: (bool? checked) {
          updateSpadesRules((rules) => updateRulesFn(rules, checked == true));
        },
        value: isChecked,
      );
    }

    final dialogWidth = 0.8 * minDim;
    final dialogPadding = (layout.displaySize.width - dialogWidth) / 2;

    return Container(
        // width: double.infinity,
        // height: double.infinity,
        child: Dialog(
            insetPadding: EdgeInsets.only(left: dialogPadding, right: dialogPadding),
            backgroundColor: dialogBackgroundColor,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _paddingAll(
                    20,
                    Text(
                      "Preferences",
                      style: TextStyle(fontSize: min(minDim / 18, 40)),
                    )),
                Text("Changes take effect in the next match.",
                    style: TextStyle(fontSize: baseFontSize * 0.65)),
                ListTile(
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
                ListTile(
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
                _paddingAll(20, ElevatedButton(onPressed: _showMainMenu, child: Text("OK"))),
              ],
            )));
  }

  Widget _menuIcon() {
    return Padding(
      padding: EdgeInsets.all(10),
      child: FloatingActionButton(
        onPressed: _showMainMenu,
        child: Icon(Icons.menu),
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
          ),
        if (dialogMode == DialogMode.mainMenu) _mainMenuDialog(context, layout),
        if (dialogMode == DialogMode.preferences) _preferencesDialog(context, layout),
        if (dialogMode == DialogMode.none) _menuIcon(),
      ]),
    );
  }
}
