import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/l10n/locale_controller.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/sort_widgets.dart' as modern_sort;

enum SourceSortMode {
  defaultOrder(Icons.swap_vert),
  nameAsc(Icons.sort_by_alpha),
  nameDesc(Icons.sort_by_alpha),
  modifiedNewest(Icons.history),
  modifiedOldest(Icons.history),
  createdNewest(Icons.calendar_month),
  createdOldest(Icons.calendar_month);

  const SourceSortMode(this.icon);

  final IconData icon;

  String label() => switch (this) {
        SourceSortMode.defaultOrder => getLocalText.s("Default"),
        SourceSortMode.nameAsc => getLocalText.s("Name A–Z"),
        SourceSortMode.nameDesc => getLocalText.s("Name Z–A"),
        SourceSortMode.modifiedNewest => getLocalText.s("Modified — newest"),
        SourceSortMode.modifiedOldest => getLocalText.s("Modified — oldest"),
        SourceSortMode.createdNewest => getLocalText.s("Created — newest"),
        SourceSortMode.createdOldest => getLocalText.s("Created — oldest"),
      };

  SourceSortMode get next => switch (this) {
        SourceSortMode.defaultOrder => SourceSortMode.nameAsc,
        SourceSortMode.nameAsc => SourceSortMode.nameDesc,
        SourceSortMode.nameDesc => SourceSortMode.modifiedNewest,
        SourceSortMode.modifiedNewest => SourceSortMode.modifiedOldest,
        SourceSortMode.modifiedOldest => SourceSortMode.createdNewest,
        SourceSortMode.createdNewest => SourceSortMode.createdOldest,
        SourceSortMode.createdOldest => SourceSortMode.defaultOrder,
      };
}

const List<String> defaultSourceGroupOrder = <String>[
  'folder',
  'server',
  'subscription',
  'chain',
];

enum SourceNameSortStyle { letters, tags }

enum SourceTagPosition { top, bottom }

class SourceSortSettings {
  const SourceSortSettings({
    this.mode = SourceSortMode.nameAsc,
    this.sortState = const modern_sort.SortState(),
    this.groupByType = false,
    this.enabledFirst = false,
    this.groupOrder = defaultSourceGroupOrder,
    this.activeFilter = ActiveFilter.all,
    this.nameSortStyle = SourceNameSortStyle.letters,
    this.tagPosition = SourceTagPosition.top,
  });

  /// Concrete mode used by the comparator. It is kept for compatibility with
  /// existing list-sorting code and older saved settings.
  final SourceSortMode mode;

  /// Current field plus separately remembered direction for each field.
  final modern_sort.SortState sortState;

  final bool groupByType;
  final bool enabledFirst;
  final List<String> groupOrder;
  final ActiveFilter activeFilter;
  final SourceNameSortStyle nameSortStyle;
  final SourceTagPosition tagPosition;

  /// Resolve settings created through the old single-mode constructor while
  /// the screen itself uses the per-field state model.
  modern_sort.SortState get effectiveSortState =>
      mode == _sortModeFromState(sortState)
          ? sortState
          : _sortStateFromLegacyMode(mode);

  SourceSortSettings copyWith({
    SourceSortMode? mode,
    modern_sort.SortState? sortState,
    bool? groupByType,
    bool? enabledFirst,
    List<String>? groupOrder,
    ActiveFilter? activeFilter,
    SourceNameSortStyle? nameSortStyle,
    SourceTagPosition? tagPosition,
  }) {
    final nextState = sortState ??
        (mode == null ? effectiveSortState : _sortStateFromLegacyMode(mode));
    final nextMode = sortState != null
        ? _sortModeFromState(sortState)
        : (mode ?? _sortModeFromState(nextState));
    return SourceSortSettings(
      mode: nextMode,
      sortState: nextState,
      groupByType: groupByType ?? this.groupByType,
      enabledFirst: enabledFirst ?? this.enabledFirst,
      groupOrder: groupOrder ?? this.groupOrder,
      activeFilter: activeFilter ?? this.activeFilter,
      nameSortStyle: nameSortStyle ?? this.nameSortStyle,
      tagPosition: tagPosition ?? this.tagPosition,
    );
  }

  Map<String, dynamic> toJson() {
    // A few tests and migration callers still construct settings by legacy
    // mode. If that mode and the new state differ, persist a consistent pair.
    final state = effectiveSortState;
    return {
      'mode': _sortModeFromState(state).name,
      'sort_state': state.toJson(),
      'group_by_type': groupByType,
      'enabled_first': enabledFirst,
      'group_order': groupOrder,
      'active_filter': activeFilter.name,
      'name_sort_style': nameSortStyle.name,
      'tag_position': tagPosition.name,
    };
  }

  static SourceSortSettings fromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const SourceSortSettings();

