import 'dart:async';

import 'package:flutter/material.dart';

import '../models/gacha_event.dart';
import '../models/games.dart';
import '../services/auto_import_service.dart';
import '../services/event_store.dart';
import '../services/settings_store.dart';
import '../widgets/event_card.dart';
import 'edit_event_screen.dart';
import 'import_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, required this.settings});

  final EventStore store;
  final SettingsStore settings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _game;
  bool _showEnded = false;
  DateTime _now = DateTime.now();
  late final Timer _ticker;
  late final AutoImportService _auto;
  late final AppLifecycleListener _lifecycle;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() => _now = DateTime.now()),
    );
    _auto = AutoImportService(widget.store, widget.settings);
    _lifecycle = AppLifecycleListener(onResume: () => _checkForBanners());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForBanners());
  }

  @override
  void dispose() {
    _ticker.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _checkForBanners({bool force = false}) async {
    if (widget.settings.autoGames.isEmpty) return;
    setState(() => _checking = true);
    try {
      final added = await _auto.run(force: force);
      if (!mounted) return;
      if (added > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(added == 1
              ? 'Added 1 new character banner.'
              : 'Added $added new character banners.'),
        ));
      } else if (force) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No new character banners.')),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _openEditor([GachaEvent? event]) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EditEventScreen(
        store: widget.store,
        settings: widget.settings,
        existing: event,
      ),
    ));
  }

  void _openImport() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ImportScreen(store: widget.store, settings: widget.settings),
    ));
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsScreen(settings: widget.settings, store: widget.store),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.store, widget.settings]),
      builder: (context, _) {
        final now = _now;
        final all = widget.store.events
            .where((e) => _game == null || e.game == _game)
            .toList();
        final live = all.where((e) => e.isActiveAt(now)).toList()
          ..sort((a, b) => a.end.compareTo(b.end));
        final upcoming = all.where((e) => e.isUpcomingAt(now)).toList()
          ..sort((a, b) => a.start.compareTo(b.start));
        final ended = all.where((e) => e.isEndedAt(now)).toList()
          ..sort((a, b) => b.end.compareTo(a.end));

        return Scaffold(
          appBar: AppBar(
            title: const Text('Gacha Tracker'),
            actions: [
              IconButton(
                onPressed: _checking ? null : () => _checkForBanners(force: true),
                tooltip: 'Check for new banners',
                icon: _checking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
              IconButton(
                onPressed: _openImport,
                tooltip: 'Import from a game',
                icon: const Icon(Icons.cloud_download_outlined),
              ),
              IconButton(
                onPressed: _openSettings,
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
              ),
              const SizedBox(width: 8),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add),
            label: const Text('Add event'),
          ),
          body: RefreshIndicator(
            onRefresh: () => _checkForBanners(force: true),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _filterBar()),
                if (all.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      filtered: _game != null,
                      onImport: _openImport,
                    ),
                  ),
                ..._section('Live now', live, now),
                ..._section('Upcoming', upcoming, now),
                if (ended.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(() => _showEnded = !_showEnded),
                          icon: Icon(_showEnded ? Icons.expand_less : Icons.expand_more),
                          label: Text(_showEnded
                              ? 'Hide ended'
                              : 'Show ended (${ended.length})'),
                        ),
                      ),
                    ),
                  ),
                if (_showEnded) ..._section('Ended', ended, now),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _filterBar() {
    Widget chip(String label, String? game) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: _game == game,
            onSelected: (_) => setState(() => _game = game),
          ),
        );

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          chip('All', null),
          for (final g in Games.all) chip(g, g),
        ],
      ),
    );
  }

  List<Widget> _section(String title, List<GachaEvent> events, DateTime now) {
    if (events.isEmpty) return const [];
    final theme = Theme.of(context);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Text(
            '$title (${events.length})',
            style: theme.textTheme.titleMedium,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 480,
            mainAxisExtent: 250,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => EventCard(
              event: events[i],
              now: now,
              onTap: () => _openEditor(events[i]),
            ),
            childCount: events.length,
          ),
        ),
      ),
    ];
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered, required this.onImport});

  final bool filtered;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              filtered ? 'Nothing tracked for this game' : 'No events tracked yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Add one by hand or import from your games.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Import events'),
            ),
          ],
        ),
      ),
    );
  }
}
