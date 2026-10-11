import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A local, user-visible audit trail for configuration and app-setting changes.
/// Sensitive values (tokens, passwords, private keys and HWIDs) must never be
/// written here.
class ChangeJournalEntry {
  const ChangeJournalEntry({
    required this.id,
    required this.timestamp,
    required this.category,
    required this.title,
    this.beforeText = '',
    this.afterText = '',
    this.path = '',
    this.target = '',
    this.actionKey,
    this.beforeValue,
    this.afterValue,
    this.comment = '',
    this.isUndone = false,
  });

  final String id;
  final DateTime timestamp;
  final String category;
  final String title;
  final String beforeText;
  final String afterText;
  final String path;
  final String target;
  final String? actionKey;
  final String? beforeValue;
  final String? afterValue;
  final String comment;
  final bool isUndone;

  bool get canUndo =>
      actionKey != null && beforeValue != null && afterValue != null;

  ChangeJournalEntry copyWith({
    String? comment,
    bool? isUndone,
  }) {
    return ChangeJournalEntry(
      id: id,
      timestamp: timestamp,
      category: category,
      title: title,
      beforeText: beforeText,
      afterText: afterText,
      path: path,
      target: target,
      actionKey: actionKey,
      beforeValue: beforeValue,
      afterValue: afterValue,
      comment: comment ?? this.comment,
      isUndone: isUndone ?? this.isUndone,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'category': category,
        'title': title,
        'beforeText': beforeText,
        'afterText': afterText,
        'path': path,
        'target': target,
        'actionKey': actionKey,
        'beforeValue': beforeValue,
        'afterValue': afterValue,
        'comment': comment,
        'isUndone': isUndone,
      };

  factory ChangeJournalEntry.fromJson(Map<String, dynamic> json) {
    String text(String key) => json[key]?.toString() ?? '';
    String? nullableText(String key) {
      final value = json[key];
      return value?.toString();
    }

    return ChangeJournalEntry(
      id: text('id'),
      timestamp: DateTime.tryParse(text('timestamp')) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      category: text('category').isEmpty ? 'info' : text('category'),
      title: text('title'),
      beforeText: text('beforeText'),
      afterText: text('afterText'),
      path: text('path'),
      target: text('target'),
      actionKey: nullableText('actionKey'),
      beforeValue: nullableText('beforeValue'),
      afterValue: nullableText('afterValue'),
      comment: text('comment'),
      isUndone: json['isUndone'] == true,
    );
  }
}

/// Persisted on-device. Keeping this outside lxbox_settings.json means journal
/// records cannot affect the VPN configuration, import/export, or config-dirty
/// lifecycle.
class ChangeJournalService {
  ChangeJournalService._();

  static const _enabledKey = 'change_journal_enabled_v1';
  static const _entriesKey = 'change_journal_entries_v1';
  static const _maxEntries = 500;

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static Future<void> _writeQueue = Future<void>.value();

  static Future<T> _exclusive<T>(Future<T> Function() action) async {
    final previous = _writeQueue;
    final gate = Completer<void>();
    _writeQueue = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }

  static Future<bool> isEnabled() async => _exclusive(() async {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getBool(_enabledKey) ?? true;
      });

  static Future<void> setEnabled(bool enabled) =>
      _exclusive(() async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_enabledKey, enabled);
        revision.value++;
      });

  static Future<List<ChangeJournalEntry>> readAll() =>
      _exclusive(() async {
        final prefs = await SharedPreferences.getInstance();
        return List<ChangeJournalEntry>.unmodifiable(_readEntries(prefs));
      });

  static Future<void> record({
    required String category,
    required String title,
    String beforeText = '',
    String afterText = '',
    String path = '',
    String target = '',
    String? actionKey,
    String? beforeValue,
    String? afterValue,
    String comment = '',
  }) =>
      _exclusive(() async {
        final prefs = await SharedPreferences.getInstance();
        if (!(prefs.getBool(_enabledKey) ?? true)) return;

        final entries = _readEntries(prefs);
        entries.insert(
          0,
          ChangeJournalEntry(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            timestamp: DateTime.now(),
            category: category,
            title: title,
            beforeText: beforeText,
            afterText: afterText,
            path: path,
            target: target,
            actionKey: actionKey,
            beforeValue: beforeValue,
            afterValue: afterValue,
            comment: comment,
          ),
        );
        if (entries.length > _maxEntries) {
          entries.removeRange(_maxEntries, entries.length);
        }
        await _writeEntries(prefs, entries);
        revision.value++;
      });

  static Future<void> setComment(String id, String comment) =>
      _exclusive(() async {
        final prefs = await SharedPreferences.getInstance();
        final entries = _readEntries(prefs);
        final index = entries.indexWhere((entry) => entry.id == id);
        if (index < 0) return;
        entries[index] = entries[index].copyWith(comment: comment.trim());
        await _writeEntries(prefs, entries);
        revision.value++;
      });

  static Future<void> setUndone(String id, bool undone) =>
      _exclusive(() async {
        final prefs = await SharedPreferences.getInstance();
        final entries = _readEntries(prefs);
        final index = entries.indexWhere((entry) => entry.id == id);
        if (index < 0) return;
        entries[index] = entries[index].copyWith(isUndone: undone);
        await _writeEntries(prefs, entries);
        revision.value++;
      });

  static Future<void> clearHistory() => _exclusive(() async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_entriesKey);
        revision.value++;
      });

  static List<ChangeJournalEntry> _readEntries(SharedPreferences prefs) {
    final raw = prefs.getString(_entriesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => ChangeJournalEntry.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (_) {
      // A malformed journal must not prevent the app or VPN from starting.
      return [];
    }
  }

  static Future<void> _writeEntries(
    SharedPreferences prefs,
    List<ChangeJournalEntry> entries,
  ) async {
    await prefs.setString(
      _entriesKey,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }
}
