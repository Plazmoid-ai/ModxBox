import 'package:flutter/material.dart';

import '../../../controllers/home_controller.dart';
import '../../../models/home_state.dart';
import '../../../services/l10n/locale_controller.dart';

/// Визуальный режим кнопок сортировки.
///
/// calm   — подпись остаётся по центру, стрелка появляется сверху;
/// lively — подпись перемещается к противоположному краю, стрелка занимает
/// другую сторону.
enum SortChipStyle { calm, lively }

/// Визуальная часть меню сортировки LxBox.
///
/// В отличие от универсального примера SortSheet, здесь используются реальные
/// режимы LxBox: Default / Ping / A–Z / Custom. Само состояние сортировки
/// продолжает принадлежать HomeState/HomeController.
class SortSheet extends StatelessWidget {
  const SortSheet({
    super.key,
    required this.controller,
    this.style = SortChipStyle.calm,
  });

  final HomeController controller;
  final SortChipStyle style;

  void _select(NodeSortMode mode) {
    controller.setSortMode(mode);
  }

  Widget _chip(NodeSortMode mode, HomeState state) {
    final selected = state.sortMode == mode;

    // В LxBox нет отдельного down-направления у sortMode:
    // latencyAsc и nameAsc всегда ascending. Default и Custom собственной
    // стрелки направления не имеют.
    final showArrow =
        selected &&
        mode != NodeSortMode.defaultOrder &&
        mode != NodeSortMode.manual;

    return Expanded(
      child: _SortChip(
        icon: mode.icon,
        label: mode.label(),
        selected: selected,
        showArrow: showArrow,
        style: style,
        onTap: () => _select(mode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        return _buildSheet(context, state);
      },
    );
  }

  Widget _buildSheet(BuildContext context, HomeState state) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            getLocalText.s('Sort options'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 24,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: Align(
                key: ValueKey(state.sortMode.name),
                alignment: Alignment.centerLeft,
                child: Text(
                  state.sortMode.label(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Фиксированная сетка 2×2: геометрия строк не зависит от выбора.
          Row(
            children: [
              _chip(NodeSortMode.defaultOrder, state),
              const SizedBox(width: 8),
              _chip(NodeSortMode.latencyAsc, state),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _chip(NodeSortMode.nameAsc, state),
              const SizedBox(width: 8),
              _chip(NodeSortMode.manual, state),
            ],
          ),

          const Divider(height: 24),

          CheckboxListTile(
            value: state.pinDirect,
            onChanged: (v) => controller.setPinDirect(v ?? false),
            title: Text(getLocalText.s('Pin DIRECT to top')),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          CheckboxListTile(
            value: state.pinAuto,
            onChanged: (v) => controller.setPinAuto(v ?? false),
            title: Text(getLocalText.s('Pin AUTO to top')),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          CheckboxListTile(
            value: state.resortOnManualPing,
            onChanged: (v) => controller.setResortOnManualPing(v ?? false),
            title: Text(getLocalText.s('Re-sort on manual ping')),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.showArrow,
    required this.style,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool showArrow;
  final SortChipStyle style;
  final VoidCallback onTap;

  static const double _h = 60;
  static const double _labelH = 20;
  static const double _arrowH = 16;
  static const double _edge = 6;
  static const _anim = Duration(milliseconds: 150);

  double get _labelTop {
    const center = (_h - _labelH) / 2; // 20
    if (!showArrow) return center;
    if (style == SortChipStyle.calm) return center;

    // lively: активный ascending sort → подпись к нижнему краю,
    // стрелка остаётся сверху.
    return _h - _edge - _labelH;
  }

  double get _arrowTop {
    if (!showArrow) {
      // Позиция всё равно зарезервирована: AnimatedOpacity только скрывает
      // стрелку. Это не меняет геометрию чипа.
      return 4;
    }

    if (style == SortChipStyle.calm) {
      const center = (_h - _labelH) / 2; // 20
      return center - _arrowH; // 4
    }

    // lively: стрелка у верхнего края, напротив подписи.
    return _edge;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onSecondaryContainer : cs.onSurface;
    final radius = BorderRadius.circular(8);

    return AnimatedContainer(
      duration: _anim,
      height: _h,
      decoration: BoxDecoration(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: radius,
        border: Border.all(
          color: selected ? cs.primary : cs.outlineVariant,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: _anim,
                curve: Curves.easeOut,
                left: 0,
                right: 0,
                top: _arrowTop,
                height: _arrowH,
                child: AnimatedOpacity(
                  duration: _anim,
                  opacity: showArrow ? 1 : 0,
                  child: const Icon(
                    Icons.arrow_upward,
                    size: _arrowH,
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: _anim,
                curve: Curves.easeOut,
                left: 0,
                right: 0,
                top: _labelTop,
                height: _labelH,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
