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
import '../../../services/l10n/locale_controller.dart';

class ChainEntryTile extends StatelessWidget {
  const ChainEntryTile({
    super.key,
    required this.chain,
    required this.onTap,
    required this.onToggle,
    this.compact = false,
    this.onCompactChanged,
  });

  final SourceChain chain;

  final VoidCallback onTap;
  final VoidCallback onToggle;
  final bool compact;
  final ValueChanged<bool>? onCompactChanged;

  Widget _chainIndicator(
    BuildContext context, {
    required VoidCallback onTap,
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
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.route,
                      size: compact ? 20 : 29,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    Icon(
                      Icons.route,
                      size: compact ? 16.5 : 24,
                      color: isDark ? Colors.black : Colors.white,
                    ),
                  ],
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
                          chain.displayLabel,
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
      leading: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => onCompactChanged?.call(true),
        child: _chainIndicator(
          context,
          onTap: onToggle,
        ),
      ),
      title: Text(
        chain.displayLabel,
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
      child: Column(
        children: [
          tile,
          const Divider(height: 1),
        ],
      ),
    );
  }
}
