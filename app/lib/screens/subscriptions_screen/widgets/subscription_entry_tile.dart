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
    final trailingWidget = _buildTrailing(context, entry);
    final tile = ListTile(
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 0,
      horizontalTitleGap: 4,
      leading: Transform.scale(
        scale: 0.85,
        alignment: Alignment.centerLeft,
        child: Switch(
          value: enabled,
          onChanged: (_) => onToggle(),
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
      // The visible handle is centered on the right side, while the
      // actual drag hit area is intentionally wider and fills the whole
      // trailing region for easier touch interaction.
      trailing: SizedBox(
        width: 58,
        child: ReorderableDragStartListener(
          index: dragIndex,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: 10,
                right: 10,
                top: 4,
                height: 26,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Center(
                    child: CustomPaint(
                      size: const Size(24, 14),
                      painter: _DragChevronPainter(
                        direction: AxisDirection.up,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: trailingWidget,
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 4,
                height: 26,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Center(
                    child: CustomPaint(
                      size: const Size(24, 14),
                      painter: _DragChevronPainter(
                        direction: AxisDirection.down,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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


class _DragChevronPainter extends CustomPainter {
  const _DragChevronPainter({
    required this.direction,
    required this.color,
  });

  final AxisDirection direction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    if (direction == AxisDirection.up) {
      path
        ..moveTo(size.width * 0.15, size.height * 0.72)
        ..lineTo(size.width * 0.5, size.height * 0.28)
        ..lineTo(size.width * 0.85, size.height * 0.72);
    } else {
      path
        ..moveTo(size.width * 0.15, size.height * 0.28)
        ..lineTo(size.width * 0.5, size.height * 0.72)
        ..lineTo(size.width * 0.85, size.height * 0.28);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DragChevronPainter oldDelegate) {
    return oldDelegate.direction != direction || oldDelegate.color != color;
  }
}
