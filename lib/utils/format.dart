import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

tz.Location? displayLocation;

DateTime toDisplay(DateTime instant) {
  final loc = displayLocation;
  return loc == null ? instant.toLocal() : tz.TZDateTime.from(instant, loc);
}

DateTime fromDisplay(int year, int month, int day, int hour, int minute) {
  final loc = displayLocation;
  if (loc == null) return DateTime(year, month, day, hour, minute);
  final t = tz.TZDateTime(loc, year, month, day, hour, minute);
  return DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch);
}

String zoneAbbr(DateTime instant) {
  final name = toDisplay(instant).timeZoneName;
  if (!name.contains(' ')) return name;
  return name
      .split(RegExp(r'[\s-]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase())
      .join();
}

String formatRemaining(Duration duration) {
  final d = duration.isNegative ? Duration.zero : duration;
  final days = d.inDays;
  final hours = d.inHours % 24;
  final mins = d.inMinutes % 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${mins}m';
  return '${mins}m';
}

final _day = DateFormat('MMM d');
final _dateTime = DateFormat('EEE, MMM d, h:mm a');
final _dayTime = DateFormat('MMM d, h:mm a');

String formatDay(DateTime instant) => _day.format(toDisplay(instant));

String formatDateTime(DateTime instant) =>
    '${_dateTime.format(toDisplay(instant))} ${zoneAbbr(instant)}';

String formatRange(DateTime start, DateTime end, {bool endEstimated = false}) =>
    '${_dayTime.format(toDisplay(start))} - '
    '${endEstimated ? 'est. ' : ''}${_dayTime.format(toDisplay(end))} ${zoneAbbr(end)}';
