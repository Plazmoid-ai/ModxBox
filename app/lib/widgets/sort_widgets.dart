import 'package:flutter/material.dart';

import '../services/l10n/locale_controller.dart';

enum SortField { name, modified, created }

/// Обычный порядок: А–Я / сначала новые. Обратный: Я–А / сначала старые.
@immutable
class SortState {
  const SortState({
    this.field = SortField.name,
    this.reversed = const {},
  });

  final SortField field;
  final Map<SortField, bool> reversed;

  bool isReversed(SortField f) => reversed[f] ?? false;
  bool get reverse => isReversed(field);

  /// Выбор поля не меняет запомненное направление.
  SortState select(SortField f) => SortState(field: f, reversed: reversed);

  /// Следующее поле по кругу.
  SortState next() =>
      select(SortField.values[(field.index + 1) % SortField.values.length]);

  /// Меняет направление только у текущего поля.
  SortState toggleReverse() =>
      SortState(field: field, reversed: {...reversed, field: !reverse});

  Map<String, Object> toJson() => {
        'field': field.name,
        'reversed': {for (final f in SortField.values) f.name: isReversed(f)},
      };

  factory SortState.fromJson(Map<String, dynamic> j) {
    final rawReversed = j['reversed'];
    final rawLegacyDirs = j['dirs'];
    return SortState(
      field: SortField.values.firstWhere(
        (f) => f.name == j['field'],
        orElse: () => SortField.name,
      ),
      reversed: {
        for (final f in SortField.values)
          f: rawReversed is Map
              ? rawReversed[f.name] == true
              : rawLegacyDirs is Map
                  ? rawLegacyDirs[f.name] == 'up'
                  : false,
      },
    );
  }
}

String sortLabel(SortField f, bool rev) {
  switch (f) {
    case SortField.name:
      return rev
          ? getLocalText.s('Name Z–A')
          : getLocalText.s('Name A–Z');
    case SortField.modified:
      return rev
          ? getLocalText.s('Modified — oldest')
          : getLocalText.s('Modified — newest');
    case SortField.created:
      return rev
          ? getLocalText.s('Created — oldest')
          : getLocalText.s('Created — newest');
  }
}

const _anim = Duration(milliseconds: 220);

// ───────────── Иконки полей ─────────────
// Имя: А—Я ↔ Я—А. Изменено: часы-«история» зеркалятся.
// Создано: число 1 ↔ 31. compact = true — кнопка панели 48×48.

class SortGlyph extends StatelessWidget {
  const SortGlyph({
    super.key,
    required this.field,
    required this.reversed,
    required this.color,
    this.compact = false,
  });

  final SortField field;
  final bool reversed;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    switch (field) {
      case SortField.name:
        return _NameGlyph(reversed: reversed, color: color, compact: compact);
      case SortField.modified:
        return _ClockGlyph(
            reversed: reversed, color: color, compact: compact);
      case SortField.created:
        return _CalendarGlyph(
            reversed: reversed, color: color, compact: compact);
    }
  }
}

class _NameGlyph extends StatelessWidget {
  const _NameGlyph({
    required this.reversed,
    required this.color,
    required this.compact,
  });
  final bool reversed;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = compact ? 13.0 : 16.0;
    final dash = compact ? 8.0 : 10.0;
    final gap = compact ? 3.0 : 4.0;
    final fs = compact ? 18.0 : 20.0;
    final h = compact ? 22.0 : 24.0;
    final dt = compact ? 2.0 : 2.5;
    final right = s + gap + dash + gap;

