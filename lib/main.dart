import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'hearts/hearts.dart';
import 'spades/spades.dart';

import 'common_ui.dart';
import 'hearts_ui.dart';
import 'spades_ui.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CatTricks',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'CatTricks'),
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

enum GameType {none, hearts, spades}

enum DialogMode {none, mainMenu, preferences}

class _MyHomePageState extends State<MyHomePage> {
  var loaded = false;
  var matchType = GameType.none;
  late final SharedPreferences preferences;
  DialogMode dialogMode = DialogMode.none;
  var prefsGameType = GameType.hearts;
  late HeartsRuleSet heartsRulesFromPrefs;
  late SpadesRuleSet spadesRulesFromPrefs;
  final matchUpdateNotifier = StreamController.broadcast();

  @override void initState() {
    super.initState();
    _readPreferences();
  }

  void _readPreferences() async {
    preferences = await SharedPreferences.getInstance();
    // preferences.remove("matchType");
    setState(() {
      loaded = true;
      heartsRulesFromPrefs = _readHeartsRulesFromPrefs();
      spadesRulesFromPrefs = _readSpadesRulesFromPrefs();
      String? savedMatchType = preferences.getString("matchType") ?? "";
      if (savedMatchType == "hearts") {
        matchType = GameType.hearts;
      }
      else if (savedMatchType == "spades") {
        matchType = GameType.spades;
      }
      else {
        dialogMode = DialogMode.mainMenu;
      }
    });
  }

