import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/change_journal.dart';
import '../../../services/l10n/locale_controller.dart';

typedef ChangeJournalAction = Future<void> Function(
  ChangeJournalEntry entry,
  bool redo,
);

/// Compact, expandable journal tab. Filters are intentionally out of scope for
/// this first iteration; important changes and informational events are marked
/// differently, while every saved entry remains in one chronological list.
class ChangeJournalTab extends StatefulWidget {
  const ChangeJournalTab({
    super.key,
    required this.padding,
    required this.onNavigate,
    required this.onApplyAction,
  });

  final EdgeInsets padding;
  final ValueChanged<ChangeJournalEntry> onNavigate;
  final ChangeJournalAction onApplyAction;

  @override
  State<ChangeJournalTab> createState() => _ChangeJournalTabState();
}

class _ChangeJournalTabState extends State<ChangeJournalTab> {
  late Future<List<ChangeJournalEntry>> _entriesFuture;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _entriesFuture = ChangeJournalService.readAll();
    ChangeJournalService.revision.addListener(_onRevision);
    unawaited(_loadEnabled());
  }

  @override
  void dispose() {
    ChangeJournalService.revision.removeListener(_onRevision);
    super.dispose();
  }

  void _onRevision() {
    if (!mounted) return;
    setState(() {
      _entriesFuture = ChangeJournalService.readAll();
    });
  }

  Future<void> _loadEnabled() async {
    final value = await ChangeJournalService.isEnabled();
    if (mounted) setState(() => _enabled = value);
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _enabled = value);
    await ChangeJournalService.setEnabled(value);
  }

  String _dateHeading(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    if (day == today) return getLocalText.s("Today");
    if (day == today.subtract(const Duration(days: 1))) {
      return getLocalText.s("Yesterday");
    }
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _timeLabel(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ChangeJournalEntry>>(
      future: _entriesFuture,
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const <ChangeJournalEntry>[];
        final children = <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.history),
            title: Text(getLocalText.s("Record settings changes")),
            subtitle: Text(_enabled
                ? getLocalText.s("New events will be added to this history.")
                : getLocalText.s("Logging is disabled. Existing entries are kept.")),
            value: _enabled,
            onChanged: _setEnabled,
          ),
          const Divider(height: 24),
        ];

        if (snapshot.connectionState == ConnectionState.waiting) {
          children.add(const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ));
        } else if (entries.isEmpty) {
          children.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(getLocalText.s("No changes recorded yet")),
            ),
          ));
        } else {
          String? previousHeading;
          for (final entry in entries) {
            final heading = _dateHeading(entry.timestamp);
            if (heading != previousHeading) {
              children.add(Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
                child: Text(
                  heading,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ));
              previousHeading = heading;
            }
            children.add(_JournalEntryCard(
              key: ValueKey(entry.id),
              entry: entry,
              timeLabel: _timeLabel(entry.timestamp),
              onNavigate: () => widget.onNavigate(entry),
              onApplyAction: (redo) =>
                  widget.onApplyAction(entry, redo),
            ));
          }
        }

        return ListView(
          padding: widget.padding,
          children: children,
        );
      },
    );
  }
}

class _JournalEntryCard extends StatefulWidget {
  const _JournalEntryCard({
    required this.entry,
    required this.timeLabel,
    required this.onNavigate,
    required this.onApplyAction,
  });

  final ChangeJournalEntry entry;
  final String timeLabel;
  final VoidCallback onNavigate;
  final ValueChanged<bool> onApplyAction;

  @override
  State<_JournalEntryCard> createState() => _JournalEntryCardState();
}

class _JournalEntryCardState extends State<_JournalEntryCard> {
  late final TextEditingController _commentController;
  bool _commentSaved = false;

  @override
  void initState() {
    super.initState();
    _commentController = TextEditingController(text: widget.entry.comment);
  }

  @override
  void didUpdateWidget(covariant _JournalEntryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.comment != widget.entry.comment &&
        widget.entry.comment != _commentController.text) {
      _commentController.text = widget.entry.comment;
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _saveComment() async {
    await ChangeJournalService.setComment(
      widget.entry.id,
      _commentController.text,
    );
    if (mounted) setState(() => _commentSaved = true);
  }

  String _timeLabel() => widget.timeLabel;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final theme = Theme.of(context);
    final important = entry.category == 'important';
    final color = important
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: important
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          foregroundColor: color,
          child: Icon(important ? Icons.tune : Icons.info_outline, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _timeLabel(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.beforeText.isNotEmpty || entry.afterText.isNotEmpty)
                Text(
                  '${entry.beforeText} → ${entry.afterText}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              if (entry.path.isNotEmpty)
                Text(
                  entry.path,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (entry.isUndone)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    getLocalText.s("Change undone"),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (entry.beforeText.isNotEmpty || entry.afterText.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${getLocalText.s("Previous value")}: ${entry.beforeText}\n'
                '${getLocalText.s("New value")}: ${entry.afterText}',
              ),
            ),
          if (entry.path.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  entry.path,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentController,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: getLocalText.s("Comment"),
              hintText: getLocalText.s("Add a comment for this entry"),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) {
              if (_commentSaved) setState(() => _commentSaved = false);
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _saveComment,
              icon: Icon(_commentSaved ? Icons.check : Icons.save_outlined),
              label: Text(getLocalText.s(_commentSaved ? "Comment saved" : "Save comment")),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                onPressed: entry.target.isEmpty ? null : widget.onNavigate,
                icon: const Icon(Icons.open_in_new),
                label: Text(getLocalText.s("Go to setting")),
              ),
              if (entry.canUndo)
                OutlinedButton.icon(
                  onPressed: () => widget.onApplyAction(entry.isUndone),
                  icon: Icon(entry.isUndone ? Icons.redo : Icons.undo),
                  label: Text(getLocalText.s(entry.isUndone ? "Redo change" : "Undo change")),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
