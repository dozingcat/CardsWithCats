import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as Path;

import 'package:cards_with_cats/hearts/hearts_stats.dart';
import 'package:cards_with_cats/spades/spades_stats.dart';
import 'package:cards_with_cats/stats/stats_store.dart';

import '../ohhell/ohhell_stats.dart';

class JsonFileStatsStore implements StatsStore {

  final Directory baseDirectory;

  String heartsPath() => Path.join(baseDirectory.path, "hearts.json");
  String spadesPath() => Path.join(baseDirectory.path, "spades.json");
  String ohHellPath() => Path.join(baseDirectory.path, "ohhell.json");

  JsonFileStatsStore({required this.baseDirectory});

  @override
  Future<HeartsStats?> readHeartsStats() async  {
    final json = await readJsonFromFile(heartsPath());
    if (json != null) {
      return HeartsStats.fromJson(json);
    }
    return null;
  }

  @override
  Future<SpadesStats?> readSpadesStats() async {
    final json = await readJsonFromFile(spadesPath());
        if (json != null) {
      return SpadesStats.fromJson(json);
    }
    return null;
  }

  @override
  Future<OhHellStats?> readOhHellStats() async {
    final json = await readJsonFromFile(ohHellPath());
    if (json != null) {
      return OhHellStats.fromJson(json);
    }
    return null;
  }

  @override
  Future<void> writeHeartsStats(HeartsStats stats) async {
    final file = File(heartsPath());
    print("Writing hearts stats to $file");
    await file.writeAsString(jsonEncode(stats.toJson()), flush: true);
  }

  @override
  Future<void> writeSpadesStats(SpadesStats stats) async {
    final file = File(spadesPath());
    print("Writing spades stats to $file");
    await file.writeAsString(jsonEncode(stats.toJson()), flush: true);
  }

  @override
  Future<void> writeOhHellStats(OhHellStats stats) async {
    final file = File(ohHellPath());
    print("Writing Oh Hell stats to $file");
    await file.writeAsString(jsonEncode(stats.toJson()), flush: true);
  }
}

Future<dynamic> readJsonFromFile(String path) async {
  final file = File(path);
  bool exists = await file.exists();
  if (!exists) return null;
  String content = await File(path).readAsString();
  try {
    return jsonDecode(content);
  } catch (ex) {
    return null;
  }
}