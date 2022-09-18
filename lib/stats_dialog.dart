import 'package:cards_with_cats/spades/spades_stats.dart';
import 'package:cards_with_cats/stats/stats_store.dart';
import 'package:flutter/material.dart';

import 'common_ui.dart';
import 'hearts/hearts_stats.dart';

class StatsDialog extends StatefulWidget {
  final Layout layout;
  final StatsStore statsStore;
  final void Function() onClose;

  const StatsDialog({
    Key? key,
    required this.layout,
    required this.statsStore,
    required this.onClose,
  }) : super(key: key);

  @override
  _StatsDialogState createState() => _StatsDialogState();
}

enum StatsMode {hearts, spades}

const dialogBackgroundColor = Color.fromARGB(0x80, 0xd8, 0xd8, 0xd8);
const statsTableBackgroundColor = Color.fromARGB(0x80, 0xc0, 0xc0, 0xc0);

class _StatsDialogState extends State<StatsDialog> with SingleTickerProviderStateMixin {
  late HeartsStats heartsStats;
  late SpadesStats spadesStats;
  late TabController tabController;
  var mode = StatsMode.hearts;
  var loaded = false;

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 2, vsync: this);
    tabController.addListener(() {
      setState(() {
        mode = tabController.index == 0 ? StatsMode.hearts : StatsMode.spades;
      });
    });
    _loadStats();
  }

  void _loadStats() async {
    heartsStats = (await widget.statsStore.readHeartsStats()) ?? HeartsStats.empty();
    spadesStats = (await widget.statsStore.readSpadesStats()) ?? SpadesStats.empty();
    setState(() {loaded = true;});
  }

  @override
  Widget build(BuildContext context) {
    final ds = widget.layout.displaySize;
    final paddingPx = 12.0;
    final scale = widget.layout.dialogScale();
    final maxDialogHeight = ds.height * 0.9 / scale;
    final maxDialogWidth = ds.width * 0.9 / scale;

    return Transform.scale(scale: scale, child: Dialog(
        backgroundColor: dialogBackgroundColor,
        child: ConstrainedBox(constraints: BoxConstraints(maxHeight: maxDialogHeight), child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.only(top: 20.0), child:
              Text(
                  "Statistics",
                  style: TextStyle(fontSize: 20)),
            ),

            // If there's not a max width, TabBar will take all available width.
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 250), child: TabBar(
              controller: tabController,
              tabs: [
                _paddingAll(10, const Text("Hearts")),
                _paddingAll(10, const Text("Spades")),
              ],
            )),

            // Flexible can grow to max allowed size, but (unlike Expanded) doesn't have to.
            if (loaded) Flexible(child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(primary: true, child: Container(
                color: statsTableBackgroundColor,
                child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: paddingPx),
                    child: mode == StatsMode.hearts ?
                        heartsStatsTable(heartsStats, widget.layout) :
                        spadesStatsTable(spadesStats, widget.layout)
              ))))),

            _paddingAll(
                paddingPx * 1.5,
                ElevatedButton(
                  onPressed: widget.onClose,
                  child: const Text("OK"),
                )
            ),
          ],
        ))));
  }
}

Widget _paddingAll(final double paddingPx, final Widget child) {
  return Padding(padding: EdgeInsets.all(paddingPx), child: child);
}

TableRow statsTableRow(String name, String value) {
  const textStyle = TextStyle(fontSize: 14);
  return TableRow(children: [
    _paddingAll(8, Text(name, textAlign: TextAlign.left, style: textStyle)),
    const SizedBox(width: 10),
    _paddingAll(8, Text(value, textAlign: TextAlign.right, style: textStyle)),
  ]);
}

