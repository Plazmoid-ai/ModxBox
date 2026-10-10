import 'package:flutter/material.dart';

import '../services/l10n/locale_controller.dart';

enum SortField { name, modified, created }

/// down: А–Я / сначала новые. up: Я–А / сначала старые.
enum SortDir { down, up }

SortDir flip(SortDir d) => d == SortDir.down ? SortDir.up : SortDir.down;

/// Поле + запомненное направление для каждого поля.
@immutable
class SortState {
  const SortState({
    this.field = SortField.name,
    this.dirs = _defaultDirs,
  });

  static const Map<SortField, SortDir> _defaultDirs = {
    SortField.name: SortDir.down,
    SortField.modified: SortDir.down,
    SortField.created: SortDir.down,
  };

  final SortField field;
  final Map<SortField, SortDir> dirs;

  SortDir dirOf(SortField f) => dirs[f] ?? SortDir.down;
  SortDir get dir => dirOf(field);

  SortState withDir(SortField f, SortDir d) =>
      SortState(field: field, dirs: {...dirs, f: d});

  /// Меню: другое поле — берём его запомненное направление,
  /// повторный тап по активному — переворачиваем.
  SortState tapInMenu(SortField f) => f == field
      ? withDir(f, flip(dirOf(f)))
      : SortState(field: f, dirs: dirs);

  /// Панель: всегда переворачивает направление текущего поля.
  SortState tapInBar() => withDir(field, flip(dir));

  Map<String, Object> toJson() => {
        'field': field.name,
        'dirs': {for (final e in dirs.entries) e.key.name: e.value.name},
      };

  factory SortState.fromJson(Map<String, dynamic> j) {
    final dirs = <SortField, SortDir>{..._defaultDirs};
    final raw = j['dirs'];
    if (raw is Map) {
      for (final f in SortField.values) {
        dirs[f] = SortDir.values.firstWhere(
          (d) => d.name == raw[f.name],
          orElse: () => SortDir.down,
        );
      }
    }
    final field = SortField.values.firstWhere(
      (f) => f.name == j['field'],
      orElse: () => SortField.name,
    );
    return SortState(field: field, dirs: dirs);
  }
}

String sortLabel(SortField f, SortDir d) {
  final down = d == SortDir.down;
  switch (f) {
    case SortField.name:
      return getLocalText.s(down ? 'Name A–Z' : 'Name Z–A');
    case SortField.modified:
      return getLocalText.s(
        down ? 'Modified — newest' : 'Modified — oldest',
      );
    case SortField.created:
      return getLocalText.s(
        down ? 'Created — newest' : 'Created — oldest',
      );
  }
}

const _anim = Duration(milliseconds: 180);

// ───────────── Уголок 22×11 с утолщением к острию ─────────────

class SortChevron extends StatelessWidget {
  const SortChevron({super.key, required this.color});
  final Color color;
  static const double width = 22, height = 11;

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
    final sx = size.width / 16, sy = size.height / 10;
    const pts = [
      Offset(0.8, 1.2), Offset(8, 6), Offset(15.2, 1.2),
      Offset(15.2, 2.6), Offset(8, 9.6), Offset(0.8, 2.6),
    ];
    final path = Path()..moveTo(pts[0].dx * sx, pts[0].dy * sy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx * sx, p.dy * sy);
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
  bool shouldRepaint(_ChevronPainter old) => old.color != color;
}

// ───────────── Иконки полей ─────────────

/// Имя: А↔Я. Изменено: солнце (новые) / луна (старые) + карандаш.
/// Создано: календарь 1 (новые) / 31 (старые).
/// compact = true — для кнопки панели 48.
class SortGlyph extends StatelessWidget {
  const SortGlyph({
    super.key,
    required this.field,
    required this.dir,
    required this.color,
    required this.badgeBg,
    this.compact = false,
  });

  final SortField field;
  final SortDir dir;
  final Color color;
  final Color badgeBg;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    switch (field) {
      case SortField.name:
        return _NameGlyph(dir: dir, color: color, compact: compact);
      case SortField.modified:
        return _SunMoonGlyph(
          dir: dir,
          color: color,
          badgeBg: badgeBg,
          compact: compact,
        );
      case SortField.created:
        return _CalendarGlyph(dir: dir, color: color, compact: compact);
    }
  }
}

