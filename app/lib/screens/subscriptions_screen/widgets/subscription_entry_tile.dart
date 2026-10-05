import 'package:flutter/material.dart';

import '../../../controllers/subscription_controller.dart';
import '../../../widgets/reorder_grab_strip.dart';
import '../../../models/server_list.dart';
import '../../../services/l10n/locale_controller.dart';
import '../entry_warnings.dart';
import 'subscription_entry_subtitle.dart';

/// Одна строка списка подписок/серверов. §098 — слева grab-strip для
/// drag-reorder (как в routing rules), снизу divider (раньше был
/// `separatorBuilder` у `ListView.separated`).
class SubscriptionEntryTile extends StatelessWidget {
  const SubscriptionEntryTile({
    super.key,
    required this.entry,
    required this.subController,
    required this.dragIndex,
    required this.onToggle,
    required this.onLaunchUrl,
    required this.onLongPress,
    required this.onTap,
    this.showNewBadge = false,
    this.compact = false,
    this.onCompactChanged,
  });

  final SubscriptionEntry entry;
  final SubscriptionController subController;

  /// Индекс в `ReorderableListView` для drag-старта (§098).
  final int dragIndex;

  /// §504 — метка «New» у свежедобавленной записи (локальная подсветка экрана).
  final bool showNewBadge;

  /// Дополнительный компактный вид записи. Удержание переключателя сворачивает;
  /// обычное нажатие на индикатор в компактном виде раскрывает.
  final bool compact;
  final ValueChanged<bool>? onCompactChanged;

  final VoidCallback onToggle;
  final void Function(String url) onLaunchUrl;
  final void Function(BuildContext context) onLongPress;
  final void Function(BuildContext context) onTap;

