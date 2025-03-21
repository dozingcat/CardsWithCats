import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

import 'bridge/bridge.dart';
import 'bridge_ui.dart';
import 'common.dart';
import 'hearts/hearts.dart';
import 'ohhell/ohhell.dart';
import 'ohhell_ui.dart';
import 'spades/spades.dart';

import 'common_ui.dart';
import 'hearts_ui.dart';
import 'spades_ui.dart';

const appTitle = "Cards With Cats";
const appVersion = "1.3.0";
const appLegalese = "© 2022-2025 Brian Nenninger";

const gameBackgroundColor = Color.fromRGBO(180, 216, 180, 1);
const gameTableColor = Color.fromRGBO(0, 128, 0, 1.0);

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
        // TODO: remove this
        useMaterial3: true,
        // colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
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

enum DialogMode { none, mainMenu, startMatch, preferences, statistics }

class _MyHomePageState extends State<MyHomePage> {
  final rng = Random();
  var loaded = false;
  GameType? matchType;
  late final SharedPreferences preferences;
  late final StatsStore statsStore;
  DialogMode dialogMode = DialogMode.none;
  var prefsGameType = GameType.hearts;
  late HeartsRuleSet heartsRulesFromPrefs;
  late SpadesRuleSet spadesRulesFromPrefs;
  late OhHellRuleSet ohHellRulesFromPrefs;
  final matchUpdateNotifier = StreamController.broadcast();
  List<int> catIndices = [0, 1, 2, 3];
  final soundPlayer = SoundEffectPlayer();
  bool useTintedTrumpCards = false;

