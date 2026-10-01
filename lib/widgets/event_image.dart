import 'dart:io';

import 'package:flutter/material.dart';

import '../models/games.dart';

class EventImage extends StatelessWidget {
  const EventImage({super.key, required this.game, this.filePath, this.url});

  final String game;
  final String? filePath;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final path = filePath;
    if (path != null && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => GamePlaceholder(game: game),
      );
    }
    final u = url;
    if (u != null && u.isNotEmpty) {
      return Image.network(
        u,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => GamePlaceholder(game: game),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : GamePlaceholder(game: game),
      );
    }
    return GamePlaceholder(game: game);
  }
}

class GamePlaceholder extends StatelessWidget {
  const GamePlaceholder({super.key, required this.game});

  final String game;

  @override
  Widget build(BuildContext context) {
    final c = Games.color(game);
    return ColoredBox(
      color: Color.lerp(c, Colors.black, 0.75)!,
      child: Center(
        child: Text(
          Games.short(game),
          style: TextStyle(fontSize: 28, color: c.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}