      final modeName = decoded['mode'];
      final legacyMode = SourceSortMode.values.firstWhere(
        (m) => m.name == modeName,
        orElse: () => SourceSortMode.nameAsc,
      );
      final rawSortState = decoded['sort_state'];
      final sortState = rawSortState is Map
          ? modern_sort.SortState.fromJson(
              Map<String, dynamic>.from(rawSortState),
            )
          : _sortStateFromLegacyMode(legacyMode);
      final mode = _sortModeFromState(sortState);

      final activeFilter = ActiveFilter.values.firstWhere(
        (f) => f.name == decoded['active_filter'],
        orElse: () => ActiveFilter.all,
      );

      final nameSortStyle = SourceNameSortStyle.values.firstWhere(
        (style) => style.name == decoded['name_sort_style'],
        orElse: () => SourceNameSortStyle.letters,
      );
      final tagPosition = SourceTagPosition.values.firstWhere(
        (position) => position.name == decoded['tag_position'],
        orElse: () => SourceTagPosition.top,
      );

      final order = <String>[];
      final rawOrder = decoded['group_order'];
      if (rawOrder is List) {
        for (final value in rawOrder) {
          final kind = value?.toString();
          if (kind == null ||
              !defaultSourceGroupOrder.contains(kind) ||
              order.contains(kind)) {
            continue;
          }
          order.add(kind);
        }
      }
      for (final kind in defaultSourceGroupOrder) {
        if (!order.contains(kind)) order.add(kind);
      }

      return SourceSortSettings(
        mode: mode,
        sortState: sortState,
        groupByType: decoded['group_by_type'] == true,
        enabledFirst: decoded.containsKey('enabled_first')
            ? decoded['enabled_first'] == true
            : decoded['group_by_active'] == true,
        groupOrder: List<String>.unmodifiable(order),
        activeFilter: activeFilter,
        nameSortStyle: nameSortStyle,
        tagPosition: tagPosition,
      );
    } catch (_) {
      return const SourceSortSettings();
    }
  }
}

/// Map persisted legacy modes to the new per-field reverse flags.
modern_sort.SortState _sortStateFromLegacyMode(SourceSortMode mode) {
  final (field, reversed) = switch (mode) {
    SourceSortMode.defaultOrder || SourceSortMode.nameAsc =>
      (modern_sort.SortField.name, false),
    SourceSortMode.nameDesc => (modern_sort.SortField.name, true),
    SourceSortMode.modifiedNewest => (modern_sort.SortField.modified, false),
    SourceSortMode.modifiedOldest => (modern_sort.SortField.modified, true),
    SourceSortMode.createdNewest => (modern_sort.SortField.created, false),
    SourceSortMode.createdOldest => (modern_sort.SortField.created, true),
  };
  return modern_sort.SortState(
    field: field,
    reversed: {field: reversed},
  );
}

SourceSortMode _sortModeFromState(modern_sort.SortState state) =>
    switch (state.field) {
      modern_sort.SortField.name =>
        state.reverse ? SourceSortMode.nameDesc : SourceSortMode.nameAsc,
      modern_sort.SortField.modified => state.reverse
          ? SourceSortMode.modifiedOldest
          : SourceSortMode.modifiedNewest,
      modern_sort.SortField.created => state.reverse
          ? SourceSortMode.createdOldest
          : SourceSortMode.createdNewest,
    };

class SourceSortTimestamps {
  const SourceSortTimestamps({
    this.createdAt,
    this.modifiedAt,
  });

  final DateTime? createdAt;
  final DateTime? modifiedAt;

