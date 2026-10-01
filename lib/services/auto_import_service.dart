import 'package:flutter/foundation.dart';

import '../importers/importer.dart';
import '../importers/registry.dart';
import '../models/gacha_event.dart';
import 'event_store.dart';
import 'settings_store.dart';

class AutoImportService {
  AutoImportService(this.store, this.settings);

  final EventStore store;
  final SettingsStore settings;

  DateTime? _lastRun;
  bool _running = false;

  Future<int> run({bool force = false}) async {
    final now = DateTime.now();
    if (_running) return 0;
    if (!force && _lastRun != null && now.difference(_lastRun!).inMinutes < 60) {
      return 0;
    }
    _running = true;
    _lastRun = now;
    try {
      final lists = await Future.wait(
        settings.autoGames.map((game) => _safeFetch(importerFor(game, settings))),
      );

      var added = 0;
      final changes = <GachaEvent>[];
      for (final c in lists.expand((l) => l)) {
        if (!c.isCharacterBanner || store.isDismissed(c.sourceId)) continue;
        // limited banners are ~3 weeks, way longer = permanent info
        if (c.end.difference(c.start).inDays > 60) continue;

        final existing = store.bySource(c.sourceId);
        if (existing == null) {
          changes.add(c.toEvent(store.newId()));
          added++;
        } else if (existing.endEstimated && !c.needsReview) {
          changes.add(existing.copyWith(end: c.end, endEstimated: false));
        }
      }

      if (changes.isNotEmpty) await store.putAll(changes);
      return added;
    } finally {
      _running = false;
    }
  }

  Future<List<ImportCandidate>> _safeFetch(EventImporter? importer) async {
    if (importer == null) return const [];
    try {
      return await importer.fetch();
    } catch (e) {
      debugPrint('Auto-import failed for ${importer.game}: $e');
      return const [];
    }
  }
}
