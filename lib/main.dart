import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'screens/home_screen.dart';
import 'services/event_store.dart';
import 'services/notification_service.dart';
import 'services/settings_store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  await NotificationService.instance.init();
  final settings = SettingsStore();
  final store = EventStore();
  await Future.wait([settings.load(), store.load()]);
  runApp(GachaTrackerApp(store: store, settings: settings));
}

class GachaTrackerApp extends StatelessWidget {
  const GachaTrackerApp({super.key, required this.store, required this.settings});

  final EventStore store;
  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gacha Tracker',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomeScreen(store: store, settings: settings),
    );
  }
}