  SourceSortTimestamps copyWith({
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) =>
      SourceSortTimestamps(
        createdAt: createdAt ?? this.createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
      );
}

bool isSourceSortNonDefault(SourceSortSettings settings) =>
    settings.effectiveSortState.field != modern_sort.SortField.name ||
    settings.effectiveSortState.reverse ||
    settings.groupByType ||
    settings.enabledFirst ||
    settings.activeFilter != ActiveFilter.all ||
    settings.nameSortStyle != SourceNameSortStyle.letters ||
    (settings.nameSortStyle == SourceNameSortStyle.tags &&
        settings.tagPosition != SourceTagPosition.top) ||
    !listEquals(settings.groupOrder, defaultSourceGroupOrder);

String sourceTypeLabel(String kind) => switch (kind) {
      'folder' => getLocalText.s("Folder"),
      'server' => getLocalText.s("Server"),
      'subscription' => getLocalText.s("Subscription"),
      'chain' => getLocalText.s("Hop chain"),
      _ => kind,
    };

IconData sourceTypeIcon(String kind) => switch (kind) {
      'folder' => Icons.folder_outlined,
      'server' => Icons.dns_outlined,
      'subscription' => Icons.rss_feed,
      'chain' => Icons.link,
      _ => Icons.category_outlined,
    };


const String _russianAlphabet = 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя';
final RegExp _firstSortLetter = RegExp(
  r'[a-zA-ZÀ-ɏа-яА-ЯёЁ㐀-䶿一-鿿぀-ヿ가-힯]',
);
final RegExp _asciiDigit = RegExp(r'^[0-9]$');

String? _letterSortKey(String value, String localeTag) {
  final match = _firstSortLetter.firstMatch(value);
  if (match == null) return null;
  return _normalizePhonetic(value.substring(match.start), localeTag);
}

String _normalizePhonetic(String value, String localeTag) {
  final lower = value.toLowerCase();
  return localeTag == 'ru'
      ? _latinToCyrillic(lower)
      : _cyrillicToLatin(lower);
}

String _latinToCyrillic(String value) {
  final chars = value.characters.toList();
  const digraphs = <String, String>{
    'shch': 'щ', 'sch': 'щ', 'zh': 'ж', 'kh': 'х',
    'ts': 'ц', 'ch': 'ч', 'sh': 'ш', 'yu': 'ю',
    'ya': 'я', 'yo': 'ё', 'jo': 'ё', 'ye': 'е',
    'ph': 'ф', 'th': 'т', 'qu': 'кв', 'ck': 'к',
  };
  const singles = <String, String>{
    'a': 'а', 'b': 'б', 'c': 'к', 'd': 'д', 'e': 'е', 'f': 'ф',
    'g': 'г', 'h': 'х', 'i': 'и', 'j': 'й', 'k': 'к', 'l': 'л',
    'm': 'м', 'n': 'н', 'o': 'о', 'p': 'п', 'q': 'к', 'r': 'р',
    's': 'с', 't': 'т', 'u': 'у', 'v': 'в', 'w': 'в', 'x': 'кс',
    'y': 'й', 'z': 'з',
  };
  final out = StringBuffer();
  var i = 0;
  while (i < chars.length) {
    var matched = false;
    for (final entry in digraphs.entries) {
      final end = i + entry.key.length;
      if (end <= chars.length &&
          chars.skip(i).take(entry.key.length).join() == entry.key) {
        out.write(entry.value);
        i = end;
        matched = true;
        break;
      }
    }
    if (!matched) {
      out.write(singles[chars[i]] ?? chars[i]);
      i++;
    }
  }
  return out.toString();
}

String _cyrillicToLatin(String value) {
  const letters = <String, String>{
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e',
    'ё': 'yo', 'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k',
    'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r',
    'с': 's', 'т': 't', 'у': 'u', 'ф': 'f', 'х': 'kh', 'ц': 'ts',
    'ч': 'ch', 'ш': 'sh', 'щ': 'shch', 'ъ': '', 'ы': 'y', 'ь': '',
    'э': 'e', 'ю': 'yu', 'я': 'ya',
  };
  final out = StringBuffer();
  for (final character in value.characters) {
    out.write(letters[character] ?? character);
  }
  return out.toString();
}

int _compareCodePoints(String a, String b) {
  final left = a.runes.toList();
  final right = b.runes.toList();
  final common = left.length < right.length ? left.length : right.length;
  for (var i = 0; i < common; i++) {
    if (left[i] != right[i]) return left[i].compareTo(right[i]);
  }
  return left.length.compareTo(right.length);
}

int _compareTextByLocale(String a, String b, String localeTag) {
  final left = _normalizePhonetic(a, localeTag);
  final right = _normalizePhonetic(b, localeTag);
  if (localeTag != 'ru') return left.compareTo(right);

  final leftRunes = left.runes.toList();
  final rightRunes = right.runes.toList();
  final common = leftRunes.length < rightRunes.length
      ? leftRunes.length
      : rightRunes.length;
  for (var i = 0; i < common; i++) {
    final leftRune = leftRunes[i];
    final rightRune = rightRunes[i];
    final leftIndex = _russianAlphabet.indexOf(String.fromCharCode(leftRune));
    final rightIndex = _russianAlphabet.indexOf(String.fromCharCode(rightRune));
    final leftWeight = leftIndex >= 0 ? 0x110000 + leftIndex : leftRune;
    final rightWeight = rightIndex >= 0 ? 0x110000 + rightIndex : rightRune;
    if (leftWeight != rightWeight) {
      return leftWeight.compareTo(rightWeight);
    }
  }
  return leftRunes.length.compareTo(rightRunes.length);
}

String _leadingVisibleGrapheme(String value) {
  final visible =
      value.characters.skipWhile((character) => character.trim().isEmpty);
  return visible.isEmpty ? '' : visible.first;
}

bool _isEmojiGrapheme(String value) {
  if (value.isEmpty) return false;
  final runes = value.runes.toList();
  if (runes.contains(0xFE0F) ||
      runes.contains(0x200D) ||
      runes.contains(0x20E3)) {
    return true;
  }
  final first = runes.first;
  return (first >= 0x1F000 && first <= 0x1FAFF) ||
      (first >= 0x1F1E6 && first <= 0x1F1FF) ||
      (first >= 0x2600 && first <= 0x27BF) ||
      (first >= 0x2300 && first <= 0x23FF);
}

enum _NamePrefixKind { digit, emoji, ordinary }

_NamePrefixKind _namePrefixKind(String name) {
  final first = _leadingVisibleGrapheme(name);
  if (_isEmojiGrapheme(first)) return _NamePrefixKind.emoji;
  if (_asciiDigit.hasMatch(first)) return _NamePrefixKind.digit;
  return _NamePrefixKind.ordinary;
}

bool _isAsciiDigitRune(int rune) => rune >= 0x30 && rune <= 0x39;

int _compareNatural(String a, String b, String localeTag) {
  final left = a.runes.toList();
  final right = b.runes.toList();
  var i = 0;
  var j = 0;
  while (i < left.length && j < right.length) {
    final leftIsDigit = _isAsciiDigitRune(left[i]);
    final rightIsDigit = _isAsciiDigitRune(right[j]);
    if (leftIsDigit && rightIsDigit) {
      final leftStart = i;
      final rightStart = j;
      while (i < left.length && _isAsciiDigitRune(left[i])) {
        i++;
      }
      while (j < right.length && _isAsciiDigitRune(right[j])) {
        j++;
      }
      var leftSignificant = leftStart;
      var rightSignificant = rightStart;
      while (leftSignificant < i && left[leftSignificant] == 0x30) {
        leftSignificant++;
      }
      while (rightSignificant < j && right[rightSignificant] == 0x30) {
        rightSignificant++;
      }
      final leftDigits = left.sublist(leftSignificant, i);
      final rightDigits = right.sublist(rightSignificant, j);
      if (leftDigits.length != rightDigits.length) {
        return leftDigits.length.compareTo(rightDigits.length);
      }
      final numeric = _compareCodePoints(
        String.fromCharCodes(leftDigits),
        String.fromCharCodes(rightDigits),
      );
      if (numeric != 0) return numeric;
      final leftZeroes = leftSignificant - leftStart;
      final rightZeroes = rightSignificant - rightStart;
      if (leftZeroes != rightZeroes) {
        return leftZeroes.compareTo(rightZeroes);
      }
      continue;
    }
    if (leftIsDigit != rightIsDigit) return leftIsDigit ? -1 : 1;

    final leftStart = i;
    final rightStart = j;
    while (i < left.length && !_isAsciiDigitRune(left[i])) {
      i++;
    }
    while (j < right.length && !_isAsciiDigitRune(right[j])) {
      j++;
    }
    final textCompare = _compareTextByLocale(
      String.fromCharCodes(left.sublist(leftStart, i)),
      String.fromCharCodes(right.sublist(rightStart, j)),
      localeTag,
    );
    if (textCompare != 0) return textCompare;
  }
  return (left.length - i).compareTo(right.length - j);
}

int _compareLetterNames(
  String a,
  String b,
  String localeTag, {
  required bool descending,
}) {
  final leftKey = _letterSortKey(a, localeTag);
  final rightKey = _letterSortKey(b, localeTag);
  if (leftKey == null || rightKey == null) {
    // Values without recognized letters remain last in either direction.
    if (leftKey == null && rightKey != null) return 1;
    if (leftKey != null && rightKey == null) return -1;
    final raw = _compareCodePoints(a, b);
    return descending ? -raw : raw;
  }
  final result = _compareTextByLocale(leftKey, rightKey, localeTag);
  return descending ? -result : result;
}

int _compareEmojiNames(
  String a,
  String b,
  String localeTag, {
  required bool descending,
}) {
  final leftTag = _leadingVisibleGrapheme(a);
  final rightTag = _leadingVisibleGrapheme(b);
  final tags = _compareCodePoints(leftTag, rightTag);
  if (tags != 0) return descending ? -tags : tags;
  return _compareLetterNames(a, b, localeTag, descending: descending);
}

int compareSourceNames(
  String a,
  String b, {
  required SourceSortSettings settings,
  required String localeTag,
}) {
  final descending = settings.effectiveSortState.reverse;
  if (settings.nameSortStyle == SourceNameSortStyle.letters) {
    return _compareLetterNames(a, b, localeTag, descending: descending);
  }

  final leftKind = _namePrefixKind(a);
  final rightKind = _namePrefixKind(b);
  int rank(_NamePrefixKind kind) => switch (settings.tagPosition) {
        SourceTagPosition.top => switch (kind) {
            _NamePrefixKind.digit => 0,
            _NamePrefixKind.emoji => 1,
            _NamePrefixKind.ordinary => 2,
          },
        SourceTagPosition.bottom => switch (kind) {
            _NamePrefixKind.ordinary => 0,
            _NamePrefixKind.digit => 1,
            _NamePrefixKind.emoji => 2,
          },
      };
  final leftRank = rank(leftKind);
  final rightRank = rank(rightKind);
  if (leftRank != rightRank) return leftRank.compareTo(rightRank);
  return switch (leftKind) {
    _NamePrefixKind.digit => descending
        ? -_compareNatural(a, b, localeTag)
        : _compareNatural(a, b, localeTag),
    _NamePrefixKind.emoji =>
      _compareEmojiNames(a, b, localeTag, descending: descending),
    _NamePrefixKind.ordinary =>
      _compareLetterNames(a, b, localeTag, descending: descending),
  };
}

List<T> sortSourceItems<T>(
  List<T> items,
  SourceSortSettings settings, {
  required String Function(T item) nameOf,
  required String Function(T item) kindOf,
  required DateTime? Function(T item) modifiedOf,
  required DateTime? Function(T item) createdOf,
  bool Function(T item)? enabledOf,
  String? localeTag,
}) {
  final indexed = [
    for (var i = 0; i < items.length; i++)
      (item: items[i], index: i),
  ];

  int compareNames(String a, String b) => compareSourceNames(
        a,
        b,
        settings: settings,
        localeTag: localeTag ?? LocaleController.I.effectiveTag,
      );

  int compareDates(DateTime? a, DateTime? b, {required bool newestFirst}) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    final result = a.compareTo(b);
    return newestFirst ? -result : result;
  }

