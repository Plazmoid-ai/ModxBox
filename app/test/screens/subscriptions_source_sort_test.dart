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

  group('SourceSortSettings', () {
    test('persists selected sort chip animation style', () {
      final source = SourceSortSettings(
        mode: SourceSortMode.createdNewest,
        chipStyle: SortChipStyle.lively,
        groupByActive: true,
      );
      final restored = SourceSortSettings.fromJson(jsonEncode(source.toJson()));

      expect(restored.mode, SourceSortMode.createdNewest);
      expect(restored.chipStyle, SortChipStyle.lively);
      expect(restored.groupByActive, isTrue);
    });

    test('older settings default to calm chip animation', () {
      final restored = SourceSortSettings.fromJson('{"mode":"nameAsc"}');

      expect(restored.chipStyle, SortChipStyle.calm);
      expect(restored.groupByActive, isFalse);
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
