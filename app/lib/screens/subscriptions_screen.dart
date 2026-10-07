import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/home_controller.dart';
import '../controllers/subscription_controller.dart';
import '../models/server_list.dart';
import '../models/ui_msg.dart';
import '../services/community_servers_loader.dart';
import '../services/error_format.dart';
import '../services/settings_storage.dart';
import '../services/subscription/auto_updater.dart';
import '../services/url_launcher.dart';
import 'add_server_wizard_screen.dart';
import 'app_settings_screen.dart';
import 'folder_detail_screen.dart';
import 'node_settings_screen.dart';
import 'qr_scan_screen.dart';
import 'subscription_detail_screen.dart';
import 'subscription_detail_screen/widgets/node_warnings_sheet.dart';
import 'warp_wizard_screen.dart';
import 'subscriptions_screen/clipboard_analysis.dart';
import 'subscriptions_screen/entry_context_menu.dart';
import 'subscriptions_screen/folder_picker.dart';
import 'subscriptions_screen/paste_dialogs.dart';
import 'subscriptions_screen/public_test_servers.dart';
import '../models/source_chain.dart';
import '../models/source_entry.dart';
import 'chain_edit/chain_edit_flow.dart';
import 'chain_edit/new_chain_dialog.dart';
import 'subscriptions_screen/widgets/add_icon_button.dart';
import 'subscriptions_screen/widgets/parse_input_error_banner.dart';
import 'subscriptions_screen/widgets/chains_section.dart';
import 'subscriptions_screen/widgets/subscription_entry_tile.dart';
import 'subscriptions_screen/widgets/subscriptions_empty_state.dart';
import 'subscriptions_screen/source_sort.dart';
import '../services/l10n/locale_controller.dart';
import '../services/file_import.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({
    super.key,
    required this.subController,
    required this.homeController,
    required this.autoUpdater,
    this.focusEntryId,
    this.initialInput,
  });

  final SubscriptionController subController;
  final HomeController homeController;
  final AutoUpdater autoUpdater;

  /// §255 — при открытии проскроллить к этому entry и мигнуть его строкой
  /// (навигация из detour-cycle sheet к владельцу ноды-виновника). null = нет.
  final String? focusEntryId;

  /// §357 — предзаполнить поле «URL подписки или proxy-ссылка» (lxbox-кнопка
  /// `add:<uri>` support-ленты). Только prefill: добавление подтверждает сам
  /// юзер кнопкой «+». null = пустое поле.
  final String? initialInput;

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  final _inputController = TextEditingController();
  bool _autoUpdateEnabled = true;

  /// §524 — ОБЩИЙ СПИСОК ИСТОЧНИКОВ в порядке `sources[]`: подписки, серверы,
  /// папки и цепочки одним рядом. Один список — одна истина о порядке; до §524
  /// экран сшивал три источника (`entries` контроллера, буфер цепочек,
  /// `List<String>` ключей) в `_rows()` на каждый кадр.
  ///
  /// Наполняется [SubscriptionController.sourceEntries]; пусто до первой
  /// загрузки — [_rows] тогда рисует записи контроллера в их порядке.
  List<SourceEntry> _sources = const [];

  /// Локальная настройка представления списка. Она не меняет нормативный
  /// порядок `sources[]`: сортировка и группировка являются только способом
  /// отображения.
  SourceSortSettings _sortSettings = const SourceSortSettings();
  final Map<String, SourceSortTimestamps> _sortMetadata = {};
  static const _sortSettingsStorageKey = 'server_list_sorting';
  static const _sortMetadataStorageKey = 'server_list_sort_meta';
  bool _sortStateReady = false;

  /// Цепочки общего списка — срез [_sources]. Нужен диалогам (редактор
  /// цепочки хочет соседей, чтобы показать законные позиции) и гейту тега.
  List<SourceChain> get _chains =>
      [for (final e in _sources) if (e is ChainEntry) e.chain];

  /// §375 — есть ли камера. null = ещё не ответил канал; до ответа пункт
  /// «Scan QR code» показываем (проверка мгновенная, на телефоне камера есть
  /// практически всегда). На Android TV — false, пункт прячется.
  bool? _hasCamera;

  // §255 / §504 — прокрутка к строке + подсветка. Локальная (в хранилище не
  // пишется): focusEntryId (detour-cycle) или свежедобавленная запись.
  final _scrollController = ScrollController();
  final _tileKeys = <String, GlobalKey>{};

  /// ID отдельных карточек, свёрнутых в разделе «Серверы».
  final Set<String> _compactEntryIds = <String>{};
  static const _compactEntriesStorageKey = 'servers_compact_entry_ids';
  String? _highlightedEntryId;
  _HighlightMode _highlightMode = _HighlightMode.none;
  double _highlightOpacity = 0;
  double? _highlightScrollBaseline;

  /// §504 — запас под SnackBar в конце списка. Новая запись встаёт в хвост,
  /// а хвост длинного списка прокручивается только до нижнего padding:
  /// без запаса последняя строка оставалась под SnackBar «Config
  /// regenerated». Появляется с первой подсветкой и живёт до ухода с экрана —
  /// иначе список дёрнулся бы вниз при снятии подсветки.
  double _snackBarClearance = 0;
  Timer? _highlightTimer;
  Timer? _highlightFadeTimer;

  /// §504 — programmatic clear поля после add не снимает подсветку.
  bool _ignoreInputDismiss = false;

  /// §504 — ensureVisible/jumpTo к новой записи не считается ручным скроллом.
  bool _programmaticScroll = false;

  GlobalKey _tileKey(String id) => _tileKeys.putIfAbsent(id, GlobalKey.new);

  Set<String> _entryIds(SubscriptionController ctrl) =>
      ctrl.entries.map((e) => e.id).toSet();

  String? _firstNewEntryId(Set<String> before, SubscriptionController ctrl) {
    for (final e in ctrl.entries) {
      if (!before.contains(e.id)) return e.id;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadCompactEntries());
    unawaited(_loadAutoUpdateFlag());
    unawaited(_loadCameraAvailability());
    unawaited(_loadSortState());
    widget.subController.addListener(_onControllerForSourceOrder);
    // §357 — prefill поля ввода из lxbox-кнопки `add:<uri>` support-ленты.
    final prefill = widget.initialInput;
    if (prefill != null && prefill.trim().isNotEmpty) {
      _inputController.text = prefill.trim();
    }
    _inputController.addListener(_onInputForHighlightDismiss);
    _scrollController.addListener(_onScrollForHighlightDismiss);
    final focus = widget.focusEntryId;
    if (focus != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _focusEntry(focus, attempt: 0));
    }
  }

  void _onInputForHighlightDismiss() {
    if (_ignoreInputDismiss) return;
    if (_highlightMode == _HighlightMode.newEntry) {
      _dismissHighlight(animated: true);
    }
  }

  void _onScrollForHighlightDismiss() {
    if (_programmaticScroll) return;
    if (_highlightMode != _HighlightMode.newEntry) return;
    if (!_scrollController.hasClients) return;
    final baseline = _highlightScrollBaseline;
    if (baseline == null) return;
    final screenH = MediaQuery.sizeOf(context).height;
    if ((_scrollController.offset - baseline).abs() > screenH) {
      _dismissHighlight(animated: true);
    }
  }

  void _onUserInteractionDismissHighlight() {
    if (_highlightMode == _HighlightMode.newEntry) {
      _dismissHighlight(animated: true);
    }
  }

  void _dismissHighlight({required bool animated}) {
    _highlightTimer?.cancel();
    _highlightFadeTimer?.cancel();
    if (_highlightedEntryId == null) return;
    if (!animated || _highlightMode != _HighlightMode.newEntry) {
      if (!mounted) return;
      setState(() {
        _highlightedEntryId = null;
        _highlightMode = _HighlightMode.none;
        _highlightOpacity = 0;
        _highlightScrollBaseline = null;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _highlightOpacity = 0);
    _highlightFadeTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() {
        _highlightedEntryId = null;
        _highlightMode = _HighlightMode.none;
        _highlightScrollBaseline = null;
      });
    });
  }

  /// §255 — скролл к строке владельца + вспышка. Retry по кадрам: строка за
  /// вьюпортом в lazy-списке не смонтирована (currentContext null); грубо
  /// прыгаем по оценке позиции и повторяем ensureVisible.
  Future<void> _focusEntry(String id, {required int attempt}) async {
    if (!mounted) return;
    if (attempt == 0) {
      _highlightTimer?.cancel();
      _highlightFadeTimer?.cancel();
      setState(() {
        _highlightedEntryId = id;
        _highlightMode = _HighlightMode.focus;
        _highlightOpacity = 1;
      });
    }
    const maxAttempts = 6;
    final ctx = _tileKeys[id]?.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: 0.3);
    } else if (attempt < maxAttempts && _scrollController.hasClients) {
      final idx = widget.subController.entries.indexWhere((e) => e.id == id);
      if (idx >= 0) {
        final target = (idx * 88.0)
            .clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.jumpTo(target);
      }
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _focusEntry(id, attempt: attempt + 1));
      return;
    }
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 2200), () {
      _dismissHighlight(animated: false);
    });
  }

  /// §504 — после успешного add: подсветка + прокрутка к новой записи.
  Future<void> _beginNewEntryHighlight(String id) async {
    if (!mounted) return;
    _highlightTimer?.cancel();
    _highlightFadeTimer?.cancel();
    setState(() {
      _highlightedEntryId = id;
      _highlightMode = _HighlightMode.newEntry;
      _highlightOpacity = 1;
      _snackBarClearance = 80;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _programmaticScroll = true;
    await _scrollToEntry(id);
    _programmaticScroll = false;
    if (!mounted) return;
    _highlightScrollBaseline =
        _scrollController.hasClients ? _scrollController.offset : 0;
    _highlightTimer = Timer(const Duration(seconds: 7), () {
      _dismissHighlight(animated: true);
    });
  }

  /// Прокрутка к строке записи (~300 мс, ближе к центру — не под SnackBar).
  ///
  /// ensureVisible не ждём до конца Future: в widget-тестах без pump'ов это
  /// зависает, а SnackBar должен выйти после анимации — хватает длительности.
  Future<void> _scrollToEntry(String id, {int attempt = 0}) async {
    if (!mounted) return;
    final ctx = _tileKeys[id]?.currentContext;
    if (ctx != null) {
      unawaited(Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.45,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 320));
      return;
    }
    if (attempt < 6 && _scrollController.hasClients) {
      final idx = widget.subController.entries.indexWhere((e) => e.id == id);
      if (idx >= 0) {
        final target = (idx * 88.0)
            .clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.jumpTo(target);
      }
      await WidgetsBinding.instance.endOfFrame;
      return _scrollToEntry(id, attempt: attempt + 1);
    }
  }

  Future<void> _loadCompactEntries() async {
    final raw = await SettingsStorage.getVar(_compactEntriesStorageKey, '[]');
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final ids = decoded.whereType<String>().toSet();
        if (!mounted) return;
        setState(() => _compactEntryIds
          ..clear()
          ..addAll(ids));
      }
    } catch (_) {
      // Повреждённое значение не должно мешать открытию раздела.
    }
  }

  Future<void> _saveCompactEntries() => SettingsStorage.setVar(
        _compactEntriesStorageKey,
        jsonEncode(_compactEntryIds.toList()),
      );

  Future<void> _loadAutoUpdateFlag() async {
    final v = await SettingsStorage.getAutoUpdateSubs();
    if (!mounted) return;
    setState(() => _autoUpdateEnabled = v);
  }

  /// §375 — спрашиваем платформу о камере один раз при открытии экрана:
  /// меню строится синхронно в itemBuilder, асинхронную проверку туда не
  /// вставить.
  Future<void> _loadCameraAvailability() async {
    final v = await UrlLauncher.hasCamera();
    if (!mounted) return;
    setState(() => _hasCamera = v);
  }

  // ── §393 C7/D1 — источники-цепочки ─────────────────────────────────────

  /// §524 — перечитать общий список источников одним чтением.
  Future<void> _loadSortState() async {
    final values = await Future.wait<String>([
      SettingsStorage.getVar(_sortSettingsStorageKey, ''),
      SettingsStorage.getVar(_sortMetadataStorageKey, '{}'),
    ]);
    final settings = SourceSortSettings.fromJson(values[0]);

    final metadata = <String, SourceSortTimestamps>{};
    try {
      final decoded = jsonDecode(values[1]);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final key = entry.key?.toString();
          final value = entry.value;
          if (key == null || value is! Map) continue;
          final created =
              DateTime.tryParse(value['created_at']?.toString() ?? '');
          final modified =
              DateTime.tryParse(value['modified_at']?.toString() ?? '');
          if (created != null || modified != null) {
            metadata[key] = SourceSortTimestamps(
              createdAt: created?.toUtc(),
              modifiedAt: modified?.toUtc(),
            );
          }
        }
      }
    } catch (_) {
      // Broken optional metadata must never prevent the list from opening.
    }

    if (!mounted) return;
    setState(() {
      _sortSettings = settings;
      _sortMetadata
        ..clear()
        ..addAll(metadata);
      _sortStateReady = true;
    });
    await _loadSourceOrder();
  }

  Future<void> _saveSortSettings() => SettingsStorage.setVar(
        _sortSettingsStorageKey,
        jsonEncode(_sortSettings.toJson()),
      );

  Future<void> _saveSortMetadata() {
    final encoded = <String, dynamic>{
      for (final entry in _sortMetadata.entries)
        entry.key: {
          if (entry.value.createdAt != null)
            'created_at': entry.value.createdAt!.toUtc().toIso8601String(),
          if (entry.value.modifiedAt != null)
            'modified_at': entry.value.modifiedAt!.toUtc().toIso8601String(),
        },
    };
    return SettingsStorage.setVar(
      _sortMetadataStorageKey,
      jsonEncode(encoded),
    );
  }

  void _updateSortSettings(SourceSortSettings next) {
    if (!mounted) return;
    setState(() => _sortSettings = next);
    unawaited(_saveSortSettings());
  }

  void _cycleSourceSort() {
    _updateSortSettings(
      _sortSettings.copyWith(mode: _sortSettings.mode.next),
    );
  }

  void _openSourceSortOptions() {
    unawaited(
      showSourceSortOptions(
        context,
        settings: _sortSettings,
        onChanged: _updateSortSettings,
      ),
    );
  }

  Future<void> _loadSourceOrder() async {
    final sources = await widget.subController.sourceEntries();
    if (!mounted) return;

    final metadataChanged = _refreshSortMetadata(sources);
    setState(() => _sources = sources);
    if (metadataChanged) unawaited(_saveSortMetadata());
  }

  bool _refreshSortMetadata(List<SourceEntry> sources) {
    final oldByKey = <String, SourceEntry>{
      for (final entry in _sources) entry.sourceKey: entry,
    };
    final now = DateTime.now().toUtc();
    var changed = false;

    final liveKeys = <String>{for (final entry in sources) entry.sourceKey};
    final staleKeys =
        _sortMetadata.keys.where((key) => !liveKeys.contains(key)).toList();
    if (staleKeys.isNotEmpty) {
      for (final key in staleKeys) {
        _sortMetadata.remove(key);
      }
      changed = true;
    }

    for (final entry in sources) {
      final key = entry.sourceKey;
      final current = _sortMetadata[key];
      if (current == null) {
        final created = _initialSourceCreatedAt(entry, now);
        _sortMetadata[key] = SourceSortTimestamps(
          createdAt: created,
          modifiedAt: _initialSourceModifiedAt(entry, created),
        );
        changed = true;
        continue;
      }

      final previous = oldByKey[key];
      if (previous != null && !_sameSourceEntry(previous, entry)) {
        _sortMetadata[key] = current.copyWith(modifiedAt: now);
        changed = true;
      } else if (current.modifiedAt == null) {
        _sortMetadata[key] = current.copyWith(
          modifiedAt: _initialSourceModifiedAt(entry, current.createdAt),
        );
        changed = true;
      }
    }

    return changed;
  }

  DateTime _initialSourceCreatedAt(SourceEntry entry, DateTime now) {
    return switch (entry) {
      ContainerEntry(:final list) => switch (list) {
          FolderServers(:final createdAt) => createdAt.toUtc(),
          SubscriptionServers(:final lastUpdated) =>
            (lastUpdated ?? now).toUtc(),
          UserServer() => now,
        },
      ChainEntry() => now,
      OpaqueEntry() => now,
    };
  }

  DateTime? _initialSourceModifiedAt(
      SourceEntry entry, DateTime? createdAt) {
    return switch (entry) {
      ContainerEntry(:final list) => switch (list) {
          FolderServers() => createdAt,
          SubscriptionServers(
            :final lastUpdateAttempt,
            :final lastUpdated,
          ) =>
            (lastUpdateAttempt ?? lastUpdated ?? createdAt)?.toUtc(),
          UserServer() => createdAt,
        },
      ChainEntry() => createdAt,
      OpaqueEntry() => createdAt,
    };
  }

  bool _sameSourceEntry(SourceEntry a, SourceEntry b) {
    return switch ((a, b)) {
      (ContainerEntry(list: final x), ContainerEntry(list: final y)) =>
        x == y,
      (ChainEntry(chain: final x), ChainEntry(chain: final y)) => x == y,
      _ => true,
    };
  }

  void _onControllerForSourceOrder() {
    if (!_sortStateReady) return;
    _forgetGoneEntries();
    unawaited(_loadSourceOrder());
  }

  /// §511 m1 — запись ушла (удалена из меню, пропала при обновлении
  /// подписки): подсветка с её id снимается, а не живёт до таймера, и
  /// `GlobalKey` строки не копится в [_tileKeys] до закрытия экрана.
  void _forgetGoneEntries() {
    final ids = _entryIds(widget.subController);
    _tileKeys.removeWhere((id, _) => !ids.contains(id));
    final hl = _highlightedEntryId;
    if (hl != null && !ids.contains(hl)) _dismissHighlight(animated: false);
  }

  /// §524 — жест перестановки общего списка в виджет-тесте: адресуется
  /// индексами строк, как `onReorderItem`, минус drag-механика.
  @visibleForTesting
  Future<void> debugReorderRows(int oldIndex, int newIndex) =>
      _reorderRows(widget.subController, oldIndex, newIndex);

  /// §524 — перечитать общий список (как это делает слушатель контроллера).
  @visibleForTesting
  Future<void> debugReloadSources() => _loadSourceOrder();

  @visibleForTesting
  String? get debugHighlightedEntryId => _highlightedEntryId;

  @visibleForTesting
  Iterable<String> get debugTileKeyIds => _tileKeys.keys;

  /// Создание цепочки: тег спрашиваем ДО создания (после он immutable — на
  /// него ссылаются фильтры Направлений, `route_final` и позиции ДРУГИХ
  /// цепочек), затем сразу открываем форму: пустая цепочка ядру не годится
  /// (нужно минимум две позиции), и оставлять пользователя наедине со строкой
  /// «0 hops» смысла нет.
  Future<void> _addChain() async {
    final directions = await SettingsStorage.getDirections();
    if (!mounted) return;
    final req = await showNewChainDialog(
      context,
      usedTags: [
        ..._chains.map((c) => c.tag),
        ...directions.map((d) => d.tag),
      ],
    );
    if (req == null || !mounted) return;
    final SourceChain created;
    try {
      created = await SettingsStorage.addChain(tag: req.tag);
    } on StateError catch (e) {
      // Гонка со вторым источником мутаций (Debug API / restore): форма
      // считала тег свободным, storage — уже нет.
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    await _loadSourceOrder();
    if (!mounted) return;
    await _editChain(created);
  }

  Future<void> _editChain(SourceChain chain) async {
    final outcome = await editChainAndPersist(
      context,
      chain,
      subController: widget.subController,
      homeController: widget.homeController,
    );
    if (outcome == null || !mounted) return;
    await _loadSourceOrder();
    if (!mounted) return;
    // Укороченный маршрут обязан быть замечен: цепочка ниже двух позиций
    // теперь не эмитится, 3+ хопов эмитится короче — пользователь узнаёт об
    // этом здесь, тем же механизмом, что rules/detours-heal (§202/§248).
    _notifyChainPositionsRemoved(outcome.positionsRemoved);
    // Цепочка — узел конфига: правка маршрута обязана доехать до сборки, иначе
    // пользователь увидит старый маршрут под новым именем.
    await _regenerateAndSave();
  }

  /// §439 (D-114) — уведомление о ссылках, погашенных удалением узла или
  /// источника: кто удалён, у скольких источников снят detour, сколько членов
  /// групп и позиций цепочек ушло, с именами (до трёх, дальше `+N`).
  ///
  /// Тот же механизм, что у rules/detours/includes-heal (§202/§248,
  /// `routing_screen._notifyHealed`). Показывать обязательно — удаление МЕНЯЕТ
  /// МАРШРУТ задетых: узел без detour идёт напрямую, цепочка 3+ хопов
  /// эмитится укороченной, 2-хоповая перестаёт эмититься вовсе.
  void _notifyLinksCleared(NodeLinkNotice notice) {
    if (!mounted) return;
    String names(List<String> carriers) {
      final all = [
        for (final n in carriers)
          if (n.isNotEmpty) n,
      ];
      if (all.isEmpty) return '';
      final shown = all.take(3).map((n) => '"$n"').join(', ');
      return ' ($shown${all.length > 3 ? ' +${all.length - 3}' : ''})';
    }

    final subject = notice.subject;
    final lead = switch (subject.kind) {
      NodeLinkSubjectKind.server =>
        getLocalText.s('Server "%s" deleted', subject.name),
      NodeLinkSubjectKind.subscription =>
        getLocalText.s('Subscription "%s" deleted', subject.name),
      NodeLinkSubjectKind.folder =>
        getLocalText.s('Folder "%s" deleted', subject.name),
      NodeLinkSubjectKind.servers =>
        getLocalText.plural('%d servers deleted', subject.count),
    };
    final change = notice.change;
    final parts = [
      if (change.detourCarriers.isNotEmpty)
        getLocalText.s('detour removed from %s source(s)',
                '${change.detourCarriers.length}') +
            names(change.detourCarriers),
      if (change.groupMembers > 0)
        getLocalText.s('%s group member(s) removed', '${change.groupMembers}') +
            names(change.touchedGroups),
      if (change.positions > 0)
        getLocalText.s('%s chain position(s) removed', '${change.positions}') +
            names(change.touchedChains),
    ];
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$lead — ${parts.join(', ')}.'),
    ));
  }

  /// §393 D2 — удаление цепочки сняло её позиции у остальных цепочек.
  void _notifyChainPositionsRemoved(int removed) {
    if (removed <= 0 || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(getLocalText.s('%s chain position(s) removed', '$removed')),
    ));
  }

  /// §439 — забрать уведомления, накопленные контроллером на удалении, и
  /// показать их; цепочки перечитать, если реестр ссылок их переписал (иначе
  /// буфер экрана затёр бы переписанные позиции следующей правкой). Контроллер
  /// копит, экран показывает: у контроллера нет `BuildContext`, а у экрана —
  /// знания, какие мутации сейчас прошли.
  void _drainLinkNotices() {
    final ctrl = widget.subController;
    if (ctrl.takeChainsRelinked()) {
      unawaited(_loadSourceOrder()); // строки цепочек показывают новое число хопов
    }
    for (final notice in ctrl.takeLinkNotices()) {
      _notifyLinksCleared(notice);
    }
  }

  Future<void> _toggleChain(SourceChain chain) async {
    await SettingsStorage.updateChain(
        chain.copyWith(enabled: !chain.enabled));
    await _loadSourceOrder();
    if (!mounted) return;
    await _regenerateAndSave();
  }

  Future<void> _toggleAutoUpdate() async {
    final next = !_autoUpdateEnabled;
    await SettingsStorage.setAutoUpdateSubs(next);
    if (!mounted) return;
    setState(() => _autoUpdateEnabled = next);
  }

  @override
  void deactivate() {
    // Уход с экрана снимает подсветку (§504). setState здесь нельзя: дерево
    // в фазе сборки, debug ловит assert. Поля — напрямую; при activate()
    // элемент перестроится сам.
    _highlightTimer?.cancel();
    _highlightFadeTimer?.cancel();
    _highlightedEntryId = null;
    _highlightMode = _HighlightMode.none;
    _highlightOpacity = 0;
    _highlightScrollBaseline = null;
    super.deactivate();
  }

  @override
  void dispose() {
    widget.subController.removeListener(_onControllerForSourceOrder);
    _inputController.removeListener(_onInputForHighlightDismiss);
    _scrollController.removeListener(_onScrollForHighlightDismiss);
    _inputController.dispose();
    _scrollController.dispose();
    _highlightTimer?.cancel();
    _highlightFadeTimer?.cancel();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    // Unsaved-input guard (night T4-3): если юзер ввёл что-то в поле и
    // уходит со screen без сабмита — подтверждаем, чтобы не терять URL
    // / proxy-link, который он только что вставил.
    final pending = _inputController.text.trim();
    if (pending.isEmpty) return true;
    if (!mounted) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("Discard input?")),
        content: Text(getLocalText.s("You have unsaved text in the input field. Leave and discard it?")),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(getLocalText.s("Stay")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(getLocalText.s("Discard")),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// §074 — open Add server wizard (long-press на «+»). Wizard сам зовёт
  /// `addUserServer`/`addFromInput`; после successful add — callback
  /// делает `_regenerateAndSave` тут.
  void _openAddServerWizard() {
    final baseline = _entryIds(widget.subController);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AddServerWizardScreen(
        subController: widget.subController,
        onAdded: () => _regenerateAndSave(entryBaseline: baseline),
      ),
    ));
  }

  /// Открыть App Settings сразу на табе «Subscriptions» (initialTab: 2).
  void _openSubscriptionSettings() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const AppSettingsScreen(initialTab: 2),
    ));
  }

  /// §025 — открыть full-screen визард Cloudflare WARP.
  void _openWarpWizard() {
    final baseline = _entryIds(widget.subController);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WarpWizardScreen(
        subController: widget.subController,
        onAdded: () => _regenerateAndSave(entryBaseline: baseline),
      ),
    ));
  }

  /// §500 — при отказе с известной причиной открыть шторку сразу после add.
  void _presentParseRejectSheetIfNeeded() {
    final err = widget.subController.lastError;
    if (err is! ParseInputRejectedMsg || !err.hasDropped || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showNodeWarningsSheet(context, err.dropped, sourceLabel: err.sourceLabel);
    });
  }

  /// §585 — комментарии вставленного JSON убраны из источника записи.
  void _snackCommentsRemoved() {
    if (!mounted || !widget.subController.lastCommentsRemoved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(getLocalText.s("Comments were removed."))),
    );
  }

  Future<void> _add() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      // Пустое поле + тап «+» = paste-from-clipboard поток с диалогом
      // подтверждения (анализ + предпросмотр).
      await _pasteFromClipboard();
      return;
    }
    final baseline = _entryIds(widget.subController);
    await widget.subController.addFromInput(text);
    if (widget.subController.lastError == null) {
      _ignoreInputDismiss = true;
      _inputController.clear();
      _ignoreInputDismiss = false;
      _snackCommentsRemoved();
      await _regenerateAndSave(entryBaseline: baseline);
    } else {
      _presentParseRejectSheetIfNeeded();
    }
  }

  /// После любого add'а — пересобрать конфиг и сохранить, чтобы новые
  /// узлы попали в выбираемые group'ы без ручного нажатия rebuild.
  ///
  /// [entryBaseline] — id записей до add; при успехе §504 прокручивает к первой
  /// новой и подсвечивает её, SnackBar — после прокрутки.
  Future<void> _regenerateAndSave({Set<String>? entryBaseline}) async {
    final applied = await regenerateSourcesConfig(
        widget.subController, widget.homeController);
    if (!mounted || applied == null) return;
    final n = widget.subController.entries
        .where((e) => e.enabled)
        .fold<int>(0, (s, e) => s + e.nodeCount);
    final newEntryId = entryBaseline == null
        ? null
        : _firstNewEntryId(entryBaseline, widget.subController);
    if (newEntryId != null) {
      await _beginNewEntryHighlight(newEntryId);
      if (!mounted) return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(applied
              ? getLocalText.plural("Config regenerated & applied: %d nodes", n)
              : getLocalText.plural("Config regenerated: %d nodes", n)),
          duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(getLocalText.s("Clipboard is empty"))),
        );
      }
      return;
    }

    final analysis = analyzeClipboard(text);
    if (!mounted) return;

    if (analysis.type == 'unknown') {
      showUnknownFormatDialog(context, text);
      return;
    }

    final confirmed = await showConfirmAddDialog(context, analysis);

    if (confirmed != true || !mounted) return;
    final baseline = _entryIds(widget.subController);
    await widget.subController.addFromInput(text);
    final addErr = widget.subController.lastError;
    if (addErr == null) {
      _snackCommentsRemoved();
      await _regenerateAndSave(entryBaseline: baseline);
    } else if (mounted) {
      _presentParseRejectSheetIfNeeded();
      if (addErr is! ParseInputRejectedMsg || !addErr.hasDropped) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(addErr.render())),
        );
      }
    }
  }

  /// §375 — импорт по QR-коду с камеры. Сканер только поставляет строку:
  /// разбор формата и подтверждение — тот же путь, что у буфера обмена, так
  /// что юзер видит, что именно приехало в коде, до записи в конфиг (QR —
  /// недоверенный ввод из внешнего мира).
  Future<void> _scanQrCode() async {
    final outcome = await Navigator.of(context).push<ScanOutcome>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (!mounted) return;

    // Уход системной кнопкой «назад» — pop без значения.
    if (outcome is! ScannedCode) {
      final problem =
          outcome == null ? null : scanProblemText(outcome);
      if (problem != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(problem)),
        );
      }
      return;
    }

    final text = outcome.value;
    final analysis = analyzeClipboard(text);
    if (!mounted) return;

    if (analysis.type == 'unknown') {
      showUnknownFormatDialog(context, text);
      return;
    }

    final confirmed = await showConfirmAddDialog(context, analysis);
    if (confirmed != true || !mounted) return;

    final baseline = _entryIds(widget.subController);
    await widget.subController
        .addFromInput(text, origin: UserSource.qr);
    final addErr = widget.subController.lastError;
    if (addErr == null) {
      await _regenerateAndSave(entryBaseline: baseline);
    } else if (mounted) {
      _presentParseRejectSheetIfNeeded();
      if (addErr is! ParseInputRejectedMsg || !addErr.hasDropped) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(addErr.render())),
        );
      }
    }
  }

  /// §234 — создать пустую папку серверов.
  Future<void> _createFolder() async {
    final name = await showFolderNameDialog(context);
    if (name == null) return;
    final baseline = _entryIds(widget.subController);
    await widget.subController.addFolder(name);
    if (!mounted) return;
    final newId = _firstNewEntryId(baseline, widget.subController);
    if (newId != null) await _beginNewEntryHighlight(newId);
  }

  /// Импорт подписки/конфига из файла. Содержимое (URI-список, JSON-конфиг,
  /// proxy-link) идёт в тот же `addFromInput`, что и paste/manual — парсер
  /// сам определяет формат. Файл приходит уже прочитанным ([PickedFile]).
  ///
  /// §234 — multi-select: несколько файлов → все серверы в новую папку
  /// (имена нод — из имён файлов). Один файл — прежние пути (§129
  /// file-подписка при >1 ноды / одиночный сервер).
  Future<void> _importFromFile() async {
    try {
      // §372 — Android TV без файлового менеджера: подсказка вместо тупика.
      final outcome = await pickFileSafely(allowMultiple: true);
      if (outcome is! PickedFiles) {
        final problem = pickProblemText(outcome);
        if (problem != null && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(problem)));
        }
        return;
      }
      if (outcome.files.length > 1) {
        await _importFilesIntoFolder(outcome.files);
        return;
      }
      final file = outcome.single;
      final text = file.text.trim();
      if (text.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(getLocalText.s("File is empty"))),
          );
        }
        return;
      }
      if (!mounted) return;
      final baseline = _entryIds(widget.subController);
      // §129 — если в файле > 1 ноды, создаём ФАЙЛОВУЮ подписку (снапшот в
      // кэше, живёт как обычная подписка). ≤ 1 ноды → старое поведение
      // (addFromInput → одиночный сервер/нода).
      final asFileSub =
          await widget.subController.addFileSubscription(text, file.name);
      if (!asFileSub) {
        if (!mounted) return;
        // §243 — имя файла уходит nameHint'ом: для WG/AWG `.conf` оно
        // становится tag'ом узла (фрагмент синтетического URI). Прежний
        // §234-renameAt в entry.name убран — displayName одиночного сервера
        // name игнорирует, правда живёт в tag'е.
        await widget.subController.addFromInput(text,
            nameHint: SubscriptionController.fileBaseName(file.name));
      }
      final importErr = widget.subController.lastError;
      if (importErr == null) {
        await _regenerateAndSave(entryBaseline: baseline);
      } else if (mounted) {
        _presentParseRejectSheetIfNeeded();
        if (importErr is! ParseInputRejectedMsg || !importErr.hasDropped) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(importErr.render())),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(getLocalText.s(
                  "Error: %s", formatUserError(e).render()))),
        );
      }
    }
  }

  /// §234 — несколько выбранных файлов → новая папка со всеми серверами.
  Future<void> _importFilesIntoFolder(List<PickedFile> files) async {
    final name = await showFolderNameDialog(context,
        title: getLocalText.plural("Import %d files into folder", files.length));
    if (name == null || !mounted) return;
    final baseline = _entryIds(widget.subController);
    await widget.subController.addFolder(name);
    final folderIndex = widget.subController.entries.length - 1;
    var addedFiles = 0;
    final errors = <String>[];
    for (final file in files) {
      final text = file.text.trim();
      if (text.isEmpty) {
        errors.add(getLocalText.s("%s: empty file", file.name));
        continue;
      }
      final err = await widget.subController.addMembersToFolder(
        folderIndex,
        text,
        nameFallback: SubscriptionController.fileBaseName(file.name),
      );
      if (err == null) {
        addedFiles++;
      } else {
        errors.add('${file.name}: ${err.render()}');
      }
    }
    if (!mounted) return;
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errors.join('\n'))),
      );
    }
    if (addedFiles > 0) {
      await _regenerateAndSave(entryBaseline: baseline);
    }
  }

  Future<void> _updateAll() async {
    // Ручной force-refresh: сбрасываем session-cap (5 фейлов) и форсим через
    // AutoUpdater — так получаем `_running` guard от дубль-кликов и общий
    // логирующий путь. После fetch'а — локальный generateConfig (без HTTP).
    widget.autoUpdater.resetAllFailCounts();
    final ran = await widget.autoUpdater
        .maybeUpdateAll(UpdateTrigger.manual, force: true);
    if (!mounted) return;
    // §603 — проход уже идёт (автообновление или прошлое нажатие): этот вызов
    // ничего не обновил. Пересборка и «Config generated» выдавали бы его за
    // успешное обновление; идущий проход сам применит реакцию подписок.
    if (!ran) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(getLocalText
              .s("Subscriptions are already updating. Try again later.")),
        ),
      );
      return;
    }
    final config = await widget.subController.generateConfig();
    if (!mounted) return;
    if (config != null) {
      final ok = await widget.homeController.saveParsedConfig(config);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              getLocalText.plural("Config generated: %d nodes", widget.subController.entries
                  .fold<int>(0, (s, e) => s + e.nodeCount)),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.subController,
      builder: (context, _) {
        final ctrl = widget.subController;
        // §439 — уведомления о погашенных ссылках накопил контроллер
        // (удаление источника идёт из контекстного меню, у которого нет ни
        // нашего состояния, ни списка цепочек). Забираем их ПОСЛЕ кадра:
        // snackbar во время build запрещён, а мутация уже завершилась —
        // контроллер как раз поэтому и уведомил.
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _drainLinkNotices());
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (await _onWillPop()) {
              if (context.mounted) Navigator.of(context).pop();
            }
          },
          child: Scaffold(
            body: RefreshIndicator(
              // SliverAppBar + CustomScrollView позволяют верхней части
              // (заголовок + поле URL) автоматически уезжать при прокрутке
              // вниз и возвращаться при прокрутке вверх.
              onRefresh: () async {
                if (ctrl.busy) return;
                await _updateAll();
              },
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverAppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(getLocalText.s("Servers")),
                  Text(getLocalText.s("Subscriptions & proxy"),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.normal)),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: getLocalText.s("Update all & generate"),
                  onPressed: ctrl.busy ? null : () => unawaited(_updateAll()),
                  icon: const Icon(Icons.refresh),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    // §074: «Add server» — duplicate access к wizard'у
                    // (long-press на «+» — discoverability через accidental,
                    // overflow menu — explicit affordance).
                    if (v == 'wizard') _openAddServerWizard();
                    if (v == 'warp') _openWarpWizard();
                    if (v == 'public') unawaited(_pickPublicTestServer());
                    if (v == 'paste') unawaited(_pasteFromClipboard());
                    if (v == 'qr') unawaited(_scanQrCode());
                    if (v == 'file') unawaited(_importFromFile());
                    if (v == 'folder') unawaited(_createFolder());
                    if (v == 'chain') unawaited(_addChain());
                    if (v == 'auto_update') unawaited(_toggleAutoUpdate());
                    if (v == 'sub_settings') _openSubscriptionSettings();
                  },
                  itemBuilder: (_) => [
                    // Раскладка утверждена оператором 24.08: четыре смысловые
                    // секции — создать / получить готовое / импортировать / подписки.
                    PopupMenuItem(value: 'wizard', child: Text(getLocalText.s("Add server…"))),
                    // §393 C7 — цепочка это ТРЕТИЙ ТИП ИСТОЧНИКА (маршрут через
                    // несколько хопов подряд): создание рядом с сервером, а не среди
                    // Направлений (§393 L5).
                    PopupMenuItem(
                        value: 'chain',
                        child: Text(getLocalText.s("Add hop chain…"))),
                    PopupMenuItem(value: 'folder', child: Text(getLocalText.s("New folder…"))),
                    const PopupMenuDivider(),
                    PopupMenuItem(value: 'warp', child: Text(getLocalText.s("Get WARP"))),
                    if (CommunityServersLoader.enabled)
                      PopupMenuItem(value: 'public', child: Text(getLocalText.s("Get Public Test Servers"))),
                    const PopupMenuDivider(),
                    PopupMenuItem(value: 'paste', child: Text(getLocalText.s("Paste from clipboard"))),
                    // §375 — на устройстве без камеры (Android TV) пункта нет:
                    // альтернативы у сканирования не существует, и пункт,
                    // который всегда отвечает «нельзя», — мусор в меню.
                    if (_hasCamera ?? true)
                      PopupMenuItem(value: 'qr', child: Text(getLocalText.s("Scan QR code"))),
                    PopupMenuItem(value: 'file', child: Text(getLocalText.s("Import from file…"))),
                    const PopupMenuDivider(),
                    CheckedPopupMenuItem<String>(
                      value: 'auto_update',
                      checked: _autoUpdateEnabled,
                      child: Text(getLocalText.s("Auto-update subscriptions")),
                    ),
                    PopupMenuItem(
                      value: 'sub_settings',
                      child: Text(getLocalText.s("Subscription settings…")),
                    ),
                  ],
                ),
                  ],
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(104),
                    child: _buildInputBar(ctrl),
                  ),
                  floating: true,
                  snap: true,
                ),

                  if (ctrl.lastError != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ParseInputErrorBanner(ctrl.lastError!),
                      ),
                    ),
                  if (ctrl.progressMessage != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(ctrl.progressMessage!.render())),
                          ],
                        ),
                      ),
                    ),
                  _buildList(ctrl),
                ],
              ),
            )
          ),
        );
      },
    );
  }

  Widget _buildInputBar(SubscriptionController ctrl) {
    final hasSources = _sources.isNotEmpty || ctrl.entries.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  onChanged: (_) => _onInputForHighlightDismiss(),
                  decoration: InputDecoration(
                    hintText: getLocalText.s("Subscription URL or proxy link"),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              // §074: tap = paste-from-clipboard / parse text input (existing).
              // long-press = full-screen Add server wizard (SOCKS5 form / Paste
              // URI / Paste JSON tabs).
              //
              // НЕ IconButton — у того встроенный Tooltip widget (даже без
              // tooltip:, Material InkWell внутри его перехватывает long-press
              // первым в gesture arena). Используем raw InkWell + Material
              // styled под IconButton.filled (primary container + circle).
              AddIconButton(
                busy: ctrl.busy,
                onTap: () => unawaited(_add()),
                onLongPress: _openAddServerWizard,
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Tooltip(
              message: _sortSettings.mode.label(),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Semantics(
                    button: true,
                    label: _sortSettings.mode.label(),
                    child: Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: hasSources ? _cycleSourceSort : null,
                        onLongPress:
                            hasSources ? _openSourceSortOptions : null,
                        borderRadius: BorderRadius.circular(18),
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: Center(
                            child: Icon(
                              _sortSettings.mode.icon,
                              size: 20,
                              color: hasSources
                                  ? null
                                  : Theme.of(context).disabledColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (isSourceSortNonDefault(_sortSettings))
                    Positioned(
                      right: 4,
                      top: 4,
                      child: IgnorePointer(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.amber,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(BuildContext context, int index, SubscriptionEntry entry) {
    showEntryContextMenu(
      context,
      index,
      entry,
      subController: widget.subController,
      autoUpdater: widget.autoUpdater,
    );
  }

  Future<void> _launchUrl(String url) async {
    final opened = await UrlLauncher.open(url);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(getLocalText.s("Copied: %s", url))),
      );
    }
  }

  Future<void> _pickPublicTestServer() async {
    await pickPublicTestServer(
      context,
      onSelectSource: (source) => _inputController.text = source,
    );
  }

  /// §524 — строки общего списка: ОДИН [_sources], без сшивки трёх источников.
  /// Взаимный порядок цепочек внутри него держит инвариант «позиция ссылается
  /// только на цепочку ВЫШЕ».
  ///
  /// Фолбэк «[_sources] пусто» — только первый кадр до [_loadSourceOrder]:
  /// рисуем записи контроллера в их порядке, чтобы список не мигал пустым.
  List<_SourceRow> _rows(SubscriptionController ctrl) {
    final byId = <String, int>{
      for (var i = 0; i < ctrl.entries.length; i++) ctrl.entries[i].id: i,
    };
    if (_sources.isEmpty) {
      return [
        for (var i = 0; i < ctrl.entries.length; i++)
          _SourceRow.entry(ctrl.entries[i], i),
      ];
    }
    final rows = <_SourceRow>[];
    for (final e in _sources) {
      switch (e) {
        case ChainEntry(:final chain):
          rows.add(_SourceRow.chain(chain));
        case ContainerEntry(:final list):
          // Индекс записи в контроллере — счёт его мутаций, не общего списка.
          final at = byId[list.id];
          if (at != null) rows.add(_SourceRow.entry(ctrl.entries[at], at));
        case OpaqueEntry():
          // §141 P1.8c — запись, которую кодек не читает: показывать нечего,
          // и перестановка её не адресует (она остаётся в своём слоте).
          break;
      }
    }
    return rows;
  }

  List<_SourceDisplayRow> _displayRows(SubscriptionController ctrl) {
    final rows = sortSourceItems(
      _rows(ctrl),
      _sortSettings,
      nameOf: (row) => row.displayLabel,
      kindOf: (row) => row.kind,
      modifiedOf: (row) => _sortMetadata[row.sourceKey]?.modifiedAt,
      createdOf: (row) => _sortMetadata[row.sourceKey]?.createdAt,
    );

    if (!_sortSettings.groupByType) {
      return [for (final row in rows) _SourceDisplayRow.item(row)];
    }

    final out = <_SourceDisplayRow>[];
    String? previousKind;
    for (final row in rows) {
      if (row.kind != previousKind) {
        out.add(_SourceDisplayRow.header(row.kind));
        previousKind = row.kind;
      }
      out.add(_SourceDisplayRow.item(row));
    }
    return out;
  }

  Widget _buildSourceGroupHeader(String kind) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
      child: Row(
        children: [
          Icon(sourceTypeIcon(kind), size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            sourceTypeLabel(kind),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              height: 1,
              color: color.withValues(alpha: 0.22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(SubscriptionController ctrl) {
    final displayRows = _displayRows(ctrl);
    if (displayRows.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: SubscriptionsEmptyState(
          busy: ctrl.busy,
          onPickPublicTestServer: CommunityServersLoader.enabled
              ? () => unawaited(_pickPublicTestServer())
              : null,
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        MediaQuery.of(context).padding.bottom + 24 + _snackBarClearance,
      ),
      sliver: SliverList.builder(
        itemCount: displayRows.length,
        itemBuilder: (context, i) {
          final displayRow = displayRows[i];
          if (displayRow.isHeader) {
            return KeyedSubtree(
              key: ValueKey('source-group:${displayRow.groupKind!}'),
              child: _buildSourceGroupHeader(displayRow.groupKind!),
            );
          }

          final row = displayRow.row!;
          final chain = row.chain;
          if (chain != null) {
            return KeyedSubtree(
              key: ValueKey('chain:${chain.tag}'),
              child: ChainEntryTile(
                chain: chain,
                compact: _compactEntryIds.contains('chain:${chain.tag}'),
                onCompactChanged: (compact) {
                  final key = 'chain:${chain.tag}';
                  setState(() {
                    if (compact) {
                      _compactEntryIds.add(key);
                    } else {
                      _compactEntryIds.remove(key);
                    }
                  });
                  unawaited(_saveCompactEntries());
                },
                onTap: () => unawaited(_editChain(chain)),
                onToggle: () => unawaited(_toggleChain(chain)),
              ),
            );
          }

          final entry = row.entry!;
          final at = row.entryIndex;
          final highlighted = _highlightedEntryId == entry.id;
          final showNewBadge = highlighted &&
              _highlightMode == _HighlightMode.newEntry &&
              _highlightOpacity > 0;
          final cs = Theme.of(context).colorScheme;

          return KeyedSubtree(
            key: ValueKey(entry.id),
            child: AnimatedContainer(
              key: _tileKey(entry.id),
              duration: const Duration(milliseconds: 400),
              decoration: highlighted
                  ? BoxDecoration(
                      color: cs.primaryContainer
                          .withValues(alpha: 0.5 * _highlightOpacity),
                      border: _highlightMode == _HighlightMode.focus
                          ? Border(
                              left: BorderSide(color: cs.primary, width: 3))
                          : null,
                    )
                  : null,
              child: Material(
                type: MaterialType.transparency,
                child: SubscriptionEntryTile(
                  entry: entry,
                  subController: widget.subController,
                  showNewBadge: showNewBadge,
                  onToggle: () {
                    _onUserInteractionDismissHighlight();
                    unawaited(widget.subController.toggleAt(at));
                  },
                  onLaunchUrl: _launchUrl,
                  compact: _compactEntryIds.contains(entry.id),
                  onCompactChanged: (compact) {
                    setState(() {
                      if (compact) {
                        _compactEntryIds.add(entry.id);
                      } else {
                        _compactEntryIds.remove(entry.id);
                      }
                    });
                    unawaited(_saveCompactEntries());
                  },
                  onLongPress: (context) =>
                      _showContextMenu(context, at, entry),
                  onTap: (context) {
                    _onUserInteractionDismissHighlight();
                    if (entry.list is FolderServers) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FolderDetailScreen(
                            entry: entry,
                            controller: widget.subController,
                          ),
                        ),
                      );
                      return;
                    }
                    final isDirectServer =
                        entry.url.isEmpty && entry.connections.isNotEmpty;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => isDirectServer
                            ? NodeSettingsScreen(
                                entry: entry,
                                index: at,
                                subController: widget.subController,
                              )
                            : SubscriptionDetailScreen(
                                entry: entry,
                                controller: widget.subController,
                              ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// §524 — перестановка в общем списке источников: ОДНА запись на жест.
  ///
  /// До §524 жест писал дважды — `reorderSources` и `applyEntryOrder`, — и
  /// каждая падала независимо; порядок контейнеров зеркалится в памяти
  /// (`applySourceOrder`), а не вторым `_persist`. «Цепочка ссылается только
  /// вверх» считается по взаимному порядку цепочек; сервер между ними ссылок
  /// не ломает.
  Future<void> _reorderRows(
      SubscriptionController ctrl, int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final rows = _rows(ctrl);
    if (oldIndex < 0 || oldIndex >= rows.length) return;
    if (newIndex < 0 || newIndex >= rows.length) return;
    final moved = [...rows];
    moved.insert(newIndex, moved.removeAt(oldIndex));

    final oldChainTags = [
      for (final r in rows)
        if (r.chain != null) r.chain!.tag,
    ];
    final newChainTags = [
      for (final r in moved)
        if (r.chain != null) r.chain!.tag,
    ];

    await ctrl.applySourceOrder([
      for (final r in moved)
        if (r.chain != null)
          sourceKeyForChainOf(r.chain!.tag)
        else
          sourceKeyForIdOf(r.entry!.id),
    ]);
    await _loadSourceOrder();
    if (!mounted) return;
    var chainsMoved = oldChainTags.length != newChainTags.length;
    if (!chainsMoved) {
      for (var i = 0; i < oldChainTags.length; i++) {
        if (oldChainTags[i] != newChainTags[i]) {
          chainsMoved = true;
          break;
        }
      }
    }
    if (chainsMoved) await _regenerateAndSave();
  }
}

/// §255 — навигация из detour-cycle sheet. §504 — свежедобавленная запись.
enum _HighlightMode { none, focus, newEntry }

/// §393 D1 — ряд общего списка источников: либо запись контроллера
/// (подписка/сервер/папка), либо цепочка. Ровно два рода, поэтому обычный
/// класс с двумя nullable-полями, а не sealed-иерархия: тип живёт внутри
/// одного экрана и наружу не выходит.
class _SourceRow {
  const _SourceRow.entry(this.entry, this.entryIndex) : chain = null;
  const _SourceRow.chain(this.chain)
      : entry = null,
        entryIndex = -1;

  final SubscriptionEntry? entry;

  /// Индекс записи в `SubscriptionController.entries` — счёт контроллера, не
  /// общего списка. Мутации подписок адресуются им.
  final int entryIndex;
  final SourceChain? chain;

  String get sourceKey => chain != null
      ? sourceKeyForChainOf(chain!.tag)
      : sourceKeyForIdOf(entry!.id);

  String get kind {
    if (chain != null) return kSourceKindChainKey;
    return switch (entry!.list) {
      SubscriptionServers() => 'subscription',
      UserServer() => 'server',
      FolderServers() => 'folder',
    };
  }

  String get displayLabel => chain != null ? chain!.tag : entry!.list.name;
}

class _SourceDisplayRow {
  const _SourceDisplayRow.item(this.row) : groupKind = null;
  const _SourceDisplayRow.header(this.groupKind) : row = null;

  final _SourceRow? row;
  final String? groupKind;

  bool get isHeader => groupKind != null;
}
