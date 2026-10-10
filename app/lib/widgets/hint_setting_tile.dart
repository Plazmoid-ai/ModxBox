import 'package:flutter/material.dart';

/// Компактная строка настройки с кратким пояснением и раскрываемой подсказкой.
///
/// Тап по строке переключает значение; тап по значку ⓘ только открывает
/// или закрывает подробное описание.
class HintSettingTile extends StatefulWidget {
  const HintSettingTile({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.summary,
    this.enabled = true,
    this.alwaysShowHint = false,
  });

  final IconData icon;
  final String title;
  final String? summary;
  final String hint;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  /// Для режима обучения: подсказка всегда раскрыта, ⓘ неактивен.
  final bool alwaysShowHint;

  @override
  State<HintSettingTile> createState() => _HintSettingTileState();
}

class _HintSettingTileState extends State<HintSettingTile> {
  bool _open = false;

  bool get _showHint => _open || widget.alwaysShowHint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final titleStyle = (tt.titleMedium ?? const TextStyle()).copyWith(
      color: cs.onSurface,
      fontWeight: FontWeight.w500,
    );
    final summaryStyle = (tt.bodyMedium ?? const TextStyle()).copyWith(
      color: cs.onSurfaceVariant,
    );

    final on = widget.value;
    final cut = widget.title.lastIndexOf(' ');
    final head = cut < 0 ? '' : widget.title.substring(0, cut + 1);
    final tail = cut < 0 ? widget.title : widget.title.substring(cut + 1);

    return Semantics(
      container: true,
      toggled: on,
      enabled: widget.enabled,
      label: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: widget.enabled ? () => widget.onChanged(!on) : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              // Отступы меньше стандартных у ListTile — больше места для текста.
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 10, 8, 10),
                child: Row(
                  children: [
                    _LeadingIcon(
                      icon: widget.icon,
                      active: on,
                      enabled: widget.enabled,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                if (head.isNotEmpty) TextSpan(text: head),
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(tail, style: titleStyle),
                                      _InfoButton(
                                        active: _showHint,
                                        enabled: widget.enabled &&
                                            !widget.alwaysShowHint,
                                        onTap: () =>
                                            setState(() => _open = !_open),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            style: titleStyle,
                          ),
                          if (widget.summary != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Text(
                                widget.summary!,
                                style: summaryStyle,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    RockerSwitch(
                      value: on,
                      enabled: widget.enabled,
                      onChanged: widget.onChanged,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _showHint
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.hint,
                        style: (tt.bodyMedium ?? const TextStyle()).copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({
    required this.icon,
    required this.active,
    required this.enabled,
  });

  final IconData icon;
  final bool active;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: enabled
            ? (active ? cs.primaryContainer : cs.surfaceContainerHighest)
            : cs.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Icon(
        icon,
        size: 20,
        color: enabled
            ? (active ? cs.onPrimaryContainer : cs.onSurfaceVariant)
            : cs.onSurface.withValues(alpha: 0.38),
      ),
    );
  }
}

class _InfoButton extends StatelessWidget {
  const _InfoButton({
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: InkResponse(
        onTap: enabled ? onTap : null,
        radius: 16,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? cs.primaryContainer : Colors.transparent,
          ),
          child: Icon(
            Icons.info_outline,
            size: 18,
            color: active ? cs.onPrimaryContainer : cs.outline,
          ),
        ),
      ),
    );
  }
}

/// Вертикальный клавишный переключатель:
/// клавиша вверху — «Вкл», внизу — «Выкл».
class RockerSwitch extends StatelessWidget {
  const RockerSwitch({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  static const double _width = 30;
  static const double _height = 48;
  static const double _thumbHeight = 19;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const d = Duration(milliseconds: 150);

    final borderColor = enabled
        ? (value ? cs.primary : cs.outline)
        : cs.outline.withValues(alpha: 0.45);
    final backgroundColor = enabled
        ? (value ? cs.primaryContainer : cs.surfaceContainerHighest)
        : cs.surfaceContainerHighest.withValues(alpha: 0.5);
    final thumbColor = enabled
        ? (value ? cs.primary : cs.outline)
        : cs.outline.withValues(alpha: 0.45);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => onChanged(!value) : null,
      child: SizedBox(
        width: _width + 8,
        height: _height + 4,
        child: Center(
          child: AnimatedContainer(
            duration: d,
            width: _width,
            height: _height,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(width: 1.5, color: borderColor),
              color: backgroundColor,
            ),
            child: AnimatedAlign(
              duration: d,
              curve: Curves.easeOut,
              alignment: value ? Alignment.topCenter : Alignment.bottomCenter,
              child: AnimatedContainer(
                duration: d,
                height: _thumbHeight,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  color: thumbColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