class _NameGlyph extends StatelessWidget {
  const _NameGlyph({
    required this.dir,
    required this.color,
    required this.compact,
  });
  final SortDir dir;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = compact ? 12.0 : 16.0;
    final right = compact ? 28.0 : 48.0;
    final arrow = compact ? 12.0 : 16.0;
    final fs = compact ? 16.0 : 20.0;
    final down = dir == SortDir.down;

    Widget slot(String t) => SizedBox(
          width: s,
          height: 24,
          child: Center(
            child: Text(
              t,
              style: TextStyle(
                fontSize: fs,
                height: 1,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        );

    return SizedBox(
      width: right + s,
      height: 24,
      child: Stack(children: [
        AnimatedPositioned(
          duration: _anim,
          curve: Curves.easeOut,
          left: down ? 0 : right,
          top: 0,
          child: slot('А'),
        ),
        Positioned(
          left: s + (right - s - arrow) / 2,
          top: (24 - arrow) / 2,
          child: Icon(Icons.arrow_forward, size: arrow, color: color),
        ),
        AnimatedPositioned(
          duration: _anim,
          curve: Curves.easeOut,
          left: down ? right : 0,
          top: 0,
          child: slot('Я'),
        ),
      ]),
    );
  }
}

class _SunMoonGlyph extends StatelessWidget {
  const _SunMoonGlyph({
    required this.dir,
    required this.color,
    required this.badgeBg,
    required this.compact,
  });
  final SortDir dir;
  final Color color;
  final Color badgeBg;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final n = compact ? 22.0 : 26.0;
    final b = compact ? 13.0 : 17.0;
    final bi = compact ? 11.0 : 14.0;
    final down = dir == SortDir.down;

    Widget layer(IconData icon, bool visible, double hiddenTurns) =>
        AnimatedOpacity(
          duration: _anim,
          opacity: visible ? 1 : 0,
          child: AnimatedScale(
            duration: _anim,
            scale: visible ? 1 : 0.6,
            child: AnimatedRotation(
              duration: _anim,
              turns: visible ? 0 : hiddenTurns,
              child: Icon(icon, size: n, color: color),
            ),
          ),
        );

    return SizedBox(
      width: n,
      height: n,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: layer(Icons.wb_sunny, down, 1 / 6)),
        Positioned.fill(child: layer(Icons.dark_mode, !down, -1 / 6)),
        Positioned(
          right: compact ? -8 : -10,
          bottom: compact ? -5 : -7,
          child: Container(
            width: b,
            height: b,
            decoration: BoxDecoration(
              color: badgeBg,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.edit, size: bi, color: color),
          ),
        ),
      ]),
    );
  }
}

class _CalendarGlyph extends StatelessWidget {
  const _CalendarGlyph({
    required this.dir,
    required this.color,
    required this.compact,
  });
  final SortDir dir;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = compact ? 23.0 : 28.0;
    final r = compact ? 5.0 : 6.0;
    final header = compact ? 6.0 : 7.0;
    final ringInset = compact ? 4.0 : 6.0;
    final ringH = compact ? 5.0 : 6.0;
    final fs = compact ? 10.0 : 13.0;
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
            second: dir == SortDir.up,
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

/// Два значения друг над другом; плавно «прокручивается» к нужному.
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
}

// ───────────── Меню: подсказка + три чипа ─────────────

class SortChips extends StatelessWidget {
  const SortChips({
    super.key,
    required this.state,
    required this.onChanged,
    this.sheetColor,
  });

