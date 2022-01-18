import 'dart:convert';
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

enum MatchType {none, hearts, spades}

enum DialogMode {none, mainMenu, preferences}

class _MyHomePageState extends State<MyHomePage> {
  var loaded = false;
  var matchType = MatchType.none;
  late final SharedPreferences preferences;
  DialogMode dialogMode = DialogMode.none;

  @override void initState() {
    super.initState();
    _readPreferences();
  }

  void _readPreferences() async {
    preferences = await SharedPreferences.getInstance();
    // preferences.remove("matchType");
    setState(() {
      loaded = true;
      String? savedMatchType = preferences.getString("matchType") ?? "";
      if (savedMatchType == "hearts") {
        matchType = MatchType.hearts;
      }
      else if (savedMatchType == "spades") {
        matchType = MatchType.spades;
      }
      else {
        dialogMode = DialogMode.mainMenu;
      }
    });
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
      matchType = MatchType.none;
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
      matchType = MatchType.none;
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
    final rules = HeartsRuleSet();
    return HeartsMatch(rules, Random());
  }

  SpadesMatch _createSpadesMatch() {
    final rules = SpadesRuleSet();
    return SpadesMatch(rules, Random());
  }

  void _continueGame() {
    setState(() {dialogMode = DialogMode.none;});
  }

  void _startHeartsGame() {
    preferences.remove("heartsMatch");
    setState(() {
      dialogMode = DialogMode.none;
      matchType = MatchType.hearts;
    });
  }

  void _startSpadesGame() {
    preferences.remove("spadesMatch");
    setState(() {
      dialogMode = DialogMode.none;
      matchType = MatchType.spades;
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
              if (matchType != MatchType.none) _makeButtonRow("Continue game", _continueGame),
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
                "Preferences",
                style: TextStyle(fontSize: min(minDim / 18, 40)),
               )),
              ElevatedButton(onPressed: _showMainMenu, child: Text("Done"))
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
        if (matchType == MatchType.hearts) HeartsMatchDisplay(
          initialMatch: _initialHeartsMatch(),
          createMatchFn: _createHeartsMatch,
          saveMatchFn: _saveHeartsMatch,
          mainMenuFn: _showMainMenu,
          dialogVisible: dialogMode != DialogMode.none,
        ),
        if (matchType == MatchType.spades) SpadesMatchDisplay(
          initialMatch: _initialSpadesMatch(),
          createMatchFn: _createSpadesMatch,
          saveMatchFn: _saveSpadesMatch,
          mainMenuFn: _showMainMenu,
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