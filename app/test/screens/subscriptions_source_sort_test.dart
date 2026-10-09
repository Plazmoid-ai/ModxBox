import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
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

    test(
      'group by active state stably moves enabled entries to top of each type',
      () {
      final items = [
        _Item('Disabled first', 'server', null, null, enabled: false),
        _Item('Enabled A', 'server', null, null),
        _Item('Enabled B', 'server', null, null),
        _Item('Disabled second', 'server', null, null, enabled: false),
      ];
        final sorted = _apply(
          items,
          const SourceSortSettings(
            groupByType: true,
            groupByActive: true,
          ),
        );
        expect(
          sorted.map((e) => e.name).toList(),
          ['Enabled A', 'Enabled B', 'Disabled first', 'Disabled second'],
        );
      },
    );

    test('default mode preserves relative order inside each group', () {
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
          'server:Zulu',
          'server:Beta',
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
        groupByActive: true,
        activeFilter: ActiveFilter.inactive,
      );
      final restored = SourceSortSettings.fromJson(jsonEncode(source.toJson()));

      expect(restored.mode, SourceSortMode.createdNewest);
      expect(restored.groupByActive, isTrue);
      expect(restored.activeFilter, ActiveFilter.inactive);
    });

    test('older settings ignore obsolete chip animation and default options', () {
      final restored = SourceSortSettings.fromJson(
        '{"mode":"nameAsc","chip_style":"lively"}',
      );

      expect(restored.mode, SourceSortMode.nameAsc);
      expect(restored.groupByActive, isFalse);
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
