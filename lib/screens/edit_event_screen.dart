import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../importers/importer.dart';
import '../models/gacha_event.dart';
import '../models/games.dart';
import '../services/event_store.dart';
import '../services/settings_store.dart';
import '../utils/format.dart';
import '../widgets/event_image.dart';

class EditEventScreen extends StatefulWidget {
  const EditEventScreen({
    super.key,
    required this.store,
    required this.settings,
    this.existing,
    this.candidate,
  });

  final EventStore store;
  final SettingsStore settings;
  final GachaEvent? existing;
  final ImportCandidate? candidate;

  @override
  State<EditEventScreen> createState() => _EditEventScreenState();
}

class _EditEventScreenState extends State<EditEventScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _notes;
  late String _game;
  late EventKind _kind;
  late DateTime _start;
  late DateTime _end;
  String? _imagePath; // already in app storage
  String? _pickedPath; // newly chosen, copied on save
  String? _imageUrl;
  late bool _endEstimated;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;
  bool get _hasImage =>
      _pickedPath != null || _imagePath != null || _imageUrl != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final c = widget.candidate;
    final now = DateTime.now();
    final defaultStart = DateTime(now.year, now.month, now.day, now.hour);

    _name = TextEditingController(text: e?.name ?? c?.name ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _game = e?.game ?? c?.game ?? Games.genshin;
    _kind = e?.kind ?? c?.kind ?? EventKind.banner;
    _start = e?.start ?? c?.start ?? defaultStart;
    _end = e?.end ?? c?.end ?? defaultStart.add(const Duration(days: 21));
    _endEstimated = e?.endEstimated ?? c?.needsReview ?? false;
    _imagePath = e?.imagePath;
    _imageUrl = e?.imageUrl ?? c?.imageUrl;
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    setState(() {
      _pickedPath = path;
      _imageUrl = null;
    });
  }

  Future<void> _enterUrl() async {
    final ctrl = TextEditingController(text: _imageUrl ?? '');
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Image URL'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'https://...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Use URL'),
          ),
        ],
      ),
    );
    if (url == null || !mounted) return;
    setState(() {
      _imageUrl = url.isEmpty ? null : url;
      _pickedPath = null;
      _imagePath = null;
    });
  }

  void _clearImage() => setState(() {
        _imagePath = null;
        _pickedPath = null;
        _imageUrl = null;
      });

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final shown = toDisplay(initial);
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(shown.year, shown.month, shown.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: shown.hour, minute: shown.minute),
    );
    if (time == null) return null;
    return fromDisplay(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<Duration?> _askDuration(String title, String help) async {
    final days = TextEditingController();
    final hours = TextEditingController();
    final mins = TextEditingController();
    Widget field(TextEditingController c, String label) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          ),
        );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(help),
            const SizedBox(height: 16),
            Row(
              children: [
                field(days, 'Days'),
                const SizedBox(width: 8),
                field(hours, 'Hours'),
                const SizedBox(width: 8),
                field(mins, 'Minutes'),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Set')),
        ],
      ),
    );
    if (ok != true) return null;
    int n(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
    final d = Duration(days: n(days), hours: n(hours), minutes: n(mins));
    return d > Duration.zero ? d : null;
  }

  Future<void> _setTimeLeft() async {
    final d = await _askDuration(
      'Time left',
      'Whatever the in-game countdown says',
    );
    if (d == null || !mounted) return;
    setState(() {
      _end = DateTime.now().add(d);
      _endEstimated = false;
      if (!_start.isBefore(_end)) _start = DateTime.now();
    });
  }

  Future<void> _setCustomLength() async {
    final d = await _askDuration('Length', 'From the start time');
    if (d == null || !mounted) return;
    setState(() {
      _end = _start.add(d);
      _endEstimated = false;
    });
  }

  // Offer to reuse the fixed end date for the other guessed events
  Future<void> _offerVersionEnd(GachaEvent saved) async {
    final others = widget.store.events
        .where((e) => e.id != saved.id && e.game == saved.game && e.endEstimated)
        .toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Use this as the version end?'),
        content: Text(
          '${formatDateTime(saved.end)}\n\n'
          '${others.isEmpty ? '' : 'Also fixes ${others.length} other ${saved.game} '
              '${others.length == 1 ? 'event' : 'events'} with a guessed end. '}'
          'Future "before version update" imports use it too.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Just this one')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Use for all')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.settings.setVersionEnd(saved.game, saved.end);
    if (others.isEmpty) return;
    await widget.store.putAll([
      for (final e in others)
        if (saved.end.isAfter(e.start))
          e.copyWith(end: saved.end, endEstimated: false),
    ]);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_end.isAfter(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End has to be after start')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      var imagePath = _imagePath;
      final picked = _pickedPath;
      if (picked != null) imagePath = await widget.store.storeImage(picked);

      final notes = _notes.text.trim();
      final wasEstimated =
          widget.existing?.endEstimated ?? widget.candidate?.needsReview ?? false;
      final saved = GachaEvent(
        id: widget.existing?.id ?? widget.store.newId(),
        game: _game,
        name: _name.text.trim(),
        start: _start,
        end: _end,
        kind: _kind,
        imagePath: imagePath,
        imageUrl: _imageUrl,
        notes: notes.isEmpty ? null : notes,
        sourceId: widget.existing?.sourceId ?? widget.candidate?.sourceId,
        endEstimated: _endEstimated,
      );
      await widget.store.upsert(saved);
      if (!mounted) return;
      if (wasEstimated && !_endEstimated && saved.game == Games.endfield) {
        await _offerVersionEnd(saved);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't save: $e")),
      );
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete event?'),
        content: Text('"${existing.name}" will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.delete(existing.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _isEditing
        ? 'Edit event'
        : widget.candidate != null
            ? 'Review import'
            : 'New event';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_isEditing)
            IconButton(
              onPressed: _delete,
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.candidate?.needsReview ?? false)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Dates were parsed from the post, double check them',
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
                  ),
                _imageSection(theme),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Event name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: 20),
                _label(theme, 'Game'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in Games.all)
                      ChoiceChip(
                        label: Text(g),
                        selected: _game == g,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _game = g),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _label(theme, 'Type'),
                SegmentedButton<EventKind>(
                  segments: [
                    for (final k in EventKind.values)
                      ButtonSegment(value: k, label: Text(k.label)),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => setState(() => _kind = s.first),
                ),
                const SizedBox(height: 20),
                _label(theme, 'Schedule'),
                _dateTile(Icons.play_circle_outline, 'Starts', _start, (d) {
                  setState(() {
                    _start = d;
                    if (!_end.isAfter(_start)) {
                      _end = _start.add(const Duration(days: 21));
                      _endEstimated = true;
                    }
                  });
                }),
                _dateTile(Icons.flag_outlined, 'Ends', _end, (d) {
                  setState(() {
                    _end = d;
                    _endEstimated = false;
                  });
                }),
                if (_endEstimated)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      'End date not announced yet (est.)',
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
                  ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Length', style: theme.textTheme.bodySmall),
                    for (final days in const [7, 14, 21, 42])
                      ActionChip(
                        label: Text('${days}d'),
                        onPressed: () => setState(() {
                          _end = _start.add(Duration(days: days));
                          _endEstimated = false;
                        }),
                      ),
                    ActionChip(
                      label: const Text('Custom...'),
                      onPressed: _setCustomLength,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _setTimeLeft,
                    icon: const Icon(Icons.timer_outlined),
                    label: const Text('Time left...'),
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'pull target, pity, rewards etc',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_isEditing ? 'Save changes' : 'Add event'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      );

  Widget _dateTile(
    IconData icon,
    String label,
    DateTime value,
    ValueChanged<DateTime> onChanged,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(formatDateTime(value)),
      trailing: const Icon(Icons.edit_calendar_outlined),
      onTap: () async {
        final picked = await _pickDateTime(value);
        if (picked != null) onChanged(picked);
      },
    );
  }

  Widget _imageSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 7,
            child: Material(
              color: theme.colorScheme.surfaceContainerHigh,
              child: InkWell(
                onTap: _pickImage,
                child: _hasImage
                    ? EventImage(
                        game: _game,
                        filePath: _pickedPath ?? _imagePath,
                        url: _imageUrl,
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 40,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap to add a picture',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
        Row(
          children: [
            TextButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.image_outlined),
              label: const Text('Choose file'),
            ),
            TextButton.icon(
              onPressed: _enterUrl,
              icon: const Icon(Icons.link),
              label: const Text('Use URL'),
            ),
            const Spacer(),
            if (_hasImage)
              TextButton(onPressed: _clearImage, child: const Text('Remove')),
          ],
        ),
      ],
    );
  }
}
