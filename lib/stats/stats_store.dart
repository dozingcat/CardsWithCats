import '../hearts/hearts_stats.dart';
import '../ohhell/ohhell_stats.dart';
import '../spades/spades_stats.dart';

abstract class StatsStore {
  Future<HeartsStats?> readHeartsStats();
  Future<void> writeHeartsStats(final HeartsStats stats);

  Future<SpadesStats?> readSpadesStats();
  Future<void> writeSpadesStats(final SpadesStats stats);

  Future<OhHellStats?> readOhHellStats();
  Future<void> writeOhHellStats(final OhHellStats stats);
}

class InMemoryStatsStore implements StatsStore {
  HeartsStats heartsStats = HeartsStats.empty();
  SpadesStats spadesStats = SpadesStats.empty();
  OhHellStats ohHellStats = OhHellStats.empty();

  @override Future<HeartsStats?> readHeartsStats() async {
    return heartsStats;
  }
  @override Future<void> writeHeartsStats(HeartsStats stats) async {
    heartsStats = stats;
  }

  @override Future<SpadesStats?> readSpadesStats() async {
    return spadesStats;
  }
  @override Future<void> writeSpadesStats(SpadesStats stats) async {
    spadesStats = stats;
  }

  @override Future<OhHellStats?> readOhHellStats() async {
    return ohHellStats;
  }
  @override Future<void> writeOhHellStats(OhHellStats stats) async {
    ohHellStats = stats;
  }
}