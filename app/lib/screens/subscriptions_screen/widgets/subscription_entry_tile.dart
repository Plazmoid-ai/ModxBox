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

  Widget _indicator(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (entry.list is FolderServers) {
      return _folderIndicator(
        context,
        onTap: () => onCompactChanged?.call(false),
        compact: true,
      );
    }
    return SizedBox(
      width: 48,
      height: 36,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onCompactChanged?.call(false),
          child: Center(
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: entry.enabled ? cs.primary : cs.surface,
                border: Border.all(
                  color: entry.enabled ? cs.primary : cs.outline,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _folderIndicator(
    BuildContext context, {
    required VoidCallback onTap,
    bool compact = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final active = entry.enabled;
    // Контрастная заливка одинаково читается в Light и Dark.
    final backgroundColor =
        active ? cs.primaryContainer : cs.surfaceContainerHighest;
    return SizedBox(
      // Размер близок к штатному Switch; ширина немного увеличена,
      // чтобы контурная папка не выглядела сжатой.
      width: compact ? 48 : 56,
      height: compact ? 36 : 40,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Container(
              width: compact ? 26 : 52,
              height: compact ? 16 : 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Внутренность папки совпадает с фоном карточки;
                  // цвет состояния остаётся только снаружи контура.
                  Icon(
                    Icons.folder,
                    size: compact ? 20 : 29,
                    color: cs.surface,
                  ),
                  Icon(
                    Icons.folder_outlined,
                    size: compact ? 20 : 29,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactTile(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final typeIcon = entry.list is FolderServers
        ? Icons.folder_outlined
        : entry.url.isEmpty && entry.connections.isNotEmpty
            ? Icons.dns
            : null;
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          _indicator(context),
          const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(context),
              onLongPress: () => onLongPress(context),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  entry.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: entry.enabled ? null : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          if (typeIcon != null)
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 12),
              child: Icon(typeIcon, size: 20, color: cs.onSurfaceVariant),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
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
      leading: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => onCompactChanged?.call(true),
        child: entry.list is FolderServers
            ? _folderIndicator(context, onTap: onToggle)
            : Switch(value: enabled, onChanged: (_) => onToggle()),
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
      trailing: _buildTrailing(context, entry),
      onLongPress: () => onLongPress(context),
      onTap: () => onTap(context),
    );
    return IntrinsicHeight(
      child: Column(
        children: [
          tile,
          const Divider(height: 1),
        ],
      ),
    );
  }
}