Widget heartsStatsTable(HeartsStats stats, Layout layout) {
  final avgPointsPerMatch = stats.numMatches > 0 ? stats.totalMatchPointsTaken / stats.numMatches : null;
  final roundsWithoutJd = stats.numRounds - stats.numRoundsWithJdRule;
  final avgPointsPerRoundWithoutJd = roundsWithoutJd > 0 ?
      stats.totalRoundPointsTakenWithoutJdRule / roundsWithoutJd : null;
  final avgPointsPerRoundWithJd = stats.numRoundsWithJdRule > 0 ?
      stats.totalRoundPointsTakenWithJdRule / stats.numRoundsWithJdRule : null;
  return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      defaultColumnWidth: const IntrinsicColumnWidth(),
      children: [
        statsTableRow("Matches played", stats.numMatches.toString()),
        statsTableRow("Matches won", stats.matchesWon.toString()),
        statsTableRow("Matches tied", stats.matchesTied.toString()),
        statsTableRow("Average points/match", avgPointsPerMatch?.toStringAsFixed(1) ?? "--"),
        statsTableRow("Rounds played (no J♦)", roundsWithoutJd.toString()),
        statsTableRow("Avg points/round (no J♦)", avgPointsPerRoundWithoutJd?.toStringAsFixed(2) ?? "--"),
        statsTableRow("Rounds played (with J♦)", stats.numRoundsWithJdRule.toString()),
        statsTableRow("Avg points/round (with J♦)", avgPointsPerRoundWithJd?.toStringAsFixed(2) ?? "--"),
        statsTableRow("Q♠ taken", stats.numQsTaken.toString()),
        statsTableRow("J♦ taken", stats.numJdTaken.toString()),
        statsTableRow("Moon shoots", stats.numMoonShoots.toString()),
        statsTableRow("Opponent moon shoots", stats.numOpponentMoonShoots.toString()),
      ]);
}

Widget spadesStatsTable(SpadesStats stats, Layout layout) {
  final avgPointsPerMatch = stats.numMatches > 0 ? stats.totalMatchPoints / stats.numMatches : null;
  final oppAvgPointsPerMatch = stats.numMatches > 0 ? stats.totalOpponentMatchPoints / stats.numMatches : null;

  final bids = "${stats.numBidsMade}/${stats.numBidsAttempted}";
  final nilBids = "${stats.numNilBidsMade}/${stats.numNilBidsAttempted}";
  final averageBid = stats.numBidsAttempted > 0 ? stats.totalBids / stats.numBidsAttempted : null;
  final avgBags = stats.numRoundsWithBagsEnabled > 0 ? stats.totalBagsTaken / stats.numRoundsWithBagsEnabled : null;

  final oppBids = "${stats.numOpponentBidsMade}/${stats.numOpponentBidsAttempted}";
  final oppNilBids = "${stats.numOpponentNilBidsMade}/${stats.numOpponentNilBidsAttempted}";
  final oppAverageBid = stats.numOpponentBidsAttempted > 0 ? stats.totalOpponentBids / stats.numOpponentBidsAttempted : null;
  final oppAvgBags = stats.numRoundsWithBagsEnabled > 0 ? stats.totalOpponentBagsTaken / stats.numRoundsWithBagsEnabled : null;

  return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      defaultColumnWidth: const IntrinsicColumnWidth(),
      children: [
        statsTableRow("Matches played", stats.numMatches.toString()),
        statsTableRow("Matches won", stats.matchesWon.toString()),
        statsTableRow("Average points/match", avgPointsPerMatch?.toStringAsFixed(1) ?? "--"),
        statsTableRow("Opp. average points/match", oppAvgPointsPerMatch?.toStringAsFixed(1) ?? "--"),
        statsTableRow("Bids made/attempted", bids),
        statsTableRow("Average bid", averageBid?.toStringAsFixed(2) ?? "--"),
        statsTableRow("Nil made/attempted", nilBids),
        statsTableRow("Average bags", avgBags?.toStringAsFixed(2) ?? "--"),
        statsTableRow("Opp. bids made/attempted", oppBids),
        statsTableRow("Opp. average bid", oppAverageBid?.toStringAsFixed(2) ?? "--"),
        statsTableRow("Opp. nil made/attempted", oppNilBids),
        statsTableRow("Opp. average bags", oppAvgBags?.toStringAsFixed(2) ?? "--"),
      ]);
}