  int compareItems(
    ({T item, int index}) a,
    ({T item, int index}) b,
  ) {
    final state = settings.effectiveSortState;
    final reversed = state.reverse;
    final result = switch (state.field) {
      modern_sort.SortField.name => compareNames(
          nameOf(a.item),
          nameOf(b.item),
        ),
      modern_sort.SortField.modified => compareDates(
          modifiedOf(a.item),
          modifiedOf(b.item),
          newestFirst: !reversed,
        ),
      modern_sort.SortField.created => compareDates(
          createdOf(a.item),
          createdOf(b.item),
          newestFirst: !reversed,
        ),
    };

    return result != 0 ? result : a.index.compareTo(b.index);
  }

  List<({T item, int index})> sortBucket(
    List<({T item, int index})> bucket,
  ) {
    final copy = [...bucket];
    copy.sort(compareItems);
    if (settings.enabledFirst && enabledOf != null) {
      final tagSortingActive =
          settings.nameSortStyle == SourceNameSortStyle.tags &&
          settings.effectiveSortState.field == modern_sort.SortField.name;
      if (tagSortingActive) {
        final result = <({T item, int index})>[];
        var start = 0;
        while (start < copy.length) {
          final kind = _namePrefixKind(nameOf(copy[start].item));
          var end = start + 1;
          while (end < copy.length &&
              _namePrefixKind(nameOf(copy[end].item)) == kind) {
            end++;
          }
          final enabled = <({T item, int index})>[];
          final disabled = <({T item, int index})>[];
          for (final entry in copy.sublist(start, end)) {
            (enabledOf(entry.item) ? enabled : disabled).add(entry);
          }
          result
            ..addAll(enabled)
            ..addAll(disabled);
          start = end;
        }
        return result;
      }
      final enabled = <({T item, int index})>[];
      final disabled = <({T item, int index})>[];
      for (final entry in copy) {
        (enabledOf(entry.item) ? enabled : disabled).add(entry);
      }
      return [...enabled, ...disabled];
    }
    return copy;
  }

