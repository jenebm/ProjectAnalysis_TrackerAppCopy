import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/timezone.dart' as tz;

import '../importers/registry.dart';
import '../utils/format.dart';

enum ServerRegion { americas, europe, asia }

extension ServerRegionInfo on ServerRegion {
  String get label {
    if (this == ServerRegion.americas) return 'Americas';
    if (this == ServerRegion.europe) return 'Europe';
    return 'Asia';
  }
}

class SettingsStore extends ChangeNotifier {
  ServerRegion _region = ServerRegion.americas;
  Set<String> _autoGames = {...autoImportGames};
  String? _displayZone;
  final Map<String, DateTime> _versionEnds = {};
  File? _file;

  // only matters for hoyo
  ServerRegion get region => _region;

  String? get displayZone => _displayZone;

  // for posts that only say "until the version update"
  DateTime? versionEnd(String game) => _versionEnds[game];

  Set<String> get autoGames => Set.unmodifiable(_autoGames);

  Future<void> load() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'settings.json'));
    _file = file;
    if (await file.exists()) {
      try {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _region = ServerRegion.values.firstWhere(
          (r) => r.name == json['region'],
          orElse: () => ServerRegion.americas,
        );
        _applyZone(json['displayZone'] as String?);
        final ends = json['versionEnds'];
        if (ends is Map) {
          ends.forEach((game, iso) {
            final t = iso is String ? DateTime.tryParse(iso) : null;
            if (game is String && t != null) _versionEnds[game] = t.toLocal();
          });
        }
        final auto = json['autoGames'];
        if (auto is List) {
          _autoGames = auto.whereType<String>().where(autoImportGames.contains).toSet();
        }
      } catch (e) {
        debugPrint('settings.json read failed: $e');
      }
    }
    notifyListeners();
  }

  Future<void> setRegion(ServerRegion region) async {
    if (region == _region) return;
    _region = region;
    notifyListeners();
    await _save();
  }

  Future<void> setVersionEnd(String game, DateTime end) async {
    _versionEnds[game] = end;
    notifyListeners();
    await _save();
  }

  Future<void> setDisplayZone(String? zone) async {
    _applyZone(zone);
    notifyListeners();
    await _save();
  }

  void _applyZone(String? zone) {
    try {
      displayLocation = zone == null ? null : tz.getLocation(zone);
      _displayZone = zone;
    } catch (_) {
      displayLocation = null;
      _displayZone = null;
    }
  }

  Future<void> setAutoGame(String game, bool enabled) async {
    if (enabled) {
      _autoGames.add(game);
    } else {
      _autoGames.remove(game);
    }
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    await _file?.writeAsString(
      jsonEncode({
        'region': _region.name,
        'autoGames': _autoGames.toList(),
        'displayZone': _displayZone,
        'versionEnds': _versionEnds
            .map((game, end) => MapEntry(game, end.toUtc().toIso8601String())),
      }),
      flush: true,
    );
  }
}