  @override
  void initState() {
    super.initState();
    catIndices = randomizedCatImageIndices(rng);
    soundPlayer.init();
    _readPreferences();

    runAnimationTimingTestIfNeeded();
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
      ohHellRulesFromPrefs = _readOhHellRulesFromPrefs();

      String? savedMatchType = preferences.getString("matchType") ?? "";
      matchType = GameType.fromString(savedMatchType);
      if (matchType == null) {
        dialogMode = DialogMode.mainMenu;
      }

      soundPlayer.enabled = preferences.getBool("soundEnabled") ?? true;
      useTintedTrumpCards = preferences.getBool("tintedTrumpCards") ?? true;

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

  OhHellRuleSet _readOhHellRulesFromPrefs() {
    String? json = preferences.getString("ohHellRules");
    if (json != null) {
      try {
        print("Got json: $json");
        return OhHellRuleSet.fromJson(jsonDecode(json));
      } catch (ex) {
        print("Failed to read Oh Hell rules from JSON: $ex");
      }
    }
    return OhHellRuleSet();
  }

  void updateOhHellRules(Function(OhHellRuleSet) updateRulesFn) {
    setState(() {
      updateRulesFn(ohHellRulesFromPrefs);
    });
    preferences.setString("ohHellRules", jsonEncode(ohHellRulesFromPrefs.toJson()));
  }

  void setSoundEnabled(bool enabled) {
    setState(() {
      soundPlayer.enabled = enabled;
    });
    preferences.setBool("soundEnabled", enabled);
    soundPlayer.playMadSound();
  }

  void setTintedTrumpCardsEnabled(bool enabled) {
    setState(() {
      useTintedTrumpCards = enabled;
    });
    preferences.setBool("tintedTrumpCards", enabled);
  }

  bool tintedTrumpCardsEnabled() {
    return useTintedTrumpCards;
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

  void _clearMatch() {
    // TODO: Store match JSON in a single key.
    preferences.remove("heartsMatch");
    preferences.remove("spadesMatch");
    preferences.remove("ohHellMatch");
    preferences.remove("bridgeMatch");

    preferences.remove("matchType");
    matchType = null;
    dialogMode = DialogMode.mainMenu;
  }

  void _saveHeartsMatch(final HeartsMatch? match) {
    if (match != null) {
      preferences.setString("matchType", "hearts");
      preferences.setString("heartsMatch", jsonEncode(match.toJson()));
    } else {
      _clearMatch();
    }
  }

  void _saveSpadesMatch(final SpadesMatch? match) {
    if (match != null) {
      preferences.setString("matchType", "spades");
      preferences.setString("spadesMatch", jsonEncode(match.toJson()));
    } else {
      _clearMatch();
    }
  }

  void _saveOhHellMatch(final OhHellMatch? match) {
    if (match != null) {
      preferences.setString("matchType", "ohHell");
      preferences.setString("ohHellMatch", jsonEncode(match.toJson()));
    } else {
      _clearMatch();
    }
  }

  void _saveBridgeMatch(final BridgeMatch? match) {
    if (match != null) {
      preferences.setString("matchType", "bridge");
      preferences.setString("bridgeMatch", jsonEncode(match.toJson()));
    } else {
      _clearMatch();
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

  OhHellMatch _initialOhHellMatch() {
    if (preferences.getString("matchType") == "ohHell") {
      String? json = preferences.getString("ohHellMatch");
      if (json != null) {
        return OhHellMatch.fromJson(jsonDecode(json), rng);
      }
    }
    return _createOhHellMatch();
  }

  BridgeMatch _initialBridgeMatch() {
    if (preferences.getString("matchType") == "bridge") {
      String? json = preferences.getString("bridgeMatch");
      if (json != null) {
        return BridgeMatch.fromJson(jsonDecode(json), rng);
      }
    }
    return _createBridgeMatch();
  }

  HeartsMatch _createHeartsMatch() {
    catIndices = randomizedCatImageIndices(rng);
    return HeartsMatch(heartsRulesFromPrefs, rng);
  }

  SpadesMatch _createSpadesMatch() {
    catIndices = randomizedCatImageIndices(rng);
    return SpadesMatch(spadesRulesFromPrefs, Random());
  }

  OhHellMatch _createOhHellMatch() {
    catIndices = randomizedCatImageIndices(rng);
    return OhHellMatch(ohHellRulesFromPrefs, Random());
  }

  BridgeMatch _createBridgeMatch() {
    catIndices = randomizedCatImageIndices(rng);
    return BridgeMatch(Random());
  }

  void _continueGame() {
    setState(() {
      dialogMode = DialogMode.none;
    });
  }

  bool isMatchInProgress() {
    return switch (matchType) {
      GameType.hearts => preferences.getString("heartsMatch") != null,
      GameType.spades => preferences.getString("spadesMatch") != null,
      GameType.ohHell => preferences.getString("ohHellMatch") != null,
      GameType.bridge => preferences.getString("bridgeMatch") != null,
      null => false,
    };
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

  void startNewOhHellMatch() {
    preferences.remove("ohHellMatch");
    final newMatch = _createOhHellMatch();
    _saveOhHellMatch(newMatch);
    matchUpdateNotifier.sink.add(newMatch);
    setState(() {
      dialogMode = DialogMode.none;
      matchType = GameType.ohHell;
    });
  }

  void startNewBridgeMatch() {
    preferences.remove("bridgeMatch");
    final newMatch = _createBridgeMatch();
    _saveBridgeMatch(newMatch);
    matchUpdateNotifier.sink.add(newMatch);
    setState(() {
      dialogMode = DialogMode.none;
      matchType = GameType.bridge;
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

  void handleNewOhHellMatchClicked() {
    if (isMatchInProgress()) {
      showNewMatchConfirmationDialog(startNewOhHellMatch);
    } else {
      startNewOhHellMatch();
    }
  }

  void handleNewBridgeMatchClicked() {
    if (isMatchInProgress()) {
      showNewMatchConfirmationDialog(startNewBridgeMatch);
    } else {
      startNewBridgeMatch();
    }
  }

  void handleNewMatchClicked() {
    setState(() {dialogMode = DialogMode.startMatch;});
  }

  void startNewMatch(GameType newMatchType) {
    switch (newMatchType) {
      case GameType.hearts:
        handleNewHeartsMatchClicked();
        break;
      case GameType.spades:
        handleNewSpadesMatchClicked();
        break;
      case GameType.ohHell:
        handleNewOhHellMatchClicked();
        break;
      case GameType.bridge:
        handleNewBridgeMatchClicked();
        break;
    }
  }

  Widget _gameTable(final Layout layout) {
    return Positioned.fromRect(rect: layout.cardArea(), child: Container(color: gameTableColor));
  }

  void _showAboutDialog(BuildContext context) async {
    final aboutText = await DefaultAssetBundle.of(context).loadString('assets/doc/about.md');
    if (context.mounted) {
      showAboutDialog(
        context: context,
        applicationName: appTitle,
        applicationVersion: appVersion,
        applicationLegalese: appLegalese,
        children: [
          Container(height: 15),
          MarkdownBody(
            data: aboutText,
            onTapLink: (text, href, title) => launchUrl(Uri.parse(href!)),
            // https://pub.dev/documentation/flutter_markdown/latest/flutter_markdown/MarkdownListItemCrossAxisAlignment.html
            listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.start,
          ),
        ],
      );
    }
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
                            if (matchType != null)
                              _makeButtonRow("Continue match", _continueGame),
                            _makeButtonRow("New match", handleNewMatchClicked),
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

    Widget makeCheckboxRow(String title, bool isChecked, Function(bool) updateFn) {
      return CheckboxListTile(
        dense: true,
        title: Text(title, style: labelStyle),
        isThreeLine: false,
        onChanged: (checked) => updateFn(checked == true),
        value: isChecked,
      );
    }

    Widget makeHeartsRuleCheckboxRow(
        String title, bool isChecked, Function(HeartsRuleSet, bool) updateRulesFn) {
      return makeCheckboxRow(title, isChecked, (bool checked) {
        updateHeartsRules((rules) => updateRulesFn(rules, checked));
      });
    }

    Widget makeSpadesRuleCheckboxRow(
        String title, bool isChecked, Function(SpadesRuleSet, bool) updateRulesFn) {
      return makeCheckboxRow(title, isChecked, (bool checked) {
        updateSpadesRules((rules) => updateRulesFn(rules, checked));
      });
    }

    Widget makeOhHellRuleCheckboxRow(
        String title, bool isChecked, Function(OhHellRuleSet, bool) updateRulesFn) {
      return makeCheckboxRow(title, isChecked, (bool checked) {
        updateOhHellRules((rules) => updateRulesFn(rules, checked));
      });
    }

    Widget makeOhHellRuleDropdown<T>(
        List<String> titles, List<T> values, T selectedValue, Function(OhHellRuleSet, T) updateRulesFn) {
      const menuItemStyle = TextStyle(fontSize: baseFontSize * 0.8, color: Colors.blue, fontWeight: FontWeight.bold);
      final items = [for (int i = 0; i < titles.length; i++) DropdownMenuItem(
        value: values[i],
        child: Text(titles[i], style: menuItemStyle),
      )];
      return DropdownButton(
          items: items,
          value: selectedValue,
          onChanged: (T? value) {
            if (value != null) {
              updateOhHellRules((rules) => updateRulesFn(rules, value));
            }
          }
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
                            CheckboxListTile(
                              dense: true,
                              title: const Text("Tint trump cards", style: labelStyle),
                              value: useTintedTrumpCards,
                              onChanged: (bool? checked) {
                                setTintedTrumpCardsEnabled(checked == true);
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

                            const ListTile(
                                title: Text("Oh Hell",
                                    style: TextStyle(fontSize: baseFontSize, fontWeight: FontWeight.bold))),

                            makeOhHellRuleCheckboxRow(
                              "Total bids can't equal tricks",
                              ohHellRulesFromPrefs.bidTotalCantEqualTricks,
                                  (rules, checked) {
                                rules.bidTotalCantEqualTricks = checked;
                              },
                            ),

                            makeOhHellRuleCheckboxRow(
                              "Dealer's last card is trump",
                              ohHellRulesFromPrefs.trumpMethod == TrumpMethod.dealerLastCard,
                                  (rules, checked) {
                                rules.trumpMethod = checked ? TrumpMethod.dealerLastCard : TrumpMethod.firstCardAfterDeal;
                              },
                            ),

                          const ListTile(
                              title: Text("Number of tricks sequence:",
                                  style: TextStyle(fontSize: baseFontSize * 0.8))),
                          Padding(padding: EdgeInsets.only(left: 32), child: Row(children: [makeOhHellRuleDropdown<OhHellRoundSequenceVariation>(
                            ["10 to 1 to 10 (19 rounds)", "1 to 13 (13 rounds)", "Always 13 (100 points)"],
                            [OhHellRoundSequenceVariation.tenToOneToTen, OhHellRoundSequenceVariation.oneToThirteen, OhHellRoundSequenceVariation.alwaysThirteen],
                            ohHellRulesFromPrefs.roundSequenceVariation,
                            (rules, roundSequence) {
                              rules.roundSequenceVariation = roundSequence;
                            }
                          )])),

                          const ListTile(
                              title: Text("Score 1 point per trick:",
                                  style: TextStyle(fontSize: baseFontSize * 0.8))),
                          Padding(padding: EdgeInsets.only(left: 32), child: Row(children: [makeOhHellRuleDropdown<TrickScoring>(
                              ["Always", "If bid is successful", "Never"],
                              [TrickScoring.onePointPerTrickAlways, TrickScoring.onePointPerTrickSuccessfulBidOnly, TrickScoring.noPointsPerTrick],
                              ohHellRulesFromPrefs.trickScoring,
                                  (rules, scoring) {
                                rules.trickScoring = scoring;
                              }
                          )])),
                        ],
            ))))),
            _paddingAll(20, ElevatedButton(onPressed: _showMainMenu, child: const Text("OK"))),
          ],
        ))));
  }

  Widget _menuIcon() {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Opacity(opacity: 0.6, child: FloatingActionButton(
        onPressed: _showMainMenu,
        child: const Icon(Icons.menu),
      )),
    );
  }