  final tagSortingActive =
      settings.nameSortStyle == SourceNameSortStyle.tags &&
      settings.effectiveSortState.field == modern_sort.SortField.name;
  if (!settings.groupByType || tagSortingActive) {
    return [
      for (final item in sortBucket(indexed)) item.item,
    ];
  }

  final buckets = <String, List<({T item, int index})>>{};
  final kindOrder = <String>[];

  for (final entry in indexed) {
    final kind = kindOf(entry.item);
    (buckets[kind] ??= []).add(entry);
    if (!kindOrder.contains(kind)) kindOrder.add(kind);
  }

  final orderedKinds = <String>[
    for (final kind in settings.groupOrder)
      if (buckets.containsKey(kind)) kind,
    for (final kind in kindOrder)
      if (!settings.groupOrder.contains(kind)) kind,
  ];

  return [
    for (final kind in orderedKinds)
      for (final item in sortBucket(buckets[kind]!)) item.item,
  ];
}



class _SerializedSourceRow {
  const _SerializedSourceRow({
    required this.name,
    required this.kind,
    required this.createdAt,
    required this.modifiedAt,
    required this.enabled,
  });

  final String name;
  final String kind;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final bool enabled;
}

/// Top-level entry point for Flutter's compute isolate.
List<int> sortSerializedSourceIndices(Map<String, dynamic> payload) {
  final rawItems = payload['items'] as List<dynamic>;
  final items = <_SerializedSourceRow>[];
  for (final value in rawItems) {
    final raw = Map<String, dynamic>.from(value as Map);
    items.add(_SerializedSourceRow(
      name: raw['name']?.toString() ?? '',
      kind: raw['kind']?.toString() ?? '',
      createdAt: DateTime.tryParse(raw['created_at']?.toString() ?? ''),
      modifiedAt: DateTime.tryParse(raw['modified_at']?.toString() ?? ''),
      enabled: raw['enabled'] == true,
    ));
  }

  final settings = SourceSortSettings.fromJson(
    jsonEncode(Map<String, dynamic>.from(payload['settings'] as Map)),
  );
  final sorted = sortSourceItems<_SerializedSourceRow>(
    items,
    settings,
    nameOf: (item) => item.name,
    kindOf: (item) => item.kind,
    createdOf: (item) => item.createdAt,
    modifiedOf: (item) => item.modifiedAt,
    enabledOf: (item) => item.enabled,
    localeTag: payload['locale']?.toString() ?? 'en',
  );
  return [for (final row in sorted) items.indexOf(row)];
}


