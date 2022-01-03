import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hearts/spades/spades.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'hearts/hearts.dart';
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

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

enum MatchType {hearts, spades}

class _MyHomePageState extends State<MyHomePage> {
  var loaded = false;
  var matchType = MatchType.hearts;
  late final SharedPreferences preferences;
  late HeartsMatch initialHeartsMatch;
  late SpadesMatch initialSpadesMatch;

  @override void initState() {
    super.initState();
    initialSpadesMatch = _createSpadesMatch();
    initialHeartsMatch = _createHeartsMatch();
    _readPreferences();
  }

  void _readPreferences() async {
    preferences = await SharedPreferences.getInstance();
    setState(() {
      switch (preferences.getString("matchType")) {
        case "hearts":
          String? heartsJson = preferences.getString("heartsMatch");
          if (heartsJson != null) {
            initialHeartsMatch = HeartsMatch.fromJson(jsonDecode(heartsJson), Random());
          }
          break;
        case "spades":
          break;
      }
      loaded = true;
    });
  }

  void _showMainMenu() {
    // TODO
  }

  void _saveHeartsMatch(final HeartsMatch match) {
    preferences.setString("matchType", "hearts");
    preferences.setString("heartsMatch", jsonEncode(match.toJson()));
  }

  HeartsMatch _createHeartsMatch() {
    final rules = HeartsRuleSet();
    return HeartsMatch(rules, Random());
  }

  SpadesMatch _createSpadesMatch() {
    final rules = SpadesRuleSet();
    return SpadesMatch(rules, Random());
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return Scaffold(body: Container());
    }
    final content = matchType == MatchType.hearts ?
        HeartsMatchDisplay(
          initialMatch: initialHeartsMatch,
          createMatchFn: _createHeartsMatch,
          mainMenuFn: _showMainMenu,
          saveMatchFn: _saveHeartsMatch,
        ) :
        SpadesMatchDisplay(
          initialMatch: initialSpadesMatch,
          createMatchFn: _createSpadesMatch,
        );
    return Scaffold(
      body: content,
    );
  }
}
