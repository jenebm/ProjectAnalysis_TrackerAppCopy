import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/gacha_event.dart';
import '../models/games.dart';
import '../services/settings_store.dart';
import 'importer.dart';

// gryphline first, then the daydreamer-json mirror on github
class EndfieldImporter implements EventImporter {
  EndfieldImporter(this.region, {this.versionEnd});

  final ServerRegion region;
  final DateTime? versionEnd;
  String _source = 'Endfield in-game bulletins';

  // asia utc+8, americas/europe utc-5
  int get utcOffsetHours => region == ServerRegion.asia ? 8 : -5;

  static final _official = Uri.https('game-hub.gryphline.com', '/bulletin/v2/aggregate', {
    'lang': 'en-us',
    'platform': 'Windows',
    'channel': '6',
    'type': '0',
    'code': 'endfield_U35PW8',
    'hideDetail': '0',
    'server': '3',
  });

  static final _mirror = Uri.parse(
    'https://raw.githubusercontent.com/daydreamer-json/ak-endfield-api-archive/'
    'archive/output/akEndfield/gameHub/bulletin/6/3/game/en-us/latest.json',
  );

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36';

  @override
  String get game => Games.endfield;

  @override
  String get sourceLabel => _source;

  @override
  Future<List<ImportCandidate>> fetch() async {
    Map<String, dynamic> data;
    try {
      data = await _load(_official);
      _source = 'Endfield in-game bulletins';
    } catch (_) {
      data = await _load(_mirror);
      _source = 'Endfield bulletins (community mirror)';
    }
    return parseBulletins(data, utcOffsetHours: utcOffsetHours, versionEnd: versionEnd);
  }

  Future<Map<String, dynamic>> _load(Uri uri) async {
    final res = await http
        .get(uri, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw ImportException('Server returned HTTP ${res.statusCode}.');
    }
    var body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    // mirror wraps it as {req, rsp}
    final rsp = body['rsp'];
    if (rsp is Map<String, dynamic>) body = rsp;
    if (body['code'] != 0) throw ImportException('API error ${body['code']}.');
    final data = body['data'];
    if (data is! Map<String, dynamic> || data['list'] is! List) {
      throw ImportException('Unexpected response format.');
    }
    return data;
  }

  // public for tests
  static List<ImportCandidate> parseBulletins(
    Map<String, dynamic> data, {
    required int utcOffsetHours,
    DateTime? now,
    DateTime? versionEnd,
  }) {
    final current = now ?? DateTime.now();
    final out = <ImportCandidate>[];

    for (final it in (data['list'] as List).whereType<Map<String, dynamic>>()) {
      if (it['tab'] != 'events') continue;

      final title = (it['title'] as String? ?? '')
          .replaceAll(RegExp(r'\s*(\\n|\n)\s*'), ' - ')
          .trim();
      if (title.isEmpty) continue;

      final html = ((it['data'] as Map?)?['html'] as String?) ?? '';
      final published = DateTime.fromMillisecondsSinceEpoch(
        ((it['startAt'] as num?)?.toInt() ?? 0) * 1000,
      );
      final (parsedStart, rangeEnd, untilVersion) =
          findRange(htmlToText(html), utcOffsetHours);

      final start = parsedStart ?? published;
      // "before version update" means use the version end from settings
      final parsedEnd = rangeEnd ??
          (untilVersion && versionEnd != null && versionEnd.isAfter(start)
              ? versionEnd
              : null);
      // no dates = usually permanent info, skip old ones
      if (parsedEnd == null && current.difference(start).inDays > 45) continue;

      var end = parsedEnd ?? start.add(const Duration(days: 21));
      var needsReview = parsedEnd == null;
      if (!end.isAfter(start)) {
        end = start.add(const Duration(days: 21));
        needsReview = true;
      }
      if (end.isBefore(current)) continue;

      final lower = title.toLowerCase();
      final isBanner = lower.contains('headhunting') || lower.contains('issue');
      final isCharacter = lower.contains('headhunting') && !lower.contains('basic');

      out.add(ImportCandidate(
        sourceId: 'endfield:${it['cid']}',
        game: Games.endfield,
        name: title,
        start: start,
        end: end,
        kind: isBanner ? EventKind.banner : EventKind.event,
        imageUrl: RegExp(r'<img[^>]+src="([^"]+)"').firstMatch(html)?.group(1),
        category: needsReview ? 'End date not announced' : null,
        needsReview: needsReview,
        isCharacterBanner: isCharacter,
      ));
    }

    out.sort((a, b) => a.end.compareTo(b.end));
    return out;
  }

  static String htmlToText(String html) => html
      .replaceAll(
        RegExp(r'<br\s*/?>|</p>|</div>|</li>|</h\d>', caseSensitive: false),
        '\n',
      )
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  static final _header = RegExp(
    r'(Event Time|Availability|Event Period|Duration|Time)\s*:?',
    caseSensitive: false,
  );

  static final _rangeSep = RegExp(r'\s[–—-]\s|\s*[–—~]\s*');

  // "Sept. 16, 2026 at 12:00"
  static final _date = RegExp(
    r'\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})'
    r'(?:,?\s*(?:at\s+)?(\d{1,2}):(\d{2}))?',
    caseSensitive: false,
  );

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  // flag = end is "before version update"
  // dates only exist inside the post html, there's no field for them, and every post
  // formats the header slightly differently (Event Time / Availability / Duration...)
  static (DateTime?, DateTime?, bool) findRange(String text, int utcOffsetHours) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    for (var i = 0; i < lines.length; i++) {
      final header = _header.firstMatch(lines[i]);
      if (header == null) continue;

      final candidates = [
        lines[i].substring(header.end),
        if (i + 1 < lines.length) lines[i + 1],
      ];
      for (final raw in candidates) {
        final cand = raw.replaceAll(RegExp(r'^[\s:·]+|[\s:·]+$'), '');
        if (cand.isEmpty) continue;
        final sep = _rangeSep.firstMatch(cand);
        if (sep == null && !_date.hasMatch(cand)) continue;

        final left = sep == null ? cand : cand.substring(0, sep.start);
        final right = sep == null ? null : cand.substring(sep.end);
        final end = right == null ? null : _parseDate(right, utcOffsetHours);
        return (
          _parseDate(left, utcOffsetHours),
          end,
          end == null && right != null && right.toLowerCase().contains('version'),
        );
      }
    }
    return (null, null, false);
  }

  static DateTime? _parseDate(String s, int utcOffsetHours) {
    final m = _date.firstMatch(s);
    if (m == null) return null;
    final month = _months[m[1]!.substring(0, 3).toLowerCase()]!;
    return DateTime.utc(
      int.parse(m[3]!),
      month,
      int.parse(m[2]!),
      m[4] == null ? 0 : int.parse(m[4]!),
      m[5] == null ? 0 : int.parse(m[5]!),
    ).subtract(Duration(hours: utcOffsetHours)).toLocal();
  }
}
