import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../importers/registry.dart';
import '../services/backup_service.dart';
import '../services/event_store.dart';
import '../services/settings_store.dart';
import '../utils/format.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings, required this.store});

  final SettingsStore settings;
  final EventStore store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickZone() async {
    final zones = tz.timeZoneDatabase.locations.keys.toList()..sort();
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => _ZonePicker(zones: zones, current: widget.settings.displayZone),
    );
    if (choice == null) return; // dismissed
    await widget.settings.setDisplayZone(choice.isEmpty ? null : choice);
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final path = await BackupService.exportFile(widget.store);
      if (path != null && mounted) _say('Backup saved.');
    } catch (e) {
      if (mounted) _say('Backup failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final r = await BackupService.importFile(widget.store);
      if (r != null && mounted) {
        _say('Added ${r.added}, updated ${r.updated}, ${r.skipped} unchanged'
            '${r.failed > 0 ? ', ${r.failed} unreadable' : ''}');
      }
    } on FormatException catch (e) {
      if (mounted) _say(e.message);
    } catch (e) {
      if (mounted) _say('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final heading = theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Your server', style: heading),
                const SizedBox(height: 6),
                Text(
                  'Imported times get converted from this server. Limbus is always KST.',
                  style: muted,
                ),
                const SizedBox(height: 12),
                SegmentedButton<ServerRegion>(
                  segments: [
                    for (final r in ServerRegion.values)
                      ButtonSegment(value: r, label: Text(r.label)),
                  ],
                  selected: {widget.settings.region},
                  onSelectionChanged: (s) => widget.settings.setRegion(s.first),
                ),
                const SizedBox(height: 32),
                Text('Time zone', style: heading),
                const SizedBox(height: 6),
                Text(
                  'Device zone is usually fine.',
                  style: muted,
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.schedule),
                  title: Text(widget.settings.displayZone ?? 'Device time zone'),
                  subtitle: Text('Now ${zoneAbbr(DateTime.now())}, '
                      '${TimeOfDay.fromDateTime(toDisplay(DateTime.now())).format(context)}'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _pickZone,
                ),
                const SizedBox(height: 32),
                Text('Auto-add character banners', style: heading),
                const SizedBox(height: 6),
                Text(
                  'New limited character banners get added when you open the app. '
                  'Weapon banners and events stay in Import. Deleted ones stay deleted.',
                  style: muted,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in autoImportGames)
                      FilterChip(
                        label: Text(g),
                        selected: widget.settings.autoGames.contains(g),
                        showCheckmark: false,
                        onSelected: (on) => widget.settings.setAutoGame(g, on),
                      ),
                  ],
                ),
                const SizedBox(height: 32),
                Text('Backup', style: heading),
                const SizedBox(height: 6),
                Text(
                  'Export everything (pictures too) to one file for another device. '
                  'Importing merges, newest edit wins.',
                  style: muted,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _export,
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Export backup'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _import,
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Import backup'),
                    ),
                  ],
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ZonePicker extends StatefulWidget {
  const _ZonePicker({required this.zones, required this.current});

  final List<String> zones;
  final String? current;

  @override
  State<_ZonePicker> createState() => _ZonePickerState();
}

class _ZonePickerState extends State<_ZonePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase().replaceAll(' ', '_');
    final matches = q.isEmpty
        ? widget.zones
        : widget.zones.where((z) => z.toLowerCase().contains(q)).toList();

    return AlertDialog(
      title: const Text('Time zone'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 420,
        height: 460,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search time zones',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.phone_android),
              title: const Text('Device time zone'),
              selected: widget.current == null,
              onTap: () => Navigator.pop(context, ''),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: matches.length,
                itemBuilder: (context, i) {
                  final zone = matches[i];
                  return ListTile(
                    dense: true,
                    title: Text(zone.replaceAll('_', ' ')),
                    selected: zone == widget.current,
                    onTap: () => Navigator.pop(context, zone),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
