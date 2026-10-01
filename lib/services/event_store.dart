import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/gacha_event.dart';
import 'notification_service.dart';

class EventStore extends ChangeNotifier {
  static const _uuid = Uuid();

  final _events = <GachaEvent>[];
  // Imported events the user deleted, auto import skips these
  final _dismissed = <String>{};
  File? _file;
  File? _dismissedFile;
  Directory? _imagesDir;

  List<GachaEvent> get events => List.unmodifiable(_events);

  String newId() => _uuid.v4();

  GachaEvent? byId(String id) {
    for (final e in _events) {
      if (e.id == id) return e;
    }
    return null;
  }

  bool hasSource(String sourceId) =>
      _events.any((e) => e.sourceId == sourceId);

  GachaEvent? bySource(String sourceId) {
    for (final e in _events) {
      if (e.sourceId == sourceId) return e;
    }
    return null;
  }

  bool isDismissed(String sourceId) => _dismissed.contains(sourceId);

  Future<void> load() async {
    final dir = await getApplicationSupportDirectory();
    _file = File(p.join(dir.path, 'events.json'));
    _imagesDir = Directory(p.join(dir.path, 'images'));
    _dismissedFile = File(p.join(dir.path, 'dismissed.json'));
    try {
      if (await _dismissedFile!.exists()) {
        final raw = jsonDecode(await _dismissedFile!.readAsString()) as List<dynamic>;
        _dismissed.addAll(raw.whereType<String>());
      }
    } catch (e) {
      debugPrint('dismissed.json read failed: $e');
    }
    await _imagesDir!.create(recursive: true);

    final file = _file!;
    if (await file.exists()) {
      try {
        final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
        _events
          ..clear()
          ..addAll(raw.map((e) => GachaEvent.fromJson(e as Map<String, dynamic>)));
      } catch (e) {
        debugPrint('events.json read failed: $e');
      }
    }
    notifyListeners();

    for (final e in _events) {
      unawaited(NotificationService.instance.schedule(e));
    }
  }

  Future<void> upsert(GachaEvent event) async {
    final i = _events.indexWhere((e) => e.id == event.id);
    if (i >= 0) {
      final old = _events[i];
      if (old.imagePath != null && old.imagePath != event.imagePath) {
        await _deleteImage(old.imagePath);
      }
      _events[i] = event;
    } else {
      _events.add(event);
    }
    final source = event.sourceId;
    if (source != null && _dismissed.remove(source)) await _saveDismissed();
    notifyListeners();
    await _save();
    await NotificationService.instance.schedule(event);
  }

  Future<void> delete(String id, {bool dismiss = true}) async {
    final i = _events.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final removed = _events.removeAt(i);
    final source = removed.sourceId;
    if (source != null && dismiss) {
      _dismissed.add(source);
      await _saveDismissed();
    }
    notifyListeners();
    await _save();
    await _deleteImage(removed.imagePath);
    await NotificationService.instance.cancelFor(id);
  }

  Future<String> storeImage(String sourcePath) async {
    final ext = p.extension(sourcePath).isEmpty ? '.png' : p.extension(sourcePath);
    final dest = p.join(_imagesDir!.path, '${_uuid.v4()}$ext');
    await File(sourcePath).copy(dest);
    return dest;
  }

  Future<String> storeImageBytes(List<int> bytes, String ext) async {
    final dest = p.join(_imagesDir!.path, '${_uuid.v4()}$ext');
    await File(dest).writeAsBytes(bytes, flush: true);
    return dest;
  }

  Future<void> putAll(List<GachaEvent> incoming) async {
    for (final event in incoming) {
      final i = _events.indexWhere((e) => e.id == event.id);
      if (i >= 0) {
        final old = _events[i];
        if (old.imagePath != null && old.imagePath != event.imagePath) {
          await _deleteImage(old.imagePath);
        }
        _events[i] = event;
      } else {
        _events.add(event);
      }
    }
    notifyListeners();
    await _save();
    for (final e in incoming) {
      await NotificationService.instance.schedule(e);
    }
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    final json = jsonEncode(_events.map((e) => e.toJson()).toList());
    await file.writeAsString(json, flush: true);
  }

  Future<void> _saveDismissed() async {
    await _dismissedFile?.writeAsString(jsonEncode(_dismissed.toList()), flush: true);
  }

  Future<void> _deleteImage(String? path) async {
    if (path == null) return;
    try {
      await File(path).delete();
    } catch (_) {}
  }
}
