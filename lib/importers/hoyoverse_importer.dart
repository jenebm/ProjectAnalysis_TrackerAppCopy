import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/gacha_event.dart';
import '../models/games.dart';
import '../services/settings_store.dart';
import 'importer.dart';

class HoyoverseGame {
  const HoyoverseGame({
    required this.game,
    required this.host,
    required this.biz,
    required this.code,
    required this.level,
    required this.regions,
    required this.bannerWords,
    required this.characterWords,
    required this.notCharacterWords,
  });

  final String game;
  final String host;
  final String biz;
  final String code;
  final int level;
  final Map<ServerRegion, (String, int)> regions; // server id, utc offset
  final List<String> bannerWords;
  // has a characterWord and no notCharacterWord
  final List<String> characterWords;
  final List<String> notCharacterWords;
}

// genshin/hsr/zzz feed, unofficial so it might break
class HoyoverseImporter implements EventImporter {
  HoyoverseImporter(this.config, this.region);

  final HoyoverseGame config;
  final ServerRegion region;

  static const genshin = HoyoverseGame(
    game: Games.genshin,
    host: 'sg-hk4e-api.hoyoverse.com',
    biz: 'hk4e_global',
    code: 'hk4e',
    level: 60,
    regions: {
      ServerRegion.americas: ('os_usa', -5),
      ServerRegion.europe: ('os_euro', 1),
      ServerRegion.asia: ('os_asia', 8),
    },
    bannerWords: ['wish'],
    characterWords: ['event wish'],
    notCharacterWords: ['epitome invocation', 'chronicled'],
  );

  static const starRail = HoyoverseGame(
    game: Games.starRail,
    host: 'sg-hkrpg-api.hoyoverse.com',
    biz: 'hkrpg_global',
    code: 'hkrpg',
    level: 70,
    regions: {
      ServerRegion.americas: ('prod_official_usa', -5),
      ServerRegion.europe: ('prod_official_eur', 1),
      ServerRegion.asia: ('prod_official_asia', 8),
    },
    bannerWords: ['warp'],
    characterWords: ['warp'],
    notCharacterWords: ['light cone'],
  );

  static const zenless = HoyoverseGame(
    game: Games.zenless,
    host: 'sg-announcement-api.hoyoverse.com',
    biz: 'nap_global',
    code: 'nap',
    level: 60,
    regions: {
      ServerRegion.americas: ('prod_gf_us', -5),
      ServerRegion.europe: ('prod_gf_eu', 1),
      ServerRegion.asia: ('prod_gf_jp', 8),
    },
    bannerWords: ['signal search', 'channel'],
    characterWords: ['channel', 'signal search'],
    notCharacterWords: ['w-engine', 'bangboo'],
  );

  @override
  String get game => config.game;

  @override
  String get sourceLabel => '${config.game} in-game announcements';

  @override
  Future<List<ImportCandidate>> fetch() async {
    final (serverId, regionOffset) = config.regions[region]!;
    final uri = Uri.https(
      config.host,
      '/common/${config.biz}/announcement/api/getAnnList',
      {
        'game': config.code,
        'game_biz': config.biz,
        'bundle_id': config.biz,
        'lang': 'en',
        'channel_id': '1',
        'platform': 'pc',
        'region': serverId,
        'level': '${config.level}',
        'uid': '100000000',
      },
    );

    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw ImportException('Server returned HTTP ${res.statusCode}.');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (body['retcode'] != 0) {
      throw ImportException('API error: ${body['message']}');
    }

    final data = body['data'] as Map<String, dynamic>?;
    // feed has its own tz, fall back to server
    final tz = data?['timezone'];
    final offset = tz is num ? tz.toInt() : int.tryParse('$tz') ?? regionOffset;

    final now = DateTime.now();
    final out = <ImportCandidate>[];
    final seen = <String>{};

    // genshin uses data.list, hsr/zzz ALSO have data.pic_list, nested one level deeper,
    // and the same ann_id can show up in both with different fields
    // just walk the whole thing and dedupe
    void walk(Object? node, String? category) {
      if (node is List) {
        for (final n in node) {
          walk(n, category);
        }
        return;
      }
      if (node is! Map) return;
      final label = node['type_label'];
      final cat = label is String && label.trim().isNotEmpty ? label.trim() : category;

      if (node.containsKey('ann_id') && node.containsKey('start_time')) {
        if (seen.add('${node['ann_id']}')) {
          final c = _candidate(node, cat, offset, now);
          if (c != null) out.add(c);
        }
        return;
      }
      for (final v in node.values) {
        if (v is List || v is Map) walk(v, cat);
      }
    }

    walk(data, null);
    out.sort((a, b) => a.end.compareTo(b.end));
    return out;
  }

  ImportCandidate? _candidate(Map a, String? category, int offset, DateTime now) {
    final start = _parse(a['start_time'], offset);
    final end = _parse(a['end_time'], offset);
    if (start == null || end == null || end.isBefore(now)) return null;

    final subtitle = _clean(a['subtitle']);
    final title = _clean(a['title']);
    final name = subtitle.isNotEmpty ? subtitle : title;
    if (name.isEmpty) return null;

    final haystack = '$name $title'.toLowerCase();
    final isBanner = config.bannerWords.any(haystack.contains);
    final isCharacter = config.characterWords.any(haystack.contains) &&
        !config.notCharacterWords.any(haystack.contains);

    String? image;
    for (final key in const ['banner', 'img', 'image', 'pic']) {
      final v = a[key];
      if (v is String && v.trim().startsWith('http')) {
        image = v.trim();
        break;
      }
    }

    return ImportCandidate(
      sourceId: '${config.code}:${a['ann_id']}',
      game: config.game,
      name: name,
      start: start,
      end: end,
      kind: isBanner ? EventKind.banner : EventKind.event,
      imageUrl: image,
      category: category,
      isCharacterBanner: isCharacter,
    );
  }

  // server time string -> local
  static DateTime? _parse(Object? v, int offsetHours) {
    if (v is! String || v.trim().isEmpty) return null;
    final naive = DateTime.tryParse('${v.trim().replaceFirst(' ', 'T')}Z');
    return naive?.subtract(Duration(hours: offsetHours)).toLocal();
  }

  static String _clean(Object? v) => v is String
      ? v.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&nbsp;', ' ').trim()
      : '';
}
