import '../bridge/bridge_stats.dart';
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

  Future<BridgeStats?> readBridgeStats();
  Future<void> writeBridgeStats(final BridgeStats stats);
}

class InMemoryStatsStore implements StatsStore {
  HeartsStats heartsStats = HeartsStats.empty();
  SpadesStats spadesStats = SpadesStats.empty();
  OhHellStats ohHellStats = OhHellStats.empty();
  BridgeStats bridgeStats = BridgeStats.empty();

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

  @override Future<BridgeStats?> readBridgeStats() async {
    return bridgeStats;
  }
  @override Future<void> writeBridgeStats(BridgeStats stats) async {
    bridgeStats = stats;
  }
}