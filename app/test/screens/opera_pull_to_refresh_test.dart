import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/screens/subscriptions_screen.dart';

void main() {
  Widget testScreen({
    required Future<void> Function() onRefresh,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: OperaPullToRefresh(
          canRefresh: true,
          onRefresh: onRefresh,
          child: ListView.builder(
            key: const ValueKey('refresh-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: 40,
            itemExtent: 40,
            itemBuilder: (context, index) => Text('Row $index'),
          ),
        ),
      ),
    );
  }

  testWidgets('pulling beyond the threshold at the top refreshes once',
      (tester) async {
    var refreshCount = 0;
    await tester.pumpWidget(testScreen(onRefresh: () async {
      refreshCount++;
    }));

    await tester.drag(
      find.byKey(const ValueKey('refresh-list')),
      const Offset(0, 220),
    );
    await tester.pumpAndSettle();

    expect(refreshCount, 1);
    final iconFinder = find.byKey(const ValueKey('opera-pull-refresh-icon'));
    expect(iconFinder, findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find.descendant(of: iconFinder, matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, 0);
  });

  testWidgets('releasing below the threshold cancels without refreshing',
      (tester) async {
    var refreshCount = 0;
    await tester.pumpWidget(testScreen(onRefresh: () async {
      refreshCount++;
    }));

    await tester.drag(
      find.byKey(const ValueKey('refresh-list')),
      const Offset(0, 55),
    );
    await tester.pumpAndSettle();

    expect(refreshCount, 0);
    final iconFinder = find.byKey(const ValueKey('opera-pull-refresh-icon'));
    final opacity = tester.widget<Opacity>(
      find.descendant(of: iconFinder, matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, 0);
  });

  testWidgets('pulling at the bottom never starts a refresh', (tester) async {
    var refreshCount = 0;
    await tester.pumpWidget(testScreen(onRefresh: () async {
      refreshCount++;
    }));

    final list = find.byKey(const ValueKey('refresh-list'));
    await tester.drag(list, const Offset(0, -2400));
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, -220));
    await tester.pumpAndSettle();

    expect(refreshCount, 0);
  });
}
