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
    this.activeFilter = ActiveFilter.all,
  });

  final SourceSortMode mode;
  final bool groupByType;
  final bool groupByActive;
  final List<String> groupOrder;
  final ActiveFilter activeFilter;

  SourceSortSettings copyWith({
    SourceSortMode? mode,
    bool? groupByType,
    bool? groupByActive,
    List<String>? groupOrder,
    ActiveFilter? activeFilter,
  }) =>
      SourceSortSettings(
        mode: mode ?? this.mode,
        groupByType: groupByType ?? this.groupByType,
        groupByActive: groupByActive ?? this.groupByActive,
        groupOrder: groupOrder ?? this.groupOrder,
        activeFilter: activeFilter ?? this.activeFilter,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'group_by_type': groupByType,
        'group_by_active': groupByActive,
        'group_order': groupOrder,
        'active_filter': activeFilter.name,
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
      final activeFilter = ActiveFilter.values.firstWhere(
        (f) => f.name == decoded['active_filter'],
        orElse: () => ActiveFilter.all,
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
        activeFilter: activeFilter,
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
    settings.activeFilter != ActiveFilter.all ||
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

SortState _sortStateFromMode(SourceSortMode mode) => switch (mode) {
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

// Shared, fixed-geometry chevron for both the sort sheet and toolbar.
class SortChevron extends StatelessWidget {
  const SortChevron({super.key, required this.color});

  final Color color;

  static const double width = 24;
  static const double height = 12;

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

// Every animated element moves inside a permanently 60 px high chip.
// Only opacity, rotation and top offsets change; the grid geometry stays fixed.
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
  static const double _labelHeight = 20;
  static const double _labelEdge = 6;
  static const double _arrowEdge = 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = selected ? colors.onSecondaryContainer : colors.onSurface;
    final radius = BorderRadius.circular(8);
    final isUp = dir == SortDir.up;

    final labelTop = !showArrow
        ? (_height - _labelHeight) / 2
        : (isUp ? _height - _labelEdge - _labelHeight : _labelEdge);
    final arrowTop = (showArrow && !isUp)
        ? _height - _arrowEdge - SortChevron.height
        : _arrowEdge;

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
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
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

class SortToolbarButton extends StatelessWidget {
  const SortToolbarButton({
    super.key,
    required this.state,
    required this.onTap,
    this.enabled = true,
  });

  final SortState state;
  final VoidCallback onTap;
  final bool enabled;

  static const double _size = 48;
  static const double _glyph = 22;
  static const double _gap = 4;
  static const double _edge =
      (_size - SortChevron.height - _gap - _glyph) / 2;
  static const BorderRadius _radius =
      BorderRadius.all(Radius.circular(14));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final active = state.field != SortField.byDefault;
    final isUp = state.dir == SortDir.up;
    final foreground = !enabled
        ? theme.disabledColor
        : active
            ? colors.onSecondaryContainer
            : colors.onSurfaceVariant;

    final glyphTop = !active
        ? (_size - _glyph) / 2
        : (isUp ? _edge + SortChevron.height + _gap : _edge);
    final arrowTop =
        (active && !isUp) ? _edge + _glyph + _gap : _edge;

    return Tooltip(
      message: _sortCaption(state),
      child: AnimatedContainer(
        duration: _sortAnimationDuration,
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          color: active ? colors.secondaryContainer : Colors.transparent,
          borderRadius: _radius,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: _radius,
            onTap: enabled ? onTap : null,
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
    final isAll = value == ActiveFilter.all;
    final isActive = value == ActiveFilter.active;
    final gray = colors.surfaceContainerHighest;
    final blue = colors.primary;
    final inner = Theme.of(context).brightness == Brightness.dark
        ? Colors.black
        : colors.onSurfaceVariant;

    return Tooltip(
      message: value.label(),
      child: Semantics(
        button: true,
        label: value.label(),
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
                  color: isActive ? blue : gray,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isAll ? colors.outline : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: AnimatedOpacity(
                    duration: _duration,
                    opacity: isAll ? 0 : 1,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: inner,
                        borderRadius: BorderRadius.circular(4.5),
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
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
    isScrollControlled: true,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (sheetCtx, setSheetState) {
        void apply(SourceSortSettings next) {
          local = next;
          onChanged(next);
          setSheetState(() {});
        }

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
                      onSortChanged(sortAfterTap(sortState, field));
                    }

                    Widget chip(
                      SortField field,
                      IconData icon,
                      String label,
                    ) =>
                        Expanded(
                          child: SortChip(
                            icon: icon,
                            label: label,
                            selected: sortState.field == field,
                            showArrow: sortState.field == field &&
                                field != SortField.byDefault,
                            dir: sortState.dir,
                            onTap: () => onChipTap(field),
                          ),
                        );

                    return Column(
                      children: [
                        SizedBox(
                          height: 24,
                          child: AnimatedSwitcher(
                            duration: _sortAnimationDuration,
                            child: Align(
                              key: ValueKey(_sortCaption(sortState)),
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _sortCaption(sortState),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                              ),
                            ),
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
            ),
          ),
        );
      },
    ),
  );
}
