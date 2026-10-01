import '../models/gacha_event.dart';

class ImportCandidate {
  const ImportCandidate({
    required this.sourceId,
    required this.game,
    required this.name,
    required this.start,
    required this.end,
    this.kind = EventKind.event,
    this.imageUrl,
    this.category,
    this.needsReview = false,
    this.isCharacterBanner = false,
  });

  final String sourceId;
  final String game;
  final String name;
  final DateTime start;
  final DateTime end;
  final EventKind kind;
  final String? imageUrl;
  final String? category;
  final bool needsReview; // dates guessed from text
  final bool isCharacterBanner;
}

abstract class EventImporter {
  String get game;
  String get sourceLabel;
  Future<List<ImportCandidate>> fetch();
}

class ImportException implements Exception {
  ImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

extension CandidateToEvent on ImportCandidate {
  GachaEvent toEvent(String id) => GachaEvent(
        id: id,
        game: game,
        name: name,
        start: start,
        end: end,
        kind: kind,
        imageUrl: imageUrl,
        sourceId: sourceId,
        endEstimated: needsReview,
      );
}
