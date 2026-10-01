// §393 D1 — СТРОКА источника-цепочки в общем списке источников.
//
// Цепочка — ТАКОЙ ЖЕ ИСТОЧНИК, как подписка, одиночный сервер и папка
// (директива оператора 24.08; так же у лаунчера — `source_tab`, один список).
// Поэтому она рисуется не отдельной секцией, а обычным рядом ТОГО ЖЕ вида:
// тумблер, заголовок, подзаголовок `tag · N hops`, справа — иконка типа
// (как `Icons.dns` у одиночного сервера и `Icons.folder_outlined` у папки).
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
                        SizedBox(
                          width: 36,
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
                                    color: chain.enabled ? cs.primary : cs.surface,
                                    border: Border.all(
                                      color: chain.enabled ? cs.primary : cs.outline,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
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
                                  color: chain.enabled ? null : cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(left: 8, right: 12),
                          child: Icon(Icons.route, size: 20),
                        ),
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
      leading: SizedBox(
        width: 40,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () => onCompactChanged?.call(true),
          child: Switch(
            value: chain.enabled,
            onChanged: (_) => onToggle(),
          ),
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
      // Тег + число позиций: тег — то, чем цепочка зовётся в конфиге и в
      // фильтрах Направлений, число хопов — единственное, что отличает
      // маршруты друг от друга с одного взгляда.
      subtitle: Text(
        '${chain.tag} · ${getLocalText.plural("%d hops", chain.hops.length)}',
        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
      ),
      trailing: Icon(Icons.route, size: 20, color: cs.onSurfaceVariant), // §393 — route: цепочка = маршрут (alt_route — развилка, смысл Направления)
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