    Widget slot(String t) => SizedBox(
          width: s,
          height: h,
          child: Center(
            child: Text(
              t,
              style: TextStyle(
                fontSize: fs,
                height: 1,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        );

    return SizedBox(
      width: right + s,
      height: h,
      child: Stack(children: [
        AnimatedPositioned(
          duration: _anim,
          curve: Curves.easeOut,
          left: reversed ? right : 0,
          top: 0,
          child: slot('А'),
        ),
        Positioned(
          left: s + gap,
          top: (h - dt) / 2,
          width: dash,
          height: dt,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: _anim,
          curve: Curves.easeOut,
          left: reversed ? 0 : right,
          top: 0,
          child: slot('Я'),
        ),
      ]),
    );
  }
}

class _ClockGlyph extends StatelessWidget {
  const _ClockGlyph({
    required this.reversed,
    required this.color,
    required this.compact,
  });
  final bool reversed;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final w = compact ? 28.0 : 30.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: reversed ? -1.0 : 1.0),
      duration: _anim,
      curve: Curves.easeOut,
      builder: (_, v, child) => Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(v, 1, 1),
        child: child,
      ),
      child: CustomPaint(
        size: Size(w, w * 52 / 54),
        painter: _HistoryPainter(color),
      ),
    );
  }
}

/// Классические часы «история»: круговая стрелка и стрелки часов.
class _HistoryPainter extends CustomPainter {
  _HistoryPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 54, size.height / 52);
    canvas.translate(-45, -24);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final arc = Path()
      ..moveTo(54.8, 62.05)
      ..arcToPoint(
        const Offset(54.8, 37.95),
        radius: const Radius.circular(21),
        largeArc: true,
        clockwise: false,
      );
    canvas.drawPath(arc, stroke);

    final head = Path()
      ..moveTo(51.9, 42)
      ..lineTo(61.4, 38.9)
      ..lineTo(51.6, 32)
      ..close();
    canvas.drawPath(head, Paint()..color = color);
    canvas.drawPath(
      head,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    final hands = Path()
      ..moveTo(72, 39)
      ..lineTo(72, 50)
      ..lineTo(79, 57);
    canvas.drawPath(hands, stroke);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_HistoryPainter old) => old.color != color;
}

class _CalendarGlyph extends StatelessWidget {
  const _CalendarGlyph({
    required this.reversed,
    required this.color,
    required this.compact,
  });
  final bool reversed;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = compact ? 24.0 : 28.0;
    final r = (s * 0.21).roundToDouble();
    final header = (s * 0.25).roundToDouble();
    final ringInset = (s * 0.2).roundToDouble();
    final ringH = (s * 0.2).roundToDouble() + 1;
    final fs = (s * 0.46).roundToDouble();
    const bw = 1.5;

    Widget ring() => DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1),
          ),
        );

    return SizedBox(
      width: s,
      height: s,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: color, width: bw),
              borderRadius: BorderRadius.circular(r),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: header,
          height: bw,
          child: ColoredBox(color: color),
        ),
        Positioned(
          left: ringInset,
          top: -ringH + 1,
          width: 2,
          height: ringH,
          child: ring(),
        ),
        Positioned(
          right: ringInset,
          top: -ringH + 1,
          width: 2,
          height: ringH,
          child: ring(),
        ),
        Positioned(
          left: bw,
          right: bw,
          top: header + bw,
          bottom: bw,
          child: _Roll(
            a: '1',
            b: '31',
            second: reversed,
            style: TextStyle(
              fontSize: fs,
              height: 1,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ]),
    );
  }
}

/// Два значения друг над другом, плавно прокручиваются к нужному.
class _Roll extends StatelessWidget {
  const _Roll({
    required this.a,
    required this.b,
    required this.second,
    required this.style,
  });
  final String a, b;
  final bool second;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final h = box.maxHeight;
        return ClipRect(
          child: Stack(children: [
            AnimatedPositioned(
              duration: _anim,
              curve: Curves.easeOut,
              left: 0,
              right: 0,
              height: h,
              top: second ? -h : 0,
              child: Center(child: Text(a, style: style)),
            ),
            AnimatedPositioned(
              duration: _anim,
              curve: Curves.easeOut,
              left: 0,
              right: 0,
              height: h,
              top: second ? 0 : h,
              child: Center(child: Text(b, style: style)),
            ),
          ]),
        );
      });

// ───────────── Меню: подсказка + [реверс] [Имя] [Изменено] [Создано] ─────────────

class SortChips extends StatelessWidget {
  const SortChips({super.key, required this.state, required this.onChanged});

