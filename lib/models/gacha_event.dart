import 'games.dart';

enum EventKind { banner, event, other }

extension EventKindLabel on EventKind {
  String get label {
    switch (this) {
      case EventKind.banner:
        return 'Banner';
      case EventKind.event:
        return 'Event';
      case EventKind.other:
        return 'Other';
    }
  }
}

class GachaEvent {
  GachaEvent({
    required this.id,
    required this.game,
    required this.name,
    required this.start,
    required this.end,
    this.kind = EventKind.event,
    this.imagePath,
    this.imageUrl,
    this.notes,
    this.sourceId,
    this.endEstimated = false,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String game;
  final String name;
  final DateTime start;
  final DateTime end;
  final EventKind kind;
  final String? imagePath; // copied into app storage
  final String? imageUrl;
  final String? notes;
  final String? sourceId; // importer id, null if added by hand
  final bool endEstimated;
  final DateTime updatedAt;

  GachaEvent copyWith({DateTime? end, bool? endEstimated}) => GachaEvent(
        id: id,
        game: game,
        name: name,
        start: start,
        end: end ?? this.end,
        kind: kind,
        imagePath: imagePath,
        imageUrl: imageUrl,
        notes: notes,
        sourceId: sourceId,
        endEstimated: endEstimated ?? this.endEstimated,
      );

  GachaEvent withImagePath(String? path) => GachaEvent(
        id: id,
        game: game,
        name: name,
        start: start,
        end: end,
        kind: kind,
        imagePath: path,
        imageUrl: imageUrl,
        notes: notes,
        sourceId: sourceId,
        endEstimated: endEstimated,
        updatedAt: updatedAt,
      );

  bool isUpcomingAt(DateTime now) => now.isBefore(start);
  bool isEndedAt(DateTime now) => !now.isBefore(end);
  bool isActiveAt(DateTime now) => !isUpcomingAt(now) && !isEndedAt(now);

  double progressAt(DateTime now) {
    final total = end.difference(start).inSeconds;
    if (total <= 0) return 1;
    return (now.difference(start).inSeconds / total).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'game': game,
        'name': name,
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
        'kind': kind.name,
        'imagePath': imagePath,
        'imageUrl': imageUrl,
        'notes': notes,
        'sourceId': sourceId,
        'endEstimated': endEstimated,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory GachaEvent.fromJson(Map<String, dynamic> j) => GachaEvent(
        id: j['id'] as String,
        game: j['game'] as String,
        name: j['name'] as String,
        start: DateTime.parse(j['start'] as String).toLocal(),
        end: DateTime.parse(j['end'] as String).toLocal(),
        kind: EventKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => EventKind.event,
        ),
        imagePath: j['imagePath'] as String?,
        imageUrl: j['imageUrl'] as String?,
        notes: j['notes'] as String?,
        sourceId: j['sourceId'] as String?,
        endEstimated: j['endEstimated'] == true,
        // old saves without this field
        updatedAt: j['updatedAt'] is String
            ? DateTime.parse(j['updatedAt'] as String).toLocal()
            : DateTime.fromMillisecondsSinceEpoch(0),
      );
}