enum SortField { byDefault, name, modified, created }

enum SortDir { up, down }

enum ActiveFilter { all, active, inactive }

extension ActiveFilterX on ActiveFilter {
  ActiveFilter get next =>
      ActiveFilter.values[(index + 1) % ActiveFilter.values.length];

  String label() => switch (this) {
        ActiveFilter.all => getLocalText.s("Show all sources"),
        ActiveFilter.active => getLocalText.s("Show only active sources"),
        ActiveFilter.inactive => getLocalText.s("Show only inactive sources"),
      };

  bool accepts(bool isActive) => switch (this) {
        ActiveFilter.all => true,
        ActiveFilter.active => isActive,
        ActiveFilter.inactive => !isActive,
      };
}

@immutable
class SortState {
  const SortState(this.field, this.dir);

  final SortField field;
  final SortDir dir;

  @override
  bool operator ==(Object other) =>
      other is SortState && other.field == field && other.dir == dir;

  @override
  int get hashCode => Object.hash(field, dir);
}

/// up = A–Я / oldest, down = Я–А / newest.
SortState sortAfterTap(SortState current, SortField tapped) {
  if (tapped == current.field && tapped != SortField.byDefault) {
    return SortState(
      tapped,
      current.dir == SortDir.up ? SortDir.down : SortDir.up,
    );
  }
  return SortState(
    tapped,
    tapped == SortField.name ? SortDir.up : SortDir.down,
  );
}

IconData sortFieldIcon(SortField field) => switch (field) {
      SortField.byDefault => Icons.swap_vert,
      SortField.name => Icons.sort_by_alpha,
      SortField.modified => Icons.history,
      SortField.created => Icons.calendar_month,
    };

SortState sortStateFromMode(SourceSortMode mode) => switch (mode) {
      SourceSortMode.defaultOrder =>
        const SortState(SortField.byDefault, SortDir.down),
      SourceSortMode.nameAsc => const SortState(SortField.name, SortDir.up),
      SourceSortMode.nameDesc => const SortState(SortField.name, SortDir.down),
      SourceSortMode.modifiedNewest =>
        const SortState(SortField.modified, SortDir.down),
      SourceSortMode.modifiedOldest =>
        const SortState(SortField.modified, SortDir.up),
      SourceSortMode.createdNewest =>
        const SortState(SortField.created, SortDir.down),
      SourceSortMode.createdOldest =>
        const SortState(SortField.created, SortDir.up),
    };

String _sortCaption(SortState state) => switch (state.field) {
      SortField.byDefault => getLocalText.s("Default"),
      SortField.name => getLocalText.s(
          state.dir == SortDir.up ? "Name A–Z" : "Name Z–A",
        ),
      SortField.modified => getLocalText.s(
          state.dir == SortDir.up
              ? "Modified — oldest"
              : "Modified — newest",
        ),
      SortField.created => getLocalText.s(
          state.dir == SortDir.up
              ? "Created — oldest"
              : "Created — newest",
        ),
    };

// Shared 22×11 chevron. The sheet and toolbar use the same painted shape.
class SortChevron extends StatelessWidget {
  const SortChevron({super.key, required this.color});

  final Color color;

  static const double width = 22;
  static const double height = 11;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(width, height),
        painter: _ChevronPainter(color),
      );
}

class _ChevronPainter extends CustomPainter {
  _ChevronPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 16;
    final sy = size.height / 10;
    const points = <Offset>[
      Offset(0.8, 1.2),
      Offset(8, 6),
      Offset(15.2, 1.2),
      Offset(15.2, 2.6),
      Offset(8, 9.6),
      Offset(0.8, 2.6),
    ];

    final path = Path()..moveTo(points.first.dx * sx, points.first.dy * sy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx * sx, point.dy * sy);
    }
    path.close();

    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) =>
      oldDelegate.color != color;
}

const Duration _sortAnimationDuration = Duration(milliseconds: 180);

