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
  var matchType = MatchType.spades;
  late final SharedPreferences preferences;

  @override void initState() {
    super.initState();
    _readPreferences();
  }

  void _readPreferences() async {
    preferences = await SharedPreferences.getInstance();
    setState(() {
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

  void _saveSpadesMatch(final SpadesMatch match) {
    preferences.setString("matchType", "spades");
    preferences.setString("spadesMatch", jsonEncode(match.toJson()));
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

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return Scaffold(body: Container());
    }
    final content = matchType == MatchType.hearts ?
        HeartsMatchDisplay(
          initialMatch: _initialHeartsMatch(),
          createMatchFn: _createHeartsMatch,
          saveMatchFn: _saveHeartsMatch,
          mainMenuFn: _showMainMenu,
        ) :
        SpadesMatchDisplay(
          initialMatch: _initialSpadesMatch(),
          createMatchFn: _createSpadesMatch,
          saveMatchFn: _saveSpadesMatch,
          mainMenuFn: _showMainMenu,
        );
    return Scaffold(
      body: content,
    );
  }
}
