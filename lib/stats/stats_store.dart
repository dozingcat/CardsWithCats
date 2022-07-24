import '../hearts/hearts_stats.dart';
import '../spades/spades_stats.dart';

abstract class StatsStore {
  Future<HeartsStats?> readHeartsStats();
  Future<void> writeHeartsStats(final HeartsStats stats);

  Future<SpadesStats?> readSpadesStats();
  Future<void> writeSpadesStats(final SpadesStats stats);
}

class InMemoryStatsStore implements StatsStore {
  HeartsStats heartsStats = HeartsStats.empty();
  SpadesStats spadesStats = SpadesStats.empty();

  @override Future<HeartsStats?> readHeartsStats() async {
    return heartsStats;
  }

  @override Future<SpadesStats?> readSpadesStats() async {
    return spadesStats;
  }

  @override Future<void> writeHeartsStats(HeartsStats stats) async {
    heartsStats = stats;
  }

  @override Future<void> writeSpadesStats(SpadesStats stats) async {
    spadesStats = stats;
  }
}