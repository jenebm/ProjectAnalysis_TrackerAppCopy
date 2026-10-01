import 'package:flutter/material.dart';

import '../importers/importer.dart';
import '../importers/registry.dart';
import '../models/games.dart';
import '../services/event_store.dart';
import '../services/settings_store.dart';
import '../utils/format.dart';
import '../widgets/event_image.dart';
import 'edit_event_screen.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.store, required this.settings});

  final EventStore store;
  final SettingsStore settings;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  String _game = Games.genshin;
  EventImporter? _importer;
  Future<List<ImportCandidate>>? _future;

  EventImporter? _importerFor(String game) => importerFor(game, widget.settings);

  @override
  void initState() {
    super.initState();
    _importer = _importerFor(_game);
    _future = _importer?.fetch();
  }

  void _load() {
    setState(() {
      _importer = _importerFor(_game);
      _future = _importer?.fetch();
    });
  }

  Future<void> _quickAdd(ImportCandidate c) async {
    final event = c.toEvent(widget.store.newId());
    await widget.store.upsert(event);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Added "${c.name}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.store.delete(event.id, dismiss: false),
        ),
      ));
  }

  void _review(ImportCandidate c) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EditEventScreen(
        store: widget.store,
        settings: widget.settings,
        candidate: c,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import events'),
        actions: [
          if (_importer != null)
            IconButton(
              onPressed: _load,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final g in importableGames)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(g),
                      selected: _game == g,
                      showCheckmark: false,
                      onSelected: (_) {
                        _game = g;
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    final importer = _importer;
    if (importer == null) {
      return const _Message(
        icon: Icons.edit_note,
        title: 'No auto-import for this game',
        body: 'Add these by hand.',
      );
    }
    final serverNote = _game == Games.limbus
        ? ''
        : ' (${widget.settings.region.label} server, change in Settings)';

    return FutureBuilder<List<ImportCandidate>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _Message(
            icon: Icons.cloud_off_outlined,
            title: "Couldn't reach ${importer.sourceLabel}",
            body: '${snap.error}',
            action: FilledButton(onPressed: _load, child: const Text('Try again')),
          );
        }
        final items = [...?snap.data]..sort((a, b) => b.start.compareTo(a.start));
        if (items.isEmpty) {
          return const _Message(
            icon: Icons.inbox_outlined,
            title: 'No current announcements',
            body: 'Nothing upcoming right now.',
          );
        }

        return ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            itemCount: items.length + 1,
            separatorBuilder: (context, i) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: Text(
                    'From ${importer.sourceLabel}. Tap Add, or tap a row to check it first.$serverNote',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              }
              final c = items[i - 1];
              return _CandidateTile(
                candidate: c,
                added: widget.store.hasSource(c.sourceId),
                onReview: () => _review(c),
                onAdd: () => _quickAdd(c),
              );
            },
          ),
        );
      },
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.added,
    required this.onReview,
    required this.onAdd,
  });

  final ImportCandidate candidate;
  final bool added;
  final VoidCallback onReview;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = candidate;

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: added ? null : onReview,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 96,
                  height: 54,
                  child: EventImage(game: c.game, url: c.imageUrl),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatRange(c.start, c.end),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (c.category != null)
                      Text(
                        c.category!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: c.needsReview
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              added
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(Icons.check_circle, color: theme.colorScheme.primary),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}
