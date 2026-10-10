import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/widgets/sort_widgets.dart' as modern_sort;
import 'package:lxbox/screens/subscriptions_screen/source_sort.dart';

class _Item {
  _Item(
    this.name,
    this.kind,
    this.createdAt,
    this.modifiedAt, {
    this.enabled = true,
  });

  final String name;
  final String kind;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final bool enabled;
}

List<_Item> _apply(
  List<_Item> items,
  SourceSortSettings settings,
) =>
    sortSourceItems(
      items,
      settings,
      nameOf: (item) => item.name,
      kindOf: (item) => item.kind,
      createdOf: (item) => item.createdAt,
      modifiedOf: (item) => item.modifiedAt,
      enabledOf: (item) => item.enabled,
    );

void main() {
  group('SourceSortMode', () {
    test('cycles through all modes and back to default', () {
      var mode = SourceSortMode.defaultOrder;
      final seen = <SourceSortMode>[];
      for (var i = 0; i < SourceSortMode.values.length; i++) {
        seen.add(mode);
        mode = mode.next;
      }
      expect(seen, SourceSortMode.values);
      expect(mode, SourceSortMode.defaultOrder);
    });
  });

  group('SortState', () {
    test('first name tap selects A–Z and the next tap reverses it', () {
      const initial = SortState(SortField.byDefault, SortDir.down);
      final ascending = sortAfterTap(initial, SortField.name);

      expect(ascending, const SortState(SortField.name, SortDir.up));
      expect(
        sortAfterTap(ascending, SortField.name),
        const SortState(SortField.name, SortDir.down),
      );
    });

    test('date sorting defaults to newest and repeats to oldest', () {
      const initial = SortState(SortField.byDefault, SortDir.down);
      final newest = sortAfterTap(initial, SortField.modified);

      expect(newest, const SortState(SortField.modified, SortDir.down));
      expect(
        sortAfterTap(newest, SortField.modified),
        const SortState(SortField.modified, SortDir.up),
      );
    });

    test('stored modes map to their intended directions', () {
      expect(
        sortStateFromMode(SourceSortMode.nameAsc),
        const SortState(SortField.name, SortDir.up),
      );
      expect(
        sortStateFromMode(SourceSortMode.nameDesc),
        const SortState(SortField.name, SortDir.down),
      );
      expect(
        sortStateFromMode(SourceSortMode.modifiedNewest),
        const SortState(SortField.modified, SortDir.down),
      );
    });
  });

  group('Animated sort state', () {
    test('select remembers reverse direction separately for every field', () {
      const initial = modern_sort.SortState();
      expect(initial.field, modern_sort.SortField.name);
      expect(initial.reverse, isFalse);

      final reversedName = initial.toggleReverse();
      expect(reversedName.reverse, isTrue);

      final modified = reversedName.select(modern_sort.SortField.modified);
      expect(modified.field, modern_sort.SortField.modified);
      expect(modified.reverse, isFalse);
      expect(modified.isReversed(modern_sort.SortField.name), isTrue);

      final backToName = modified.select(modern_sort.SortField.name);
      expect(backToName.reverse, isTrue);
    });

    test('next cycles fields without changing any reverse flag', () {
      final state = const modern_sort.SortState().toggleReverse();
      final modified = state.next();
      expect(modified.field, modern_sort.SortField.modified);
      expect(modified.reverse, isFalse);
      expect(modified.isReversed(modern_sort.SortField.name), isTrue);
      expect(modified.next().field, modern_sort.SortField.created);
      expect(modified.next().next().field, modern_sort.SortField.name);
    });

    test('state round-trips through JSON and reads the previous dirs schema', () {
      final flipped = const modern_sort.SortState()
          .select(modern_sort.SortField.created)
          .toggleReverse();

      final restored = modern_sort.SortState.fromJson(
        Map<String, dynamic>.from(flipped.toJson()),
      );
      expect(restored.field, flipped.field);
      expect(restored.reverse, isTrue);
      expect(restored.isReversed(modern_sort.SortField.name), isFalse);

      final migrated = modern_sort.SortState.fromJson({
        'field': 'modified',
        'dirs': {
          'name': 'down',
          'modified': 'up',
          'created': 'down',
        },
      });
      expect(migrated.field, modern_sort.SortField.modified);
      expect(migrated.reverse, isTrue);
      expect(migrated.isReversed(modern_sort.SortField.name), isFalse);
    });
  });

  group('sortSourceItems', () {
    final createdOld = DateTime.utc(2025, 1, 1);
    final createdNew = DateTime.utc(2026, 1, 1);
    final modifiedOld = DateTime.utc(2026, 1, 2);
    final modifiedNew = DateTime.utc(2026, 2, 1);

    late List<_Item> items;

    setUp(() {
      items = [
        _Item('Zulu', 'server', createdNew, modifiedOld),
        _Item('Alpha', 'folder', createdOld, modifiedNew),
        _Item('Beta', 'server', createdOld, modifiedOld),
        _Item('Gamma', 'chain', null, null),
      ];
    });

    test('sorts names in both directions', () {
      expect(
        _apply(
          items,
          const SourceSortSettings(mode: SourceSortMode.nameAsc),
        ).map((e) => e.name).toList(),
        ['Alpha', 'Beta', 'Gamma', 'Zulu'],
      );
      expect(
        _apply(
          items,
          const SourceSortSettings(mode: SourceSortMode.nameDesc),
        ).map((e) => e.name).toList(),
        ['Zulu', 'Gamma', 'Beta', 'Alpha'],
      );
    });

    test('sorts modified dates newest and oldest, unknown dates last', () {
      expect(
        _apply(
          items,
          const SourceSortSettings(mode: SourceSortMode.modifiedNewest),
        ).map((e) => e.name).toList(),
        ['Alpha', 'Zulu', 'Beta', 'Gamma'],
      );
      expect(
        _apply(
          items,
          const SourceSortSettings(mode: SourceSortMode.modifiedOldest),
        ).map((e) => e.name).toList(),
        ['Zulu', 'Beta', 'Alpha', 'Gamma'],
      );
    });

    test('groups by type in configured order and sorts inside groups', () {
      final settings = SourceSortSettings(
        mode: SourceSortMode.nameAsc,
        groupByType: true,
        groupOrder: const ['chain', 'server', 'folder', 'subscription'],
      );
      expect(
        _apply(items, settings)
            .map((e) => '${e.kind}:${e.name}')
            .toList(),
        [
          'chain:Gamma',
          'server:Beta',
          'server:Zulu',
          'folder:Alpha',
        ],
      );
    });

    test('enabled first stably partitions each type when grouping is on', () {
      final items = [
        _Item('Disabled first', 'server', null, null, enabled: false),
        _Item('Enabled A', 'server', null, null),
        _Item('Enabled B', 'server', null, null),
        _Item('Disabled second', 'server', null, null, enabled: false),
        _Item('Disabled folder', 'folder', null, null, enabled: false),
        _Item('Enabled folder', 'folder', null, null),
      ];
      final sorted = _apply(
        items,
        const SourceSortSettings(
          groupByType: true,
          enabledFirst: true,
          groupOrder: ['server', 'folder', 'subscription', 'chain'],
        ),
      );
      expect(
        sorted.map((e) => e.name).toList(),
        [
          'Enabled A',
          'Enabled B',
          'Disabled first',
          'Disabled second',
          'Enabled folder',
          'Disabled folder',
        ],
      );
    });

    test('enabled first also works with grouping disabled', () {
      final items = [
        _Item('Disabled first', 'server', null, null, enabled: false),
        _Item('Enabled A', 'server', null, null),
        _Item('Disabled folder', 'folder', null, null, enabled: false),
        _Item('Enabled B', 'server', null, null),
      ];
      final sorted = _apply(
        items,
        const SourceSortSettings(enabledFirst: true),
      );
      expect(
        sorted.map((e) => e.name).toList(),
        ['Enabled A', 'Enabled B', 'Disabled first', 'Disabled folder'],
      );
    });

    test('legacy group_by_active setting maps to enabled first', () {
      final settings = SourceSortSettings.fromJson(
        '{"group_by_active":true}',
      );
      expect(settings.enabledFirst, isTrue);
    });

    test('initial mode sorts names A–Z inside each group', () {
      final settings = SourceSortSettings(
        groupByType: true,
        groupOrder: const ['folder', 'server', 'chain', 'subscription'],
      );
      expect(
        _apply(items, settings)
            .map((e) => '${e.kind}:${e.name}')
            .toList(),
        [
          'folder:Alpha',
          'server:Beta',
          'server:Zulu',
          'chain:Gamma',
        ],
      );
    });
  });

  group('ActiveFilter', () {
    test('cycles all -> active -> inactive -> all', () {
      expect(ActiveFilter.all.next, ActiveFilter.active);
      expect(ActiveFilter.active.next, ActiveFilter.inactive);
      expect(ActiveFilter.inactive.next, ActiveFilter.all);
    });

    test('accepts sources according to selected filter', () {
      expect(ActiveFilter.all.accepts(true), isTrue);
      expect(ActiveFilter.all.accepts(false), isTrue);
      expect(ActiveFilter.active.accepts(true), isTrue);
      expect(ActiveFilter.active.accepts(false), isFalse);
      expect(ActiveFilter.inactive.accepts(true), isFalse);
      expect(ActiveFilter.inactive.accepts(false), isTrue);
    });
  });

  group('SourceSortSettings', () {
    test('persists sorting options and active filter', () {
      final source = SourceSortSettings(
        mode: SourceSortMode.createdNewest,
        enabledFirst: true,
        activeFilter: ActiveFilter.inactive,
      );
      final restored = SourceSortSettings.fromJson(jsonEncode(source.toJson()));

      expect(restored.mode, SourceSortMode.createdNewest);
      expect(restored.enabledFirst, isTrue);
      expect(restored.activeFilter, ActiveFilter.inactive);
    });

    test('persists independently remembered reverse flags for every field', () {
      final state = const modern_sort.SortState()
          .select(modern_sort.SortField.modified)
          .toggleReverse()
          .select(modern_sort.SortField.created);
      final source = const SourceSortSettings().copyWith(sortState: state);
      final restored =
          SourceSortSettings.fromJson(jsonEncode(source.toJson()));

      expect(restored.sortState.field, modern_sort.SortField.created);
      expect(restored.sortState.isReversed(modern_sort.SortField.created),
          isFalse);
      expect(restored.sortState.isReversed(modern_sort.SortField.modified),
          isTrue);
      expect(restored.sortState.isReversed(modern_sort.SortField.name), isFalse);
      expect(restored.mode, SourceSortMode.createdNewest);
    });

    test('legacy name modes preserve A–Z and Z–A meanings', () {
      final ascending = SourceSortSettings.fromJson('{"mode":"nameAsc"}');
      final descending = SourceSortSettings.fromJson('{"mode":"nameDesc"}');

      expect(ascending.sortState.field, modern_sort.SortField.name);
      expect(ascending.sortState.reverse, isFalse);
      expect(descending.sortState.field, modern_sort.SortField.name);
      expect(descending.sortState.reverse, isTrue);
    });

    test('older settings ignore obsolete chip animation and default options', () {
      final restored = SourceSortSettings.fromJson(
        '{"mode":"nameAsc","chip_style":"lively"}',
      );

      expect(restored.mode, SourceSortMode.nameAsc);
      expect(restored.enabledFirst, isFalse);
      expect(restored.activeFilter, ActiveFilter.all);
    });

    test('repairs an incomplete group order while decoding', () {
      final settings = SourceSortSettings.fromJson(
        '{"mode":"createdNewest","group_by_type":true,'
        '"group_order":["chain","server","chain"]}',
      );
      expect(settings.mode, SourceSortMode.createdNewest);
      expect(settings.groupByType, isTrue);
      expect(
        settings.groupOrder,
        ['chain', 'server', 'folder', 'subscription'],
      );
    });
  });
}
