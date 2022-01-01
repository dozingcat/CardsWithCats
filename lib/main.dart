import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hearts/spades/spades.dart';

import 'package:shared_preferences/shared_preferences.dart';

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
  var matchType = MatchType.spades;
  late final SharedPreferences preferences;
  late final SpadesMatch initialSpadesMatch;

  @override void initState() {
    super.initState();
    initialSpadesMatch = _createSpadesMatch();
    _readPreferences();
  }

  void _readPreferences() async {
    preferences = await SharedPreferences.getInstance();
  }

  SpadesMatch _createSpadesMatch() {
    final rules = SpadesRuleSet();
    return SpadesMatch(rules, Random());
  }

  @override
  Widget build(BuildContext context) {
    final content = matchType == MatchType.hearts ?
        HeartsMatchDisplay() :
        SpadesMatchDisplay(
          initialMatch: initialSpadesMatch,
          createMatchFn: _createSpadesMatch,
        );
    return Scaffold(
      body: content,
    );
  }
}
