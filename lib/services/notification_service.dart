import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/gacha_event.dart';

// android only, on windows the countdown just turns red
// TODO windows notifications?
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (!Platform.isAndroid) return;
    try {
      tzdata.initializeTimeZones();
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings);
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      // Everything gets rescheduled on load anyway
      await _plugin.cancelAll();
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'event_reminders',
      'Event reminders',
      channelDescription: 'Reminders before gacha events start or end',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<void> schedule(GachaEvent e) async {
    if (!_ready) return;
    final base = _baseId(e.id);
    final now = DateTime.now();
    try {
      await cancelFor(e.id);
      Future<void> at(int id, DateTime when, String title) async {
        if (!when.isAfter(now)) return;
        await _plugin.zonedSchedule(
          id,
          title,
          e.game,
          tz.TZDateTime.from(when.toUtc(), tz.UTC),
          _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }

      // Skip this one if the end date is a guess
      if (!e.endEstimated) {
        await at(base, e.end.subtract(const Duration(hours: 24)),
            '${e.name} ends in 24 hours');
      }
      await at(base + 1, e.start, '${e.name} is live');
    } catch (err) {
      debugPrint('Failed to schedule reminder: $err');
    }
  }

  Future<void> cancelFor(String eventId) async {
    if (!_ready) return;
    final base = _baseId(eventId);
    await _plugin.cancel(base);
    await _plugin.cancel(base + 1);
  }

  int _baseId(String id) => (id.hashCode & 0x3fffffff) * 2;
}
