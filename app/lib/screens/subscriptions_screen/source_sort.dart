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
    this.groupByActive = false,
    this.groupOrder = defaultSourceGroupOrder,
    this.chipStyle = SortChipStyle.calm,
  });

  final SourceSortMode mode;
  final bool groupByType;
  final bool groupByActive;
  final List<String> groupOrder;
  final SortChipStyle chipStyle;

  SourceSortSettings copyWith({
    SourceSortMode? mode,
    bool? groupByType,
    bool? groupByActive,
    List<String>? groupOrder,
    SortChipStyle? chipStyle,
  }) =>
      SourceSortSettings(
        mode: mode ?? this.mode,
        groupByType: groupByType ?? this.groupByType,
        groupByActive: groupByActive ?? this.groupByActive,
        groupOrder: groupOrder ?? this.groupOrder,
        chipStyle: chipStyle ?? this.chipStyle,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'group_by_type': groupByType,
        'group_by_active': groupByActive,
        'group_order': groupOrder,
        'chip_style': chipStyle.name,
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
      final chipStyle = SortChipStyle.values.firstWhere(
        (s) => s.name == decoded['chip_style'],
        orElse: () => SortChipStyle.calm,
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
        groupByActive: decoded['group_by_active'] == true,
        groupOrder: List<String>.unmodifiable(order),
        chipStyle: chipStyle,
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
  bool Function(T item)? enabledOf,
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
    if (settings.groupByType && settings.groupByActive && enabledOf != null) {
      // Stable partition: enabled entries first, retaining each side's order.
      final enabled = <({T item, int index})>[];
      final disabled = <({T item, int index})>[];
      for (final entry in copy) {
        (enabledOf(entry.item) ? enabled : disabled).add(entry);
      }
      return [...enabled, ...disabled];
    }
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
      SourceSortMode.nameAsc => const SortState(SortField.name, SortDir.down),
      SourceSortMode.nameDesc => const SortState(SortField.name, SortDir.up),
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
        state.dir == SortDir.down
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
      SortField.name => getLocalText.s(
          state.dir == SortDir.down ? "Name A–Z" : "Name Z–A",
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

  // Геометрия постоянная для обоих вариантов. Зарезервированные зоны стрелки
  // не участвуют в расчёте высоты и не заставляют сетку менять размер.
  static const double _h = 60;
  static const double _labelH = 20;
  static const double _arrowH = 16;
  static const double _edge = 6;
  static const _anim = Duration(milliseconds: 150);

  double get _labelTop {
    const center = (_h - _labelH) / 2; // 20
    if (!showArrow || style == SortChipStyle.calm) return center;

    // lively: стрелка ↑ над надписью, надпись у нижнего края;
    // стрелка ↓ под надписью, надпись у верхнего края.
    return dir == SortDir.up ? _h - _edge - _labelH : _edge;
  }

  double get _arrowTop {
    if (style == SortChipStyle.calm) {
      const center = (_h - _labelH) / 2; // 20
      return dir == SortDir.up
          ? center - _arrowH // 4: стрелка сверху
          : center + _labelH; // 40: стрелка снизу
    }

    return dir == SortDir.up
        ? _edge // 6: стрелка сверху
        : _h - _edge - _arrowH; // 38: стрелка снизу
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final foreground = selected ? cs.onSecondaryContainer : cs.onSurface;
    final arrowColor = selected ? cs.primary : foreground;
    final radius = BorderRadius.circular(8);

    return AnimatedContainer(
      duration: _anim,
      height: _h,
      decoration: BoxDecoration(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: radius,
        border: Border.all(
          color: selected ? cs.primary : cs.outlineVariant,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Stack(
            children: [
              // Стрелка всегда занимает собственный слот. Скрытие делается
              // только opacity, а положение плавно меняется через top.
              AnimatedPositioned(
                duration: _anim,
                curve: Curves.easeOut,
                left: 0,
                right: 0,
                top: _arrowTop,
                height: _arrowH,
                child: AnimatedOpacity(
                  duration: _anim,
                  opacity: showArrow ? 1 : 0,
                  child: Icon(
                    dir == SortDir.up
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    size: _arrowH,
                    color: arrowColor,
                  ),
                ),
              ),

              // Иконка поля и подпись перемещаются вместе — именно подпись
              // меняет край в lively. В calm top всегда остаётся 20.
              AnimatedPositioned(
                duration: _anim,
                curve: Curves.easeOut,
                left: 0,
                right: 0,
                top: _labelTop,
                height: _labelH,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 18, color: foreground),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontSize: label == getLocalText.s("Default") ? 12 : 14,
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
            ],
          ),
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        getLocalText.s("Sort options"),
                        style: Theme.of(sheetCtx).textTheme.titleMedium,
                      ),
                    ),
                    Tooltip(
                      message: local.chipStyle == SortChipStyle.calm
                          ? getLocalText.s("Switch to lively sort animation")
                          : getLocalText.s("Switch to calm sort animation"),
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: () => apply(
                          local.copyWith(
                            chipStyle: local.chipStyle == SortChipStyle.calm
                                ? SortChipStyle.lively
                                : SortChipStyle.calm,
                          ),
                        ),
                        icon: Icon(
                          Icons.animation,
                          color: local.chipStyle == SortChipStyle.lively
                              ? Theme.of(sheetCtx).colorScheme.primary
                              : null,
                        ),
                      ),
                    ),
                  ],
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
                            SortDir.down,
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
                            style: local.chipStyle,
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
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: local.groupByType
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 32),
                              child: CheckboxListTile(
                                value: local.groupByActive,
                                onChanged: (value) => apply(local.copyWith(
                                  groupByActive: value ?? false,
                                )),
                                title: Text(getLocalText.s("Group by active state")),
                                controlAffinity: ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                              ),
                            ),
                            const SizedBox(height: 4),
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
            ),
          ),
        );
      },
    ),
  );
}
