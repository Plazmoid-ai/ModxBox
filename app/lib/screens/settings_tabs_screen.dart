import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/l10n/locale_controller.dart';

/// Описание вкладки: название и значок (значок показывается в плитках).
class SettingsTabSpec {
  const SettingsTabSpec(this.title, this.icon);

  final String title;
  final IconData icon;
}

/// Экран настроек: вкладки в стиле браузера, а список вкладок — отдельные плитки.
///
/// Плитки открываются вытягиванием контента за верхний или нижний край либо
/// нажатием на название уже активной вкладки.
class SettingsTabsScreen extends StatefulWidget {
  const SettingsTabsScreen({
    super.key,
    required this.tabs,
    required this.pages,
    this.overlayTitle = 'App Settings',
    this.initialIndex = 0,
  });

  final List<SettingsTabSpec> tabs;
  final List<Widget> pages;
  final String overlayTitle;
  final int initialIndex;

  @override
  SettingsTabsScreenState createState() => SettingsTabsScreenState();
}

class SettingsTabsScreenState extends State<SettingsTabsScreen>
    with SingleTickerProviderStateMixin {
  /// Сколько пикселей нужно протянуть за край.
  static const double _pullThreshold = 80;

  /// Сколько удерживать после порога, чтобы жест засчитался.
  static const Duration _holdTime = Duration(milliseconds: 350);

  late final TabController _tc;
  int _indexAtPointerDown = 0;
  bool _tilesOpen = false;

  double _pull = 0;
  bool _armed = false;
  bool _pullAtTop = true;
  Timer? _armTimer;
  final ValueNotifier<_PullHint> _hint =
      ValueNotifier<_PullHint>(const _PullHint.idle());

  @override
  void initState() {
    super.initState();
    assert(widget.tabs.length == widget.pages.length);
    assert(widget.tabs.isNotEmpty);
    _tc = TabController(
      length: widget.tabs.length,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, widget.tabs.length - 1),
    );
  }

  @override
  void dispose() {
    _armTimer?.cancel();
    _hint.dispose();
    _tc.dispose();
    super.dispose();
  }

  /// Переключение извне нужно журналу настроек для перехода к изменённому
  /// параметру. Плитки при этом закрываются.
  void selectTab(int index) {
    if (index < 0 || index >= widget.tabs.length) return;
    if (_tilesOpen) setState(() => _tilesOpen = false);
    if (_tc.index != index) _tc.animateTo(index);
  }

  // ---------- плитки ----------

  void _openTiles() {
    if (_tilesOpen) return;
    HapticFeedback.selectionClick();
    setState(() => _tilesOpen = true);
  }

  void _closeTiles() {
    if (!_tilesOpen) return;
    setState(() => _tilesOpen = false);
  }

  void _selectTab(int i) {
    setState(() => _tilesOpen = false);
    _tc.animateTo(i);
  }

  // ---------- жест вытягивания ----------

  void _resetPull() {
    _armTimer?.cancel();
    _armTimer = null;
    _pull = 0;
    _armed = false;
    _hint.value = const _PullHint.idle();
  }

  void _publishPull() {
    _hint.value = _PullHint(
      (_pull / _pullThreshold).clamp(0.0, 1.0).toDouble(),
      _armed,
      _pullAtTop,
    );
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical || _tilesOpen) return false;

    if (n is ScrollStartNotification) {
      _resetPull();
    } else if (n is OverscrollNotification) {
      // Отскок и инерция (палец уже отпущен) не считаются.
      if (n.dragDetails == null) return false;
      _pullAtTop = n.overscroll < 0;
      _pull += n.overscroll.abs();
      if (_pull >= _pullThreshold && _armTimer == null && !_armed) {
        _armTimer = Timer(_holdTime, () {
          _armTimer = null;
          if (!mounted) return;
          _armed = true;
          HapticFeedback.mediumImpact();
          _publishPull();
        });
      }
      _publishPull();
    } else if (n is ScrollUpdateNotification) {
      // Контент сдвинулся внутрь границ: пользователь потянул обратно.
      if (n.dragDetails != null && _pull > 0) _resetPull();
    } else if (n is ScrollEndNotification) {
      final open = _armed;
      _resetPull();
      if (open) _openTiles();
    }
    return false;
  }

  // ---------- интерфейс ----------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      // Пока плитки открыты, «назад» закрывает их, а не выходит из настроек.
      canPop: !_tilesOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _tilesOpen) _closeTiles();
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        body: Stack(
          children: [
            Column(
              children: [
                _buildBar(cs),
                Expanded(child: _buildPages(context)),
              ],
            ),
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _tilesOpen
                    ? _TabTilesOverlay(
                        key: const ValueKey('tiles'),
                        title: widget.overlayTitle,
                        tabs: widget.tabs,
                        currentIndex: _tc.index,
                        onSelect: _selectTab,
                        onClose: _closeTiles,
                      )
                    : const SizedBox.shrink(key: ValueKey('none')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBar(ColorScheme cs) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          // Тап по уже активной вкладке открывает плитки.
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _indexAtPointerDown = _tc.index,
            child: TabBar(
              controller: _tc,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorSize: TabBarIndicatorSize.label,
              indicator: _BrowserTabIndicator(
                fill: cs.surface,
                line: cs.primary,
                hPad: 14,
              ),
              labelPadding: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              dividerColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              labelColor: cs.onSurface,
              unselectedLabelColor: cs.onSurfaceVariant,
              labelStyle:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              unselectedLabelStyle:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              tabs: [
                for (final t in widget.tabs) Tab(height: 40, text: t.title),
              ],
              onTap: (i) {
                if (i == _indexAtPointerDown) _openTiles();
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPages(BuildContext context) {
    // Единая физика: упор в край без свечения, всегда прокручиваемо,
    // чтобы вытягивание работало и на коротких вкладках.
    final behavior = ScrollConfiguration.of(context).copyWith(
      overscroll: false,
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
    );

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ScrollConfiguration(
            behavior: behavior,
            child: TabBarView(controller: _tc, children: widget.pages),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<_PullHint>(
              valueListenable: _hint,
              builder: (_, hint, __) => _PullHintView(hint: hint),
            ),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Индикатор вкладки: заливка активной вкладки + полоска по нижней линии
// ===========================================================================

class _BrowserTabIndicator extends Decoration {
  const _BrowserTabIndicator({
    required this.fill,
    required this.line,
    required this.hPad,
  });

  final Color fill;
  final Color line;

  /// Горизонтальный отступ вкладки вокруг названия (labelPadding).
  final double hPad;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _BrowserTabPainter(this);
}

class _BrowserTabPainter extends BoxPainter {
  _BrowserTabPainter(this.d);

  final _BrowserTabIndicator d;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final rect = offset & size;

    // Заливка всей вкладки со скруглённым верхом.
    final fillRect = Rect.fromLTRB(
      rect.left - d.hPad,
      rect.top,
      rect.right + d.hPad,
      rect.bottom,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        fillRect,
        topLeft: const Radius.circular(12),
        topRight: const Radius.circular(12),
      ),
      Paint()..color = d.fill,
    );

    // Полоска по нижней линии, длина равна ширине названия.
    final lineRect = Rect.fromLTWH(rect.left, rect.bottom - 3, rect.width, 3);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        lineRect,
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      ),
      Paint()..color = d.line,
    );
  }
}

// ===========================================================================
// Подсказка при вытягивании
// ===========================================================================

class _PullHint {
  const _PullHint(this.progress, this.armed, this.atTop);
  const _PullHint.idle()
      : progress = 0,
        armed = false,
        atTop = true;

  final double progress;
  final bool armed;
  final bool atTop;
}

class _PullHintView extends StatelessWidget {
  const _PullHintView({required this.hint});

  final _PullHint hint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final circle = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hint.armed ? cs.primaryContainer : cs.surfaceContainerHighest,
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              value: hint.armed
                  ? 1
                  : (hint.progress >= 1 ? null : hint.progress),
              strokeWidth: 2,
              color: cs.primary,
              backgroundColor: Colors.transparent,
            ),
          ),
          Icon(
            Icons.grid_view_rounded,
            size: 18,
            color: hint.armed ? cs.onPrimaryContainer : cs.onSurfaceVariant,
          ),
        ],
      ),
    );

    final label = SizedBox(
      height: 16,
      child: AnimatedOpacity(
        opacity: hint.armed ? 1 : 0,
        duration: const Duration(milliseconds: 120),
        child: Text(
          getLocalText.s("Release to open tabs"),
          style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
    );

    final children =
        hint.atTop ? [circle, label] : [label, circle];

    return Align(
      alignment: hint.atTop ? Alignment.topCenter : Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: AnimatedOpacity(
          opacity: hint.progress > 0 ? 1 : 0,
          duration: const Duration(milliseconds: 120),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

// ===========================================================================
// Плитки вкладок (один столбик)
// ===========================================================================

class _TabTilesOverlay extends StatelessWidget {
  const _TabTilesOverlay({
    super.key,
    required this.title,
    required this.tabs,
    required this.currentIndex,
    required this.onSelect,
    required this.onClose,
  });

  final String title;
  final List<SettingsTabSpec> tabs;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Активная вкладка уже на экране, поэтому плитки только для остальных.
    final others = [
      for (var i = 0; i < tabs.length; i++)
        if (i != currentIndex) i,
    ];

    return SizedBox.expand(
      child: Material(
        color: cs.surfaceContainer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onClose,
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < -300) onClose();
          },
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: tt.titleSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 14),
                        for (final i in others) ...[
                          _TabTile(spec: tabs[i], onTap: () => onSelect(i)),
                          const SizedBox(height: 8),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          getLocalText.s("Tap outside tiles or swipe up to close"),
                          textAlign: TextAlign.center,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabTile extends StatelessWidget {
  const _TabTile({required this.spec, required this.onTap});

  final SettingsTabSpec spec;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant, width: 0.5),
      ),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 58,
          child: Stack(
            children: [
              // Значок: у левого края, рамка 24px (18..42).
              Positioned(
                left: 18,
                top: 0,
                bottom: 0,
                width: 24,
                child: Center(
                  child: Icon(spec.icon, size: 24, color: cs.onSurfaceVariant),
                ),
              ),
              // Текст центрируется справа от значка, длинное имя уменьшается.
              Positioned(
                left: 42,
                right: 0,
                top: 0,
                bottom: 0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        spec.title,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