  HeartsRuleSet _readHeartsRulesFromPrefs() {
    String? json = preferences.getString("heartsRules");
    if (json != null) {
      try {
        return HeartsRuleSet.fromJson(jsonDecode(json));
      }
      catch (ex) {
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
      }
      catch (ex) {
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
    setState(() {dialogMode = DialogMode.mainMenu;});
  }

  void _showPreferences() {
    setState(() {dialogMode = DialogMode.preferences;});
  }

  void _saveHeartsMatch(final HeartsMatch? match) {
    if (match != null) {
      preferences.setString("matchType", "hearts");
      preferences.setString("heartsMatch", jsonEncode(match.toJson()));
    }
    else {
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
    }
    else {
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
        return HeartsMatch.fromJson(jsonDecode(json), Random());
      }
    }
    return _createHeartsMatch();
  }

  SpadesMatch _initialSpadesMatch() {
    if (preferences.getString("matchType") == "spades") {
      String? json = preferences.getString("spadesMatch");
      if (json != null) {
        return SpadesMatch.fromJson(jsonDecode(json), Random());
      }
    }
    return _createSpadesMatch();
  }

  HeartsMatch _createHeartsMatch() {
    return HeartsMatch(heartsRulesFromPrefs, Random());
  }

  SpadesMatch _createSpadesMatch() {
    return SpadesMatch(spadesRulesFromPrefs, Random());
  }

  void _continueGame() {
    setState(() {dialogMode = DialogMode.none;});
  }

  void _startHeartsGame() {
    preferences.remove("heartsMatch");
    final newMatch = _createHeartsMatch();
    matchUpdateNotifier.sink.add(newMatch);
    setState(() {
      dialogMode = DialogMode.none;
      matchType = GameType.hearts;
    });
  }

  void _startSpadesGame() {
    preferences.remove("spadesMatch");
    final newMatch = _createSpadesMatch();
    matchUpdateNotifier.sink.add(newMatch);
    setState(() {
      dialogMode = DialogMode.none;
      matchType = GameType.spades;
    });
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

  Widget _mainMenuDialog(final BuildContext context, final Layout layout) {
    final minDim = layout.displaySize.shortestSide;
    return Container(
        width: double.infinity,
        height: double.infinity,
        child: Center(
        child: Dialog(
        backgroundColor: dialogBackgroundColor,
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _paddingAll(10, Text(
            "CardCats",
            style: TextStyle(
              fontSize: min(minDim / 18, 40),
            )
          )),
          Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              if (matchType != GameType.none) _makeButtonRow("Continue game", _continueGame),
              _makeButtonRow("New hearts game", _startHeartsGame),
              _makeButtonRow("New spades game", _startSpadesGame),
              _makeButtonRow('Preferences...', _showPreferences),
              // _makeButtonRow('About...', () => _showAboutDialog(context)),
            ],
          ),
        ],
    )
    )));
  }

  Widget _preferencesDialog(final BuildContext context, final Layout layout) {
    final minDim = layout.displaySize.shortestSide;
    final baseFontSize = 18.0;

    Widget makeHeartsRuleCheckboxRow(String title, bool isChecked, Function(HeartsRuleSet, bool) updateRulesFn) {
      return CheckboxListTile(
        dense: true,
        title: Text(title, style: TextStyle(fontSize: baseFontSize)),
        isThreeLine: false,
        onChanged: (bool? checked) {
          updateHeartsRules((rules) => updateRulesFn(rules, checked == true));
        },
        value: isChecked,
      );
    }

    Widget makeSpadesRuleCheckboxRow(String title, bool isChecked, Function(SpadesRuleSet, bool) updateRulesFn) {
      return CheckboxListTile(
        dense: true,
        title: Text(title, style: TextStyle(fontSize: baseFontSize)),
        isThreeLine: false,
        onChanged: (bool? checked) {
          updateSpadesRules((rules) => updateRulesFn(rules, checked == true));
        },
        value: isChecked,
      );
    }

    return SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Center(
          child: Dialog(
          backgroundColor: dialogBackgroundColor,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _paddingAll(10, Text(
                "Preferences",
                style: TextStyle(fontSize: min(minDim / 18, 40)),
              )),
              Wrap(children: [
                GestureDetector(
                  onTapDown: (tap) {setState(() {prefsGameType = GameType.hearts;});},
                  child: Text("Hearts"),
                ),
                GestureDetector(
                  onTapDown: (tap) {setState(() {prefsGameType = GameType.spades;});},
                  child: Text("Spades"),
                ),
              ]),
              if (prefsGameType == GameType.hearts) ...[
                Text("Hearts settings"),
                makeHeartsRuleCheckboxRow(
                    "Jack of diamonds is -10 points",
                    heartsRulesFromPrefs.jdMinus10,
                    (rules, checked) {rules.jdMinus10 = checked;},
                ),
                makeHeartsRuleCheckboxRow(
                  "Allow points on first trick",
                  heartsRulesFromPrefs.pointsOnFirstTrick,
                  (rules, checked) {rules.pointsOnFirstTrick = checked;},
                ),
                makeHeartsRuleCheckboxRow(
                  "Queen of spades breaks hearts",
                  heartsRulesFromPrefs.queenBreaksHearts,
                  (rules, checked) {rules.queenBreaksHearts = checked;},
                ),
              ],
              if (prefsGameType == GameType.spades) ...[
                Text("Spades settings"),
                makeSpadesRuleCheckboxRow(
                  "Penalize sandbags",
                  spadesRulesFromPrefs.penalizeBags,
                  (rules, checked) {rules.penalizeBags = checked;},
                ),
                makeSpadesRuleCheckboxRow(
                  "No leading spades until broken",
                  spadesRulesFromPrefs.spadeLeading == SpadeLeading.after_broken,
                  (rules, checked) {
                    rules.spadeLeading = checked ? SpadeLeading.after_broken : SpadeLeading.always;
                  },
                ),
              ],
              _paddingAll(20, ElevatedButton(onPressed: _showMainMenu, child: Text("Done"))),
            ],
          )
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
        ...[1, 2, 3].map((i) => AiPlayerImage(layout: layout, playerIndex: i)),
        if (matchType == GameType.hearts) HeartsMatchDisplay(
          initialMatchFn: _initialHeartsMatch,
          createMatchFn: _createHeartsMatch,
          saveMatchFn: _saveHeartsMatch,
          mainMenuFn: _showMainMenu,
          matchUpdateStream: matchUpdateNotifier.stream,
          dialogVisible: dialogMode != DialogMode.none,
        ),
        if (matchType == GameType.spades) SpadesMatchDisplay(
          initialMatchFn: _initialSpadesMatch,
          createMatchFn: _createSpadesMatch,
          saveMatchFn: _saveSpadesMatch,
          mainMenuFn: _showMainMenu,
          matchUpdateStream: matchUpdateNotifier.stream,
          dialogVisible: dialogMode != DialogMode.none,
        ),
        if (dialogMode == DialogMode.mainMenu) _mainMenuDialog(context, layout),
        if (dialogMode == DialogMode.preferences) _preferencesDialog(context, layout),
        if (dialogMode == DialogMode.none) _menuIcon(),
      ]),
    );
  }
}

class MainMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    throw UnimplementedError();
  }
  
}