import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../models/gacha_event.dart';
import 'event_store.dart';

class BackupResult {
  const BackupResult({this.added = 0, this.updated = 0, this.skipped = 0, this.failed = 0});
  final int added;
  final int updated;
  final int skipped;
  final int failed;
}

// Pictures are embedded in the file, newest edit wins on merge
// TODO deletes don't carry over
class BackupService {
  static const _format = 'gacha-tracker-backup';

  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  static Future<Uint8List> build(EventStore store) async {
    final events = <Map<String, dynamic>>[];
    for (final e in store.events) {
      final json = e.toJson();
      final path = e.imagePath;
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          json['imageData'] = base64Encode(await file.readAsBytes());
          json['imageExt'] = p.extension(path);
        }
      }
      events.add(json);
    }
    final doc = {
      'format': _format,
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'events': events,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(doc)));
  }

  static Future<String?> exportFile(EventStore store) async {
    final bytes = await build(store);
    final name = 'gacha-tracker-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save backup',
      fileName: name,
      type: _isMobile ? FileType.any : FileType.custom,
      allowedExtensions: _isMobile ? null : const ['json'],
      bytes: bytes,
    );
    if (path == null) return null;
    if (!_isMobile) await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  static Future<BackupResult?> importFile(EventStore store) async {
    final picked = await FilePicker.platform.pickFiles(
      type: _isMobile ? FileType.any : FileType.custom,
      allowedExtensions: _isMobile ? null : const ['json'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;

    final file = picked.files.first;
    final bytes = file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null) throw const FormatException("Couldn't read that file.");

    final Object? doc;
    try {
      doc = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const FormatException("That file isn't a Gacha Tracker backup.");
    }
    if (doc is! Map || doc['format'] != _format || doc['events'] is! List) {
      throw const FormatException("That file isn't a Gacha Tracker backup.");
    }

    var added = 0, updated = 0, skipped = 0, failed = 0;
    final incoming = <GachaEvent>[];
    for (final raw in (doc['events'] as List).whereType<Map>()) {
      final json = Map<String, dynamic>.from(raw);
      final imageData = json.remove('imageData');
      final imageExt = json.remove('imageExt');

      final GachaEvent event;
      try {
        event = GachaEvent.fromJson(json);
      } catch (_) {
        failed++;
        continue;
      }

      final existing = store.byId(event.id);
      if (existing != null && !event.updatedAt.isAfter(existing.updatedAt)) {
        skipped++;
        continue;
      }

      String? imagePath;
      if (imageData is String) {
        imagePath = await store.storeImageBytes(
          base64Decode(imageData),
          imageExt is String ? imageExt : '.png',
        );
      }
      incoming.add(event.withImagePath(imagePath));
      if (existing == null) {
        added++;
      } else {
        updated++;
      }
    }

    if (incoming.isNotEmpty) await store.putAll(incoming);
    return BackupResult(added: added, updated: updated, skipped: skipped, failed: failed);
  }
}