// The chip's outer height, label slot and chevron slot are fixed. Animations
// change only opacity, rotation and position, never the grid's geometry.
class SortChip extends StatelessWidget {
  const SortChip({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.showArrow,
    required this.dir,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool showArrow;
  final SortDir dir;
  final VoidCallback onTap;

  static const double _height = 60;
  static const double _labelHeight = 32;
  static const double _labelEdge = 5;
  static const double _arrowEdge = 5;
  static const double _arrowGap = 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = selected ? colors.onSecondaryContainer : colors.onSurface;
    final radius = BorderRadius.circular(8);
    final isUp = dir == SortDir.up;

    final labelTop = !showArrow
        ? (_height - _labelHeight) / 2
        : (isUp
            ? _arrowEdge + SortChevron.height + _arrowGap
            : _labelEdge);
    final arrowTop = showArrow && isUp
        ? _arrowEdge
        : _labelEdge + _labelHeight + _arrowGap;

    return AnimatedContainer(
      duration: _sortAnimationDuration,
      height: _height,
      decoration: BoxDecoration(
        color: selected ? colors.secondaryContainer : Colors.transparent,
        borderRadius: radius,
        border: Border.all(
          color: selected ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: _sortAnimationDuration,
                curve: Curves.easeOut,
                left: 0,
                right: 0,
                top: arrowTop,
                height: SortChevron.height,
                child: Center(
                  child: AnimatedOpacity(
                    duration: _sortAnimationDuration,
                    opacity: showArrow ? 1 : 0,
                    child: AnimatedRotation(
                      duration: _sortAnimationDuration,
                      turns: isUp ? 0.5 : 0,
                      child: SortChevron(color: foreground),
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: _sortAnimationDuration,
                curve: Curves.easeOut,
                left: 0,
                right: 0,
                top: labelTop,
                height: _labelHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 18, color: foreground),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontSize: 14,
                              height: 1.0,
                              color: foreground,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SortToolbarButton extends StatelessWidget {
  const SortToolbarButton({
    super.key,
    required this.state,
    required this.onTap,
    required this.onLongPress,
    this.enabled = true,
  });

  final SortState state;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool enabled;

  // 44px hit area, matching the filter control; visible tile is 32×32.
  static const double _size = 44;
  static const double _tileSize = 32;
  static const double _glyph = 18;
  static const double _gap = 1;
  static const double _edge =
      (_tileSize - SortChevron.height - _gap - _glyph) / 2;
  static const BorderRadius _radius =
      BorderRadius.all(Radius.circular(8));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final active = state.field != SortField.byDefault;
    final isUp = state.dir == SortDir.up;
    final foreground = enabled ? colors.onSurfaceVariant : theme.disabledColor;

    final glyphTop = !active
        ? (_tileSize - _glyph) / 2
        : (isUp ? _edge + SortChevron.height + _gap : _edge);
    final arrowTop =
        (active && !isUp) ? _edge + _glyph + _gap : _edge;

    return Semantics(
      button: true,
      label: _sortCaption(state),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: _radius,
          onTap: enabled ? onTap : null,
          onLongPress: enabled ? onLongPress : null,
          child: SizedBox(
            width: _size,
            height: _size,
            child: Center(
              child: AnimatedContainer(
                duration: _sortAnimationDuration,
                width: _tileSize,
                height: _tileSize,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: _radius,
                ),
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: _sortAnimationDuration,
                      curve: Curves.easeOut,
                      left: 0,
                      right: 0,
                      top: arrowTop,
                      height: SortChevron.height,
                      child: Center(
                        child: AnimatedOpacity(
                          duration: _sortAnimationDuration,
                          opacity: active ? 1 : 0,
                          child: AnimatedRotation(
                            duration: _sortAnimationDuration,
                            turns: isUp ? 0.5 : 0,
                            child: SortChevron(color: foreground),
                          ),
                        ),
                      ),
                    ),
                    AnimatedPositioned(
                      duration: _sortAnimationDuration,
                      curve: Curves.easeOut,
                      left: 0,
                      right: 0,
                      top: glyphTop,
                      height: _glyph,
                      child: Center(
                        child: Icon(
                          sortFieldIcon(state.field),
                          size: _glyph,
                          color: foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ActiveFilterButton extends StatelessWidget {
  const ActiveFilterButton({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final ActiveFilter value;
  final ValueChanged<ActiveFilter> onChanged;
  final bool enabled;

  static const _duration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAll = value == ActiveFilter.all;
    final gray = colors.surfaceContainerHighest;
    const lightBlue = Color(0xFFBAC3FF);
    final blue = isDark ? colors.primary : lightBlue;
    final inner = isDark ? Colors.black : Colors.white;
    final innerOutline = isDark ? Colors.white : Colors.black;

    final geometry = switch (value) {
      ActiveFilter.all => const _FilterGeometry(0, 0, 1, 0.070, 0.25),
      ActiveFilter.active => const _FilterGeometry(0.10, 0.12, 0.34, 0.055, 0.13),
      ActiveFilter.inactive => const _FilterGeometry(0.10, 0.54, 0.34, 0.055, 0.13),
    };
    final background = switch (value) {
      ActiveFilter.all => Colors.transparent,
      ActiveFilter.active => blue,
      ActiveFilter.inactive => gray,
    };
    final plateFill = isAll ? gray : inner;
    final plateOutline = isAll ? colors.outline : innerOutline;

    return Semantics(
        button: true,
        label: value.label(),
        value: value.name,
        child: InkResponse(
          onTap: enabled ? () => onChanged(value.next) : null,
          radius: 24,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: AnimatedContainer(
                duration: _duration,
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: _duration,
                      curve: Curves.easeOutCubic,
                      left: 32 * geometry.inset,
                      right: 32 * geometry.inset,
                      top: 32 * geometry.top,
                      height: 32 * geometry.height,
                      child: AnimatedContainer(
                        duration: _duration,
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          color: plateFill,
                          border: Border.all(
                            color: plateOutline,
                            width: 32 * geometry.border,
                          ),
                          borderRadius:
                              BorderRadius.circular(32 * geometry.radius),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    );
  }
}

class _FilterGeometry {
  const _FilterGeometry(
    this.inset,
    this.top,
    this.height,
    this.border,
    this.radius,
  );

  final double inset;
  final double top;
  final double height;
  final double border;
  final double radius;
}

Future<void> showSourceSortOptions(
  BuildContext context, {
  required SourceSortSettings settings,
  required ValueChanged<SourceSortSettings> onChanged,
}) async {
  var local = settings;

  await showAppBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (sheetCtx, setSheetState) {
        void apply(SourceSortSettings next) {
          local = next;
          onChanged(next);
          setSheetState(() {});
        }

        final tagSortingActive =
            local.nameSortStyle == SourceNameSortStyle.tags &&
            local.effectiveSortState.field == modern_sort.SortField.name;

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.85,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Text(
                  getLocalText.s("Sort options"),
                  style: Theme.of(sheetCtx).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                modern_sort.SortChips(
                  state: local.sortState,
                  onChanged: (next) =>
                      apply(local.copyWith(sortState: next)),
                ),
                const Divider(height: 24),
                Text(
                  getLocalText.s("Name sorting"),
                  style: Theme.of(sheetCtx).textTheme.titleSmall,
                ),
                CheckboxListTile(
                  value: local.nameSortStyle == SourceNameSortStyle.tags,
                  onChanged: (value) => apply(local.copyWith(
                    nameSortStyle: value == true
                        ? SourceNameSortStyle.tags
                        : SourceNameSortStyle.letters,
                  )),
                  title: Text(getLocalText.s("Sort by tags")),
                  subtitle: Text(getLocalText.s(
                    local.nameSortStyle == SourceNameSortStyle.tags
                        ? "When sorting by name, tag mode keeps the list flat."
                        : "Letter mode ignores leading numbers, emoji and punctuation.",
                  )),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: local.nameSortStyle == SourceNameSortStyle.tags
                      ? Padding(
                          padding: const EdgeInsets.only(left: 16, bottom: 8),
                          child: Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                label: Text(getLocalText.s("Tags at top")),
                                selected: local.tagPosition == SourceTagPosition.top,
                                onSelected: (_) => apply(local.copyWith(
                                  tagPosition: SourceTagPosition.top,
                                )),
                              ),
                              ChoiceChip(
                                label: Text(getLocalText.s("Tags at bottom")),
                                selected: local.tagPosition == SourceTagPosition.bottom,
                                onSelected: (_) => apply(local.copyWith(
                                  tagPosition: SourceTagPosition.bottom,
                                )),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const Divider(height: 24),
                CheckboxListTile(
                  value: local.enabledFirst,
                  onChanged: (value) =>
                      apply(local.copyWith(enabledFirst: value ?? false)),
                  title: Text(getLocalText.s("Enabled first")),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                if (!tagSortingActive) ...[
                  CheckboxListTile(
                    value: local.groupByType,
                    onChanged: (value) =>
                        apply(local.copyWith(groupByType: value ?? false)),
                    title: Text(getLocalText.s("Group by type")),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: local.groupByType
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                getLocalText.s("Group order"),
                                style: Theme.of(sheetCtx).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 4),
                              ReorderableListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                buildDefaultDragHandles: false,
                                itemCount: local.groupOrder.length,
                                onReorderItem: (oldIndex, newIndex) {
                                  final next = [...local.groupOrder];
                                  final moved = next.removeAt(oldIndex);
                                  next.insert(newIndex, moved);
                                  apply(local.copyWith(
                                    groupOrder: List<String>.unmodifiable(next),
                                  ));
                                },
                                itemBuilder: (_, index) {
                                  final kind = local.groupOrder[index];
                                  return ListTile(
                                    key: ValueKey(kind),
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(sourceTypeIcon(kind), size: 20),
                                    title: Text(sourceTypeLabel(kind)),
                                    trailing: ReorderableDragStartListener(
                                      index: index,
                                      child: const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: Icon(Icons.drag_handle),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
