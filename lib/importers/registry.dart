import '../models/games.dart';
import '../services/settings_store.dart';
import 'endfield_importer.dart';
import 'hoyoverse_importer.dart';
import 'importer.dart';
import 'limbus_importer.dart';

const importableGames = [
  Games.genshin,
  Games.starRail,
  Games.zenless,
  Games.endfield,
  Games.limbus,
];

const autoImportGames = [
  Games.genshin,
  Games.starRail,
  Games.zenless,
  Games.endfield,
];

EventImporter? importerFor(String game, SettingsStore settings) {
  final region = settings.region;
  return switch (game) {
    Games.genshin => HoyoverseImporter(HoyoverseImporter.genshin, region),
    Games.starRail => HoyoverseImporter(HoyoverseImporter.starRail, region),
    Games.zenless => HoyoverseImporter(HoyoverseImporter.zenless, region),
    Games.endfield => EndfieldImporter(region, versionEnd: settings.versionEnd(game)),
    Games.limbus => LimbusImporter(),
    _ => null,
  };
}