  // A Fluttter bug causes most animations to take nearly zero time if the
  // ""Transition animation scale" option is set to off. This makes the game
  // unplayable, so we try to detect it by running a test animation on startup.
  // If the animation finishes much faster than it's supposed to, we're probably
  // in that condition and we notify the user.
  // See https://github.com/flutter/flutter/issues/165268
  bool runningTimingTestAnimation = false;
  int timingTestAnimationStartTimestamp = 0;
  bool showingAnimationSpeedWarningDialog = false;

  void runAnimationTimingTestIfNeeded() {
    if (Platform.isAndroid) {
      Future.delayed(const Duration(milliseconds: 1000), () {
        setState(() {
          timingTestAnimationStartTimestamp = DateTime.now().millisecondsSinceEpoch;
          runningTimingTestAnimation = true;
          // print("*** Started test animation");
        });
      });
    }
  }

  Widget timingTestAnimation() {
    return TweenAnimationBuilder(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(seconds: 3),
      onEnd: timingTestAnimationFinished,
      child: const Positioned(left: 0, top: 0, height: 0, width: 0, child: SizedBox()),
      builder: (BuildContext context, double animMillis, Widget? child) {
        return child!;
      },
    );
  }

  void timingTestAnimationFinished() {
    int elapsed = DateTime.now().millisecondsSinceEpoch - timingTestAnimationStartTimestamp;
    // print("*** test animation done, elapsed: $elapsed");
    if (elapsed < 1000) {
      setState(() {showingAnimationSpeedWarningDialog = true;});
    }
  }

