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


enum SortField { byDefault, name, modified, created }

enum SortDir { up, down }

enum SortChipStyle { calm, lively }

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

SortState _sortStateFromMode(SourceSortMode mode) => switch (mode) {
      SourceSortMode.defaultOrder =>
        const SortState(SortField.byDefault, SortDir.up),
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

SourceSortMode _sourceSortModeFromState(SortState state) => switch (state.field) {
      SortField.byDefault => SourceSortMode.defaultOrder,
      SortField.name =>
        state.dir == SortDir.up
            ? SourceSortMode.nameAsc
            : SourceSortMode.nameDesc,
      SortField.modified =>
        state.dir == SortDir.up
            ? SourceSortMode.modifiedOldest
            : SourceSortMode.modifiedNewest,
      SortField.created =>
        state.dir == SortDir.up
            ? SourceSortMode.createdOldest
            : SourceSortMode.createdNewest,
    };

String _sortCaption(SortState state) => switch (state.field) {
      SortField.byDefault => getLocalText.s("Default"),
      SortField.name =>
        state.dir == SortDir.up ? "Имя А–Я" : "Имя Я–А",
      SortField.modified =>
        state.dir == SortDir.up
            ? "Изменено — сначала старые"
            : "Изменено — сначала новые",
      SortField.created =>
        state.dir == SortDir.up
            ? "Создано — сначала старые"
            : "Создано — сначала новые",
    };

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.showArrow,
    required this.dir,
    required this.style,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool showArrow;
  final SortDir dir;
  final SortChipStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final foreground =
        selected ? colorScheme.onSecondaryContainer : colorScheme.onSurface;
    final background =
        selected ? colorScheme.secondaryContainer : colorScheme.surface;
    final borderColor =
        selected ? colorScheme.secondary : colorScheme.outlineVariant;

    final chipLabel = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: theme.textTheme.labelLarge?.copyWith(
        color: foreground,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
    );

    Widget content;
    if (style == SortChipStyle.calm) {
      final arrow = Icon(
        dir == SortDir.up ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
        size: 16,
        color: colorScheme.primary,
      );

      content = Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(
              top: showArrow && dir == SortDir.down ? 2 : 0,
              bottom: showArrow && dir == SortDir.up ? 2 : 0,
              left: 28,
              right: 28,
            ),
            child: chipLabel,
          ),
          Positioned(
            left: 10,
            child: Icon(
              icon,
              size: 18,
              color: foreground,
            ),
          ),
          if (showArrow)
            Positioned(
              top: dir == SortDir.up ? 1 : null,
              bottom: dir == SortDir.down ? 1 : null,
              child: arrow,
            ),
        ],
      );
    } else {
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 18,
            color: foreground,
          ),
          const SizedBox(width: 6),
          Flexible(child: chipLabel),
          if (showArrow) ...[
            const SizedBox(width: 4),
            Icon(
              dir == SortDir.up
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
              size: 18,
              color: colorScheme.primary,
            ),
          ],
        ],
      );
    }

    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 48,
          child: Center(child: content),
        ),
      ),
    );
  }
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
                const SizedBox(height: 4),
                Builder(
                  builder: (context) {
                    var sortState = _sortStateFromMode(local.mode);

                    void onSortChanged(SortState next) {
                      sortState = next;
                      apply(
                        local.copyWith(
                          mode: _sourceSortModeFromState(next),
                        ),
                      );
                    }

                    void onChipTap(SortField field) {
                      if (field == sortState.field &&
                          field != SortField.byDefault) {
                        onSortChanged(
                          SortState(
                            field,
                            sortState.dir == SortDir.up
                                ? SortDir.down
                                : SortDir.up,
                          ),
                        );
                      } else {
                        onSortChanged(
                          SortState(
                            field,
                            field == SortField.name
                                ? SortDir.up
                                : SortDir.down,
                          ),
                        );
                      }
                    }

                    Widget chip(
                      SortField field,
                      IconData icon,
                      String label,
                    ) =>
                        Expanded(
                          child: _SortChip(
                            icon: icon,
                            label: label,
                            selected: sortState.field == field,
                            showArrow: sortState.field == field &&
                                field != SortField.byDefault,
                            dir: sortState.dir,
                            style: SortChipStyle.calm,
                            onTap: () => onChipTap(field),
                          ),
                        );

                    return Column(
                      children: [
                        Text(
                          _sortCaption(sortState),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            chip(
                              SortField.byDefault,
                              Icons.swap_vert,
                              getLocalText.s("Default"),
                            ),
                            const SizedBox(width: 8),
                            chip(
                              SortField.name,
                              Icons.sort_by_alpha,
                              "Имя",
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            chip(
                              SortField.modified,
                              Icons.history,
                              "Изменено",
                            ),
                            const SizedBox(width: 8),
                            chip(
                              SortField.created,
                              Icons.calendar_month,
                              "Создано",
                            ),
                          ],
                        ),
                      ],
                    );
                  },
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