  Widget? _buildTrailing(BuildContext context, SubscriptionEntry entry) {
    // §499 — счётчик только у подписки/папки. У одиночного сервера значок
    // живёт в [NodeWarningRow] подписи, иначе он задвоился бы в trailing.
    final summary =
        entry.list is UserServer ? null : entryWarningSummary(entry);
    final typeIcon = entry.list is FolderServers
        ? Icon(Icons.folder_outlined,
            size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant)
        : entry.url.isEmpty && entry.connections.isNotEmpty
            ? Icon(Icons.dns,
                size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant)
            : null;
    if (summary == null && typeIcon == null) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?summary == null ? null : EntryWarningBadge(summary),
        ?typeIcon,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = entry.enabled;
    if (compact) {
      return SizedBox(
        height: 37,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 36, child: _compactTile(context)),
            const Divider(height: 1),
          ],
        ),
      );
    }

    final tile = ListTile(
      contentPadding: EdgeInsets.zero,
      leading: entry.list is FolderServers
          ? _folderIndicator(
              context,
              onTap: () => onCompactChanged?.call(true),
              onLongPress: onToggle,
            )
          : entry.list is SubscriptionServers
              ? _subscriptionIndicator(
                  context,
                  onTap: () => onCompactChanged?.call(true),
                  onLongPress: onToggle,
                )
              : entry.url.isEmpty && entry.connections.isNotEmpty
                  ? _serverIndicator(
                      context,
                      onTap: () => onCompactChanged?.call(true),
                      onLongPress: onToggle,
                    )
                  : Switch(value: enabled, onChanged: (_) => onToggle()),
      title: Row(
        children: [
          Flexible(
            child: Text(
              entry.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: enabled ? null : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (showNewBadge)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  child: Text(
                    getLocalText.s('New'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          if (entry.supportUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: GestureDetector(
                onTap: () => onLaunchUrl(entry.supportUrl),
                child: Icon(
                  entry.supportUrl.contains('t.me') ? Icons.telegram : Icons.open_in_new,
                  size: 16,
                  color: entry.supportUrl.contains('t.me')
                      ? const Color(0xFF2AABEE)
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      subtitle: buildSubscriptionEntrySubtitle(context, entry, subController),
      trailing: _buildTrailing(context, entry),
      onLongPress: () => onLongPress(context),
      onTap: () => onTap(context),
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

/// Рисует двухсекционный индикатор сервера с независимыми цветами
/// заливки, контура и точек. Геометрия повторяет пропорции Icons.dns.
class _ServerGlyphPainter extends CustomPainter {
  const _ServerGlyphPainter({
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
    // В компактном виде оставляем те же 20 px для области иконки,
    // но возвращаем размер самого рисунка к масштабу штатного Icons.dns.
    final glyphScale = compact ? 0.85 : 1.0;
    canvas.save();
    canvas.translate(
      size.width * (1 - glyphScale) / 2,
      size.height * (1 - glyphScale) / 2,
    );
    canvas.scale(size.width / base * glyphScale, size.height / base * glyphScale);

    final fillPaint = Paint()
      ..color = fill
      ..style = PaintingStyle.fill;
    final outlinePaint = Paint()
      ..color = detail
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeJoin = StrokeJoin.round;
    final dotPaint = Paint()
      ..color = detail
      ..style = PaintingStyle.fill;

    final topY = compact ? 2.5 : 3.25;
    final bottomY = compact ? 17.0 : 16.75;
    final top = RRect.fromRectAndRadius(
      Rect.fromLTWH(3, topY, 23, 9),
      const Radius.circular(2.2),
    );
    final bottom = RRect.fromRectAndRadius(
      Rect.fromLTWH(3, bottomY, 23, 9),
      const Radius.circular(2.2),
    );

    canvas.drawRRect(top, fillPaint);
    canvas.drawRRect(bottom, fillPaint);
    canvas.drawRRect(top, outlinePaint);
    canvas.drawRRect(bottom, outlinePaint);
    canvas.drawCircle(
      Offset(7, compact ? 7.25 : 8.0),
      2.15,
      dotPaint,
    );
    canvas.drawCircle(
      Offset(7, compact ? 21.75 : 21.5),
      2.15,
      dotPaint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ServerGlyphPainter oldDelegate) =>
      fill != oldDelegate.fill ||
      detail != oldDelegate.detail ||
      compact != oldDelegate.compact;
}


/// Контурная иконка облака загрузки подписки.
/// Цвета и масштабирование повторяют двухсекционный индикатор узла.
class _SubscriptionGlyphPainter extends CustomPainter {
  const _SubscriptionGlyphPainter({
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
    canvas.scale(size.width / base * glyphScale, size.height / base * glyphScale);

    final fillPaint = Paint()
      ..color = fill
      ..style = PaintingStyle.fill;
    final outlinePaint = Paint()
      ..color = detail
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final arrowPaint = Paint()
      ..color = detail
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final cloud = Path()
      ..moveTo(6.2, 22.8)
      ..cubicTo(2.8, 22.8, 1.2, 20.2, 1.2, 17.4)
      ..cubicTo(1.2, 14.1, 3.5, 11.7, 6.8, 11.4)
      ..cubicTo(7.5, 6.8, 11.2, 3.8, 15.3, 3.8)
      ..cubicTo(19.2, 3.8, 22.4, 6.3, 23.3, 10.0)
      ..cubicTo(26.5, 10.1, 28.2, 12.6, 28.2, 15.6)
      ..cubicTo(28.2, 19.7, 25.8, 22.8, 21.9, 22.8)
      ..close();

    canvas.drawPath(cloud, fillPaint);
    canvas.drawPath(cloud, outlinePaint);

    final arrow = Path()
      ..moveTo(14.7, 8.2)
      ..lineTo(14.7, 18.0)
      ..moveTo(10.5, 14.0)
      ..lineTo(14.7, 18.2)
      ..lineTo(18.9, 14.0);
    canvas.drawPath(arrow, arrowPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SubscriptionGlyphPainter oldDelegate) =>
      fill != oldDelegate.fill ||
      detail != oldDelegate.detail ||
      compact != oldDelegate.compact;
}

/// Контур папки с явно заданной толщиной линии.
class _FolderOutlinePainter extends CustomPainter {
  const _FolderOutlinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const base = 24.0;
    canvas.save();
    canvas.scale(size.width / base, size.height / base);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(2.5, 4.5)
      ..lineTo(9.7, 4.5)
      ..lineTo(11.7, 6.5)
      ..lineTo(21.5, 6.5)
      ..lineTo(21.5, 19.5)
      ..lineTo(2.5, 19.5)
      ..close();
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FolderOutlinePainter oldDelegate) =>
      color != oldDelegate.color;
}

