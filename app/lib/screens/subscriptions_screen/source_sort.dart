import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/l10n/locale_controller.dart';
import '../../widgets/app_bottom_sheet.dart';

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

class SourceSortSettings {
  const SourceSortSettings({
    this.mode = SourceSortMode.defaultOrder,
    this.groupByType = false,
    this.groupOrder = defaultSourceGroupOrder,
  });

  final SourceSortMode mode;
  final bool groupByType;
  final List<String> groupOrder;

  SourceSortSettings copyWith({
    SourceSortMode? mode,
    bool? groupByType,
    List<String>? groupOrder,
  }) =>
      SourceSortSettings(
        mode: mode ?? this.mode,
        groupByType: groupByType ?? this.groupByType,
        groupOrder: groupOrder ?? this.groupOrder,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'group_by_type': groupByType,
        'group_order': groupOrder,
      };

  static SourceSortSettings fromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const SourceSortSettings();

      final modeName = decoded['mode'];
      final mode = SourceSortMode.values.firstWhere(
        (m) => m.name == modeName,
        orElse: () => SourceSortMode.defaultOrder,
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
        groupByType: decoded['group_by_type'] == true,
        groupOrder: List<String>.unmodifiable(order),
      );
    } catch (_) {
      return const SourceSortSettings();
    }
  }
}

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
    settings.mode != SourceSortMode.defaultOrder ||
    settings.groupByType ||
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

List<T> sortSourceItems<T>(
  List<T> items,
  SourceSortSettings settings, {
  required String Function(T item) nameOf,
  required String Function(T item) kindOf,
  required DateTime? Function(T item) modifiedOf,
  required DateTime? Function(T item) createdOf,
}) {
  final indexed = [
    for (var i = 0; i < items.length; i++)
      (item: items[i], index: i),
  ];

  int compareNames(String a, String b) {
    final lower = a.toLowerCase().compareTo(b.toLowerCase());
    if (lower != 0) return lower;
    return a.compareTo(b);
  }

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
    final result = switch (settings.mode) {
      SourceSortMode.defaultOrder => 0,
      SourceSortMode.nameAsc =>
        compareNames(nameOf(a.item), nameOf(b.item)),
      SourceSortMode.nameDesc =>
        compareNames(nameOf(b.item), nameOf(a.item)),
      SourceSortMode.modifiedNewest => compareDates(
          modifiedOf(a.item),
          modifiedOf(b.item),
          newestFirst: true,
        ),
      SourceSortMode.modifiedOldest => compareDates(
          modifiedOf(a.item),
          modifiedOf(b.item),
          newestFirst: false,
        ),
      SourceSortMode.createdNewest => compareDates(
          createdOf(a.item),
          createdOf(b.item),
          newestFirst: true,
        ),
      SourceSortMode.createdOldest => compareDates(
          createdOf(a.item),
          createdOf(b.item),
          newestFirst: false,
        ),
    };

    return result != 0 ? result : a.index.compareTo(b.index);
  }

  List<({T item, int index})> sortBucket(
    List<({T item, int index})> bucket,
  ) {
    final copy = [...bucket];
    copy.sort(compareItems);
    return copy;
  }

  if (!settings.groupByType) {
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

Future<void> showSourceSortOptions(
  BuildContext context, {
  required SourceSortSettings settings,
  required ValueChanged<SourceSortSettings> onChanged,
}) async {
  var local = settings;

  await showAppBottomSheet<void>(
    context: context,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (sheetCtx, setSheetState) {
        void apply(SourceSortSettings next) {
          local = next;
          onChanged(next);
          setSheetState(() {});
        }

        return SafeArea(
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
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final mode in SourceSortMode.values)
                      ChoiceChip(
                        avatar: Icon(mode.icon, size: 16),
                        label: Text(mode.label()),
                        selected: local.mode == mode,
                        onSelected: (_) =>
                            apply(local.copyWith(mode: mode)),
                      ),
                  ],
                ),
                const Divider(height: 24),
                CheckboxListTile(
                  value: local.groupByType,
                  onChanged: (value) =>
                      apply(local.copyWith(groupByType: value ?? false)),
                  title: Text(getLocalText.s("Group by type")),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                if (local.groupByType) ...[
                  const SizedBox(height: 4),
                  Text(
                    getLocalText.s("Group order"),
                    style: Theme.of(sheetCtx).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: true,
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
                        trailing: const Icon(Icons.drag_handle),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}
