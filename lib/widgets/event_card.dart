import 'package:flutter/material.dart';

import '../models/gacha_event.dart';
import '../models/games.dart';
import '../utils/format.dart';
import 'event_image.dart';

class EventCard extends StatelessWidget {
  const EventCard({
    super.key,
    required this.event,
    required this.now,
    required this.onTap,
  });

  final GachaEvent event;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Games.color(event.game);
    final ended = event.isEndedAt(now);
    final upcoming = event.isUpcomingAt(now);
    final left = event.end.difference(now);
    final endingSoon = !ended && !upcoming && left.inHours < 24;

    final String countdown;
    final String caption;
    if (ended) {
      countdown = formatDay(event.end);
      caption = 'ended';
    } else if (upcoming) {
      countdown = formatRemaining(event.start.difference(now));
      caption = 'until start';
    } else {
      countdown = formatRemaining(left);
      caption = event.endEstimated ? 'left (est.)' : 'left';
    }

    return Opacity(
      opacity: ended ? 0.5 : 1,
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    EventImage(
                      game: event.game,
                      filePath: event.imagePath,
                      url: event.imageUrl,
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                          stops: [0.4, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: _Pill(text: event.game, color: color),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 8,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            countdown,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                              height: 1,
                              color: endingSoon ? theme.colorScheme.error : Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            caption,
                            style: const TextStyle(fontSize: 13, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${event.kind.label} - ${formatRange(event.start, event.end, endEstimated: event.endEstimated)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: upcoming ? 0 : event.progressAt(now),
                      color: endingSoon ? theme.colorScheme.error : color,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, color: Colors.black87),
      ),
    );
  }
}
