import 'package:flutter_test/flutter_test.dart';
import 'package:gacha_tracker/importers/endfield_importer.dart';
import 'package:gacha_tracker/importers/limbus_importer.dart';

void main() {
  test('limbus kst range', () {
    final posted = DateTime.utc(2026, 5, 20);
    final dates = LimbusImporter.extractDates(
      'Period: 2026.05.21 (Thu) 10:00 ~ 2026.06.04 (Thu) 02:00 (KST)',
      posted,
    );
    expect(dates.length, 2);
    expect(dates[0].toUtc(), DateTime.utc(2026, 5, 21, 1));
    expect(dates[1].toUtc(), DateTime.utc(2026, 6, 3, 17));
  });

  test('limbus dates without a year', () {
    final posted = DateTime.utc(2026, 12, 20);
    final dates = LimbusImporter.extractDates('01/08 10:00 ~ 01/22 02:00', posted);
    expect(dates.first.toUtc(), DateTime.utc(2027, 1, 8, 1));
  });

  test('endfield fixed range', () {
    final (start, end, _) = EndfieldImporter.findRange(
      '▼// Event Time\nSept. 16, 2026 at 12:00 – Sept. 30, 2026 at 16:00 (server time)',
      -5,
    );
    expect(start!.toUtc(), DateTime.utc(2026, 9, 16, 17));
    expect(end!.toUtc(), DateTime.utc(2026, 9, 30, 21));
  });

  test('endfield open start / version end', () {
    final (s1, e1, v1) = EndfieldImporter.findRange(
      '· Availability: After v1.1 version release – Sept. 30, 2026, 11:59 (server time)',
      -5,
    );
    expect(s1, isNull);
    expect(e1!.toUtc(), DateTime.utc(2026, 9, 30, 16, 59));
    expect(v1, isFalse);

    final (s2, e2, v2) = EndfieldImporter.findRange(
      '▼// Event Time\nOct. 1, 2026 at 12:00 (server time) – Before version update and maintenance',
      8,
    );
    expect(s2!.toUtc(), DateTime.utc(2026, 10, 1, 4));
    expect(e2, isNull);
    expect(v2, isTrue);
  });

  test('endfield parseBulletins', () {
    final data = {
      'list': [
        {
          'cid': '1',
          'tab': 'events',
          'title': r'Winter Hunt\nChartered Headhunting',
          'startAt': DateTime.utc(2026, 9, 1).millisecondsSinceEpoch ~/ 1000,
          'data': {
            'html': '<p><img src="https://example.com/a.jpg"></p>'
                '<p>· Availability: After update – Sept. 30, 2026, 11:59 (server time)</p>',
          },
        },
        {'cid': '2', 'tab': 'news', 'title': 'Merch', 'startAt': 0, 'data': {}},
      ],
    };
    final out = EndfieldImporter.parseBulletins(
      data,
      utcOffsetHours: -5,
      now: DateTime.utc(2026, 9, 10),
    );
    expect(out.length, 1);
    expect(out.first.name, 'Winter Hunt - Chartered Headhunting');
    expect(out.first.imageUrl, 'https://example.com/a.jpg');
    expect(out.first.needsReview, isFalse);
    expect(out.first.isCharacterBanner, isTrue);
  });
}
