// §393 D1 — СТРОКА источника-цепочки в общем списке источников.
//
// Цепочка — ТАКОЙ ЖЕ ИСТОЧНИК, как подписка, одиночный сервер и папка
// (директива оператора 24.08; так же у лаунчера — `source_tab`, один список).
// Поэтому она рисуется не отдельной секцией, а обычным рядом ТОГО ЖЕ вида:
// тумблер, заголовок, подзаголовок `tag · N hops`.
// Порядок источников здесь не меняется перетаскиванием.
//
// Прежняя отдельная секция «Цепочки хопов» над подписками отвергнута: она
// говорила пользователю, что цепочка — что-то другое, чем остальные
// источники, и заодно делала её порядок отдельным от общего.
//
// Строение виджета повторяет [SubscriptionEntryTile]: содержимое и разделитель
// занимают всю ширину строки, без отдельной зоны захвата слева.

import 'package:flutter/material.dart';

import '../../../models/source_chain.dart';
import '../../../widgets/reorder_grab_strip.dart';
import '../../../services/l10n/locale_controller.dart';

class ChainEntryTile extends StatelessWidget {
  const ChainEntryTile({
    super.key,
    required this.chain,
    required this.dragIndex,
    required this.onTap,
    required this.onToggle,
    this.compact = false,
    this.onCompactChanged,
  });

  final SourceChain chain;

  /// Индекс в `ReorderableListView` для drag-старта (§098).
  final int dragIndex;

  final VoidCallback onTap;
  final VoidCallback onToggle;
  final bool compact;
  final ValueChanged<bool>? onCompactChanged;

  Widget _chainIndicator(
    BuildContext context, {
    required VoidCallback onTap,
    required VoidCallback onLongPress,
    bool compact = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const activeFillColor = Color(0xFFBAC3FF);
    final backgroundColor = chain.enabled
        ? activeFillColor
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    return SizedBox(
      width: compact ? 48 : 56,
      height: compact ? 36 : 40,
      child: Material(
        key: ValueKey('chain-toggle-${chain.tag}'),
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Center(
            child: Container(
              width: compact ? 24 : 43,
              height: compact ? 24 : 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Transform.scale(
                scaleY: 1.1,
                child: CustomPaint(
                  size: Size.square(compact ? 20 : 29),
                  painter: _ChainGlyphPainter(
                    fill: isDark ? Colors.black : Colors.white,
                    detail: isDark ? Colors.white : Colors.black,
                    compact: compact,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (compact) {
      return SizedBox(
        height: 37,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 36,
              child: Row(
                children: [
                  _chainIndicator(
                    context,
                    onTap: () => onCompactChanged?.call(false),
                    onLongPress: onToggle,
                    compact: true,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onTap,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          chain.tag,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: chain.enabled
                                ? null
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
        ),
      );
    }

    final tile = ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _chainIndicator(
        context,
        onTap: () => onCompactChanged?.call(true),
        onLongPress: onToggle,
      ),
      title: Text(
        chain.tag,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: chain.enabled ? null : cs.onSurfaceVariant,
        ),
      ),
      subtitle: Text(
        '${chain.tag} · ${getLocalText.plural("%d hops", chain.hops.length)}',
        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
      ),
      onTap: onTap,
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReorderGrabStrip(index: dragIndex),
          Expanded(
            child: Column(
              children: [
                tile,
                const Divider(height: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
/// Иконка «Цепочка хопов».
class _ChainGlyphPainter extends CustomPainter {
  const _ChainGlyphPainter({
    required this.fill,
    required this.detail,
    required this.compact,
  });

  final Color fill;
  final Color detail;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    const base = 29.0;
    final glyphScale = compact ? 0.85 : 1.0;

    canvas.save();

    canvas.translate(
      size.width * (1 - glyphScale) / 2,
      size.height * (1 - glyphScale) / 2,
    );

    canvas.scale(
      size.width / base * glyphScale,
      size.height / base * glyphScale,
    );

    const haloWidth = 7.0;
    const lineWidth = 3.15;
    const haloDotRadius = 4.8;
    const dotRadius = 2.6;

    final route = Path()
      ..moveTo(7.5, 13.2)
      ..lineTo(7.5, 17.8)
      ..cubicTo(7.5, 19.733, 9.067, 21.3, 11.0, 21.3)
      ..cubicTo(12.933, 21.3, 14.5, 19.733, 14.5, 17.8)
      ..lineTo(14.5, 10.3)
      ..cubicTo(14.5, 8.367, 16.067, 6.8, 18.0, 6.8)
      ..cubicTo(19.933, 6.8, 21.5, 8.367, 21.5, 10.3)
      ..lineTo(21.5, 15.8);

    const leftDot = Offset(7.5, 8.1);
    const rightDot = Offset(21.5, 20.9);

    final haloPaint = Paint()
      ..color = detail
      ..style = PaintingStyle.stroke
      ..strokeWidth = haloWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final linePaint = Paint()
      ..color = fill
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final haloDotPaint = Paint()
      ..color = detail
      ..style = PaintingStyle.fill;

    final dotPaint = Paint()
      ..color = fill
      ..style = PaintingStyle.fill;

    canvas.drawPath(route, haloPaint);
    canvas.drawCircle(leftDot, haloDotRadius, haloDotPaint);
    canvas.drawCircle(rightDot, haloDotRadius, haloDotPaint);

    canvas.drawPath(route, linePaint);
    canvas.drawCircle(leftDot, dotRadius, dotPaint);
    canvas.drawCircle(rightDot, dotRadius, dotPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ChainGlyphPainter oldDelegate) =>
      fill != oldDelegate.fill ||
      detail != oldDelegate.detail ||
      compact != oldDelegate.compact;
}