  Widget animationSpeedWarningDialog(final Size displaySize) {
    String animationMessage = 'If animations are too fast, check the "Transition animation scale" option in the Settings app and make sure it\'s not set to "off".';
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Dialog(
          backgroundColor: dialogBackgroundColor,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(padding: const EdgeInsets.all(24), child: Text(
                  animationMessage,
                  style: const TextStyle(
                    fontSize: 20,
                  )
              )),
              Padding(padding: const EdgeInsets.only(bottom: 24), child: ElevatedButton(
                onPressed: () {setState(() {showingAnimationSpeedWarningDialog = false;});},
                child: const Text('OK'),
              )),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = computeLayout(context);
    if (!loaded) {
      return Scaffold(body: Container());
    }
    const aiIndices = [1, 2, 3];
    // Use layout.padding to avoid display cutouts. The background color is
    // drawn outside the padding so that it will extend into any cutout area.
    // (Not using SafeArea because it removes padding from child widgets, which
    // interferes with the height/width calculations).
    return Scaffold(
      body: Stack(children: [
        Container(color: gameBackgroundColor),
        Padding(padding: layout.padding, child: Stack(children: [
          // Text(layout.displaySize.shortestSide.toString()),
          _gameTable(layout),
          ...aiIndices.map((i) => AiPlayerImage(layout: layout, playerIndex: i, catImageIndex: catIndices[i])),
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
              tintTrumpCards: useTintedTrumpCards,
              soundPlayer: soundPlayer,
              statsStore: statsStore,
            ),
          if (matchType == GameType.ohHell)
            OhHellMatchDisplay(
              initialMatchFn: _initialOhHellMatch,
              createMatchFn: _createOhHellMatch,
              saveMatchFn: _saveOhHellMatch,
              mainMenuFn: _showMainMenu,
              matchUpdateStream: matchUpdateNotifier.stream,
              dialogVisible: dialogMode != DialogMode.none,
              catImageIndices: catIndices,
              tintTrumpCards: useTintedTrumpCards,
              soundPlayer: soundPlayer,
              statsStore: statsStore,
            ),
          if (matchType == GameType.bridge)
            BridgeMatchDisplay(
              initialMatchFn: _initialBridgeMatch,
              createMatchFn: _createBridgeMatch,
              saveMatchFn: _saveBridgeMatch,
              mainMenuFn: _showMainMenu,
              matchUpdateStream: matchUpdateNotifier.stream,
              dialogVisible: dialogMode != DialogMode.none,
              catImageIndices: catIndices,
              tintTrumpCards: useTintedTrumpCards,
              soundPlayer: soundPlayer,
              statsStore: statsStore,
            ),
          if (dialogMode == DialogMode.mainMenu) _mainMenuDialog(context, layout),
          if (dialogMode == DialogMode.preferences) _preferencesDialog(context, layout),
          if (dialogMode == DialogMode.startMatch) NewGameDialog(
              gameType: matchType,
              newGameFn: startNewMatch,
              cancelFn: () {setState(() {dialogMode = DialogMode.mainMenu;});},
              layout: layout),
          if (dialogMode == DialogMode.statistics) StatsDialog(
              layout: layout,
              statsStore: statsStore,
              onClose: _showMainMenu,
          ),
          if (dialogMode == DialogMode.none) _menuIcon(),

          if (runningTimingTestAnimation) timingTestAnimation(),
          if (showingAnimationSpeedWarningDialog) animationSpeedWarningDialog(layout.displaySize),
        ])),
      ]));
  }
}

