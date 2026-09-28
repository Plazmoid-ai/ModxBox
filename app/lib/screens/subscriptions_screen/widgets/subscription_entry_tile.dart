import 'package:flutter/material.dart';

import '../../../controllers/subscription_controller.dart';
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
  });

  final SubscriptionEntry entry;
  final SubscriptionController subController;

  /// §504 — метка «New» у свежедобавленной записи (локальная подсветка экрана).
  final bool showNewBadge;

  /// Индекс в `ReorderableListView` для drag-старта (§098).
  final int dragIndex;
  final VoidCallback onToggle;
  final void Function(String url) onLaunchUrl;
  final void Function(BuildContext context) onLongPress;
  final void Function(BuildContext context) onTap;

  Widget? _buildTrailing(BuildContext context, SubscriptionEntry entry) {
    // Предупреждения остаются в правой части карточки. Значок типа
    // перенесён под переключатель и больше не занимает место справа.
    final summary =
        entry.list is UserServer ? null : entryWarningSummary(entry);
    if (summary == null) return null;
    return EntryWarningBadge(summary);
  }

  Widget _buildTypeIcon(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    if (entry.list is FolderServers) {
      return Icon(Icons.folder_outlined, size: 18, color: color);
    }
    if (entry.url.isEmpty && entry.connections.isNotEmpty) {
      return Icon(Icons.dns, size: 18, color: color);
    }
    return const SizedBox(width: 18, height: 18);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = entry.enabled;
    final trailingWidget = _buildTrailing(context, entry);
    final tile = ListTile(
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 0,
      horizontalTitleGap: 4,
      leading: SizedBox(
        width: 46,
        height: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 28,
              child: Transform.scale(
                scale: 0.78,
                child: Switch(
                  value: enabled,
                  onChanged: (_) => onToggle(),
                ),
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: 46,
              height: 20,
              child: ReorderableDragStartListener(
                index: dragIndex,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTypeIcon(context),
                    const SizedBox(width: 3),
                    Expanded(
                      child: CustomPaint(
                        painter: _DragBarsPainter(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.78),
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
                color: enabled
                    ? null
                    : Theme.of(context).colorScheme.onSurfaceVariant,
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
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer,
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
                  entry.supportUrl.contains('t.me')
                      ? Icons.telegram
                      : Icons.open_in_new,
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
      // Warning badges deliberately remain in the trailing area.
      trailing: trailingWidget,
      onLongPress: () => onLongPress(context),
      onTap: () => onTap(context),
    );

    return Column(
      children: [
        tile,
        const Divider(height: 1),
      ],
    );
  }
}


class _DragBarsPainter extends CustomPainter {
  const _DragBarsPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final barPaint = Paint()
      ..color = color
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final xLeft = size.width * 0.12;
    final xRight = size.width * 0.96;
    final yTop = size.height * 0.30;
    final yBottom = size.height * 0.70;

    canvas.drawLine(
      Offset(xLeft, yTop),
      Offset(xRight, yTop),
      barPaint,
    );
    canvas.drawLine(
      Offset(xLeft, yBottom),
      Offset(xRight, yBottom),
      barPaint,
    );

    // Белые точки слева — постоянная часть визуального индикатора.
    const dotRadius = 2.0;
    canvas.drawCircle(Offset(xLeft, yTop), dotRadius, dotPaint);
    canvas.drawCircle(Offset(xLeft, yBottom), dotRadius, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _DragBarsPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