  final SortState state;
  final ValueChanged<SortState> onChanged;
  final Color? sheetColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final sheet = sheetColor ?? t.colorScheme.surface;
    final chips = <Widget>[];
    for (final f in SortField.values) {
      if (chips.isNotEmpty) chips.add(const SizedBox(width: 8));
      chips.add(Expanded(
        child: _SortChip(
          field: f,
          dir: state.dirOf(f),
          selected: f == state.field,
          sheetColor: sheet,
          onTap: () => onChanged(state.tapInMenu(f)),
        ),
      ));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 24,
          child: AnimatedSwitcher(
            duration: _anim,
            child: Align(
              key: ValueKey(sortLabel(state.field, state.dir)),
              alignment: Alignment.centerLeft,
              child: Text(
                sortLabel(state.field, state.dir),
                style: t.textTheme.bodyMedium
                    ?.copyWith(color: t.colorScheme.primary),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: chips),
      ],
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.field,
    required this.dir,
    required this.selected,
    required this.sheetColor,
    required this.onTap,
  });

  final SortField field;
  final SortDir dir;
  final bool selected;
  final Color sheetColor;
  final VoidCallback onTap;

  static const double _h = 60, _labelH = 28, _labelEdge = 6, _arrowEdge = 8;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onSecondaryContainer : cs.onSurface;
    final bg = selected ? cs.secondaryContainer : Colors.transparent;
    final up = dir == SortDir.up;
    final r = BorderRadius.circular(8);

    final double labelTop = !selected
        ? (_h - _labelH) / 2
        : (up ? _h - _labelEdge - _labelH : _labelEdge);
    final double arrowTop = (selected && !up)
        ? _h - _arrowEdge - SortChevron.height
        : _arrowEdge;

    return Semantics(
      button: true,
      selected: selected,
      label: sortLabel(field, dir),
      onTap: onTap,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: _anim,
        height: _h,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: r,
          border: Border.all(color: selected ? cs.primary : cs.outlineVariant),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            child: Stack(children: [
              AnimatedPositioned(
                duration: _anim,
                curve: Curves.easeOut,
                left: 0,
                right: 0,
                top: arrowTop,
                height: SortChevron.height,
                child: Center(
                  child: AnimatedOpacity(
                    duration: _anim,
                    opacity: selected ? 1 : 0,
                    child: AnimatedRotation(
                      duration: _anim,
                      turns: up ? 0.5 : 0,
                      child: SortChevron(color: fg),
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: _anim,
                curve: Curves.easeOut,
                left: 0,
                right: 0,
                top: labelTop,
                height: _labelH,
                child: Center(
                  child: SortGlyph(
                    field: field,
                    dir: dir,
                    color: fg,
                    badgeBg: selected ? cs.secondaryContainer : sheetColor,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ───────────── Панель: кнопка 48×48 ─────────────

class SortToolbarButton extends StatelessWidget {
  const SortToolbarButton({
    super.key,
    required this.state,
    required this.onChanged,
    this.barColor,
    this.enabled = true,
    this.onLongPress,
  });

  final SortState state;
  final ValueChanged<SortState> onChanged;
  final Color? barColor;
  final bool enabled;
  final VoidCallback? onLongPress;

  static const double _size = 48, _glyph = 24, _gap = 3, _edge = 5;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final up = state.dir == SortDir.up;
    final r = BorderRadius.circular(14);
    final glyphTop = up ? _edge + SortChevron.height + _gap : _edge;
    final arrowTop = up ? _edge : _edge + _glyph + _gap;
    final label = sortLabel(state.field, state.dir);

    return Semantics(
      button: true,
      label: label,
      onTap: enabled ? () => onChanged(state.tapInBar()) : null,
      excludeSemantics: true,
      child: SizedBox(
        width: _size,
        height: _size,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: r,
            onTap: enabled ? () => onChanged(state.tapInBar()) : null,
            onLongPress: enabled ? onLongPress : null,
            child: Stack(children: [
              AnimatedPositioned(
                duration: _anim,
                curve: Curves.easeOut,
                left: 0,
                right: 0,
                top: arrowTop,
                height: SortChevron.height,
                child: Center(
                  child: AnimatedRotation(
                    duration: _anim,
                    turns: up ? 0.5 : 0,
                    child: SortChevron(color: cs.onSurface),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: _anim,
                curve: Curves.easeOut,
                left: 0,
                right: 0,
                top: glyphTop,
                height: _glyph,
                child: Center(
                  child: SortGlyph(
                    field: state.field,
                    dir: state.dir,
                    color: cs.onSurface,
                    badgeBg: barColor ?? cs.surface,
                    compact: true,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
