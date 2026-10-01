import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/gacha_event.dart';
import '../models/games.dart';
import 'importer.dart';

// steam news api, dates guessed from text (KST)
// TODO some posts use formats this misses, those just get the 14 day default
class LimbusImporter implements EventImporter {
  static const steamAppId = 1973530;

  static final _uri = Uri.parse(
    'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/'
    '?appid=$steamAppId&count=30&maxlength=0&format=json'
    '&feeds=steam_community_announcements',
  );

  @override
  String get game => Games.limbus;

  @override
  String get sourceLabel => 'Limbus Company Steam announcements';

  @override
  Future<List<ImportCandidate>> fetch() async {
    final res = await http.get(_uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw ImportException('Steam returned HTTP ${res.statusCode}.');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final items = ((body['appnews'] as Map<String, dynamic>?)?['newsitems']
            as List?) ??
        const [];

    final now = DateTime.now();
    final out = <ImportCandidate>[];

    for (final item in items.whereType<Map<String, dynamic>>()) {
      final title = (item['title'] as String? ?? '').trim();
      final rawContents = item['contents'] as String? ?? '';
      final posted = DateTime.fromMillisecondsSinceEpoch(
        ((item['date'] as num?)?.toInt() ?? 0) * 1000,
      );
      if (title.isEmpty || now.difference(posted).inDays > 60) continue;

      final dates = extractDates(_strip(rawContents), posted);
      final start = dates.isNotEmpty ? dates[0] : posted;
      var end = dates.length > 1 ? dates[1] : start.add(const Duration(days: 14));
      if (!end.isAfter(start)) end = start.add(const Duration(days: 14));
      if (end.isBefore(now)) continue;

      final lower = title.toLowerCase();
      final kind = lower.contains('extraction') || lower.contains('banner')
          ? EventKind.banner
          : lower.contains('event')
              ? EventKind.event
              : EventKind.other;

      out.add(ImportCandidate(
        sourceId: 'limbus:${item['gid']}',
        game: game,
        name: title,
        start: start,
        end: end,
        kind: kind,
        imageUrl: _firstImage(rawContents),
        category: 'Steam post',
        needsReview: dates.length < 2,
      ));
    }
    return out;
  }

  // "2026.05.21 (Thu) 10:00"
  static final _full = RegExp(
    r'(20\d{2})[./-]\s?(\d{1,2})[./-]\s?(\d{1,2})\.?'
    r'(?:\s*\([A-Za-z]{2,4}\.?\))?(?:\s*(\d{1,2}):(\d{2}))?',
  );

  // "05.21 (Thu) 10:00", needs the time or it matches random numbers
  static final _short = RegExp(
    r'(?<![\d.])(\d{1,2})[./](\d{1,2})\.?'
    r'(?:\s*\([A-Za-z]{2,4}\.?\))?\s+(\d{1,2}):(\d{2})',
  );

  static List<DateTime> extractDates(String text, DateTime posted) {
    final found = <(int, DateTime)>[];

    for (final m in _full.allMatches(text)) {
      final dt = _kst(
        int.parse(m[1]!),
        int.parse(m[2]!),
        int.parse(m[3]!),
        m[4] == null ? 0 : int.parse(m[4]!),
        m[5] == null ? 0 : int.parse(m[5]!),
      );
      if (dt != null) found.add((m.start, dt));
    }

    for (final m in _short.allMatches(text)) {
      final mo = int.parse(m[1]!);
      final d = int.parse(m[2]!);
      final h = int.parse(m[3]!);
      final mi = int.parse(m[4]!);
      var dt = _kst(posted.year, mo, d, h, mi);
      if (dt != null && dt.isBefore(posted.subtract(const Duration(days: 180)))) {
        dt = _kst(posted.year + 1, mo, d, h, mi);
      }
      if (dt != null) found.add((m.start, dt));
    }

    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final f in found) f.$2];
  }

  static DateTime? _kst(int y, int mo, int d, int h, int mi) {
    if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 24 || mi > 59) return null;
    return DateTime.utc(y, mo, d, h, mi)
        .subtract(const Duration(hours: 9))
        .toLocal();
  }

  static String _strip(String s) => s
      .replaceAll(RegExp(r'\[/?[a-zA-Z0-9*]+(?:[= ][^\]]*)?\]'), ' ')
      .replaceAll(RegExp(r'<[^>]*>'), ' ');

  static String? _firstImage(String contents) {
    final m = RegExp(r'\{STEAM_CLAN_IMAGE\}([^\s\[\]"<>]+)').firstMatch(contents);
    if (m == null) return null;
    return 'https://clan.akamai.steamstatic.com/images${m[1]}';
  }
}