  final SortState state;
  final ValueChanged<SortState> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final label = sortLabel(state.field, state.reverse);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 24,
          child: AnimatedSwitcher(
            duration: _anim,
            child: Align(
              key: ValueKey(label),
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: t.textTheme.bodyMedium
                    ?.copyWith(color: t.colorScheme.primary),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(
            width: 44,
            child: _DirButton(
              reversed: state.reverse,
              onTap: () => onChanged(state.toggleReverse()),
            ),
          ),
          for (final f in SortField.values) ...[
            const SizedBox(width: 8),
            Expanded(
              child: _FieldChip(
                field: f,
                reversed: state.isReversed(f),
                selected: f == state.field,
                onTap: () => onChanged(state.select(f)),
              ),
            ),
          ],
        ]),
      ],
    );
  }
}

/// Общая рамка кнопки: подсветка, обводка, Semantics и нажатие.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.active,
    required this.label,
    required this.onTap,
    required this.builder,
  });

  final bool active;
  final String label;
  final VoidCallback onTap;
  final Widget Function(Color fg) builder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = active ? cs.onSecondaryContainer : cs.onSurface;
    final r = BorderRadius.circular(8);

    return Semantics(
      button: true,
      selected: active,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: _anim,
        height: 60,
        decoration: BoxDecoration(
          color: active ? cs.secondaryContainer : Colors.transparent,
          borderRadius: r,
          border: Border.all(color: active ? cs.primary : cs.outlineVariant),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            child: builder(fg),
          ),
        ),
      ),
    );
  }
}

class _FieldChip extends StatelessWidget {
  const _FieldChip({
    required this.field,
    required this.reversed,
    required this.selected,
    required this.onTap,
  });

  final SortField field;
  final bool reversed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Frame(
        active: selected,
        label: sortLabel(field, reversed),
        onTap: onTap,
        builder: (fg) => Stack(children: [
          AnimatedPositioned(
            duration: _anim,
            curve: Curves.easeOut,
            left: 0,
            right: 0,
            top: selected ? 12 : 19,
            height: 29,
            child: Center(
              child: SortGlyph(
                field: field,
                reversed: reversed,
                color: fg,
              ),
            ),
          ),
        ]),
      );
}

class _DirButton extends StatelessWidget {
  const _DirButton({required this.reversed, required this.onTap});
  final bool reversed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Frame(
        active: reversed,
        label: reversed
            ? 'Обратный порядок: включён'
            : 'Обратный порядок: выключен',
        onTap: onTap,
        builder: (fg) => Stack(children: [
          AnimatedPositioned(
            duration: _anim,
            curve: Curves.easeOut,
            left: 0,
            right: 0,
            top: reversed ? 16 : 23,
            height: 26,
            child: Center(
              child: AnimatedRotation(
                duration: _anim,
                turns: reversed ? 0.5 : 0,
                child: CustomPaint(
                  size: const Size(22, 26),
                  painter: _ArrowPainter(fg),
                ),
              ),
            ),
          ),
        ]),
      );
}

/// Классическая стрелка вниз.
class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(11, 2.5)
        ..lineTo(11, 23.5)
        ..moveTo(3.5, 16.5)
        ..lineTo(11, 24)
        ..lineTo(18.5, 16.5),
      p,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color;
}

// ───────────── Панель: кнопка 48×48 ─────────────
// Короткий тап — следующее поле, долгий — меню. Направление не меняет.

class SortToolbarButton extends StatelessWidget {
  const SortToolbarButton({
    super.key,
    required this.state,
    required this.onChanged,
    required this.onOpenMenu,
  });

  final SortState state;
  final ValueChanged<SortState> onChanged;
  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = sortLabel(state.field, state.reverse);
    final r = BorderRadius.circular(14);

    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        onTap: () => onChanged(state.next()),
        onLongPress: onOpenMenu,
        excludeSemantics: true,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: r,
              onTap: () => onChanged(state.next()),
              onLongPress: onOpenMenu,
              child: Center(
                child: AnimatedSwitcher(
                  duration: _anim,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.8, end: 1).animate(a),
                      child: child,
                    ),
                  ),
                  child: SortGlyph(
                    key: ValueKey(state.field),
                    field: state.field,
                    reversed: state.reverse,
                    color: cs.onSurface,
                    compact: true,
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