TableRow _makeButtonRow(String title, void Function() onPressed) {
  return TableRow(children: [
    Padding(
      padding: const EdgeInsets.all(8),
      child: ElevatedButton(onPressed: onPressed, child: Text(title)),
    ),
  ]);
}

class NewGameDialog extends StatefulWidget {
  const NewGameDialog({
    super.key,
    required this.gameType,
    required this.newGameFn,
    required this.cancelFn,
    required this.layout,
  });

  final GameType? gameType;
  final Function(GameType) newGameFn;
  final Function() cancelFn;
  final Layout layout;

  @override
  State<NewGameDialog> createState() => _NewGameDialogState();
}

class _NewGameDialogState extends State<NewGameDialog> {
  GameType selectedGameType = GameType.hearts;

  @override
  void initState() {
    super.initState();
    selectedGameType = widget.gameType ?? GameType.hearts;
  }

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(fontSize: 16);
    const menuItemStyle = TextStyle(fontSize: 16, color: Colors.blue, fontWeight: FontWeight.normal);
    return SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Center(
            child: Transform.scale(scale: widget.layout.dialogScale(), child: Dialog(
                backgroundColor: dialogBackgroundColor,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    _paddingAll(
                        10, const Text("New Match", style: TextStyle( fontSize: 22))),
                    _paddingAll(
                        10,
                        Table(
                          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                          defaultColumnWidth: const IntrinsicColumnWidth(),
                          children: [
                            TableRow(children: [Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Padding(padding: EdgeInsets.only(right: 5), child: Text("Game: ", style: labelStyle)),
                              GameTypeDropdown(
                                gameType: selectedGameType,
                                onChanged: (matchType) {
                                  setState(() {selectedGameType = matchType!;});
                                },
                                textStyle: menuItemStyle,
                              )]),

                            ]),
                            TableRow(children: [Row(children: [
                              _paddingAll(20, ElevatedButton(
                                  onPressed: () => widget.newGameFn(selectedGameType),
                                  child: const Text("Start match"))),
                              _paddingAll(20, ElevatedButton(
                                  onPressed: widget.cancelFn,
                                  child: const Text("Cancel"))),
                            ])]),
                          ],
                        )),
                  ],
                )))));
  }

}
