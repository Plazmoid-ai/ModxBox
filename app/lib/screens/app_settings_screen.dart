import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/home_controller.dart';
import '../controllers/subscription_controller.dart';
import '../services/subscription/auto_updater.dart';
import '../main.dart';
import '../services/change_journal.dart';
import '../services/debug/bootstrap.dart';
import '../services/debug/transport/server.dart';
import '../services/haptic_service.dart';
import '../services/l10n/locale_controller.dart';
import '../services/settings_storage.dart';
import '../services/subscription/subscription_identity.dart';
import '../services/subscription/user_agent.dart';
import '../services/url_launcher.dart' as ul;
import '../services/usage_region.dart';
import '../services/warp/warp_endpoint_picker.dart';
import '../services/wifi_history_listener.dart';
import '../widgets/wifi_permission_dialog.dart';
import '../widgets/user_agent_dialog.dart';
import '../vpn/box_vpn_client.dart';
import 'app_settings_screen/app_settings_dialogs.dart';
import 'dns_settings_screen.dart';
import 'routing_screen.dart';
import 'subscriptions_screen.dart';
import 'app_settings_screen/widgets/appearance_tab.dart';
import 'app_settings_screen/widgets/automation_tab.dart';
import 'app_settings_screen/widgets/change_journal_tab.dart';
import 'app_settings_screen/widgets/diagnostics_tab.dart';
import 'app_settings_screen/widgets/general_tab.dart';
import 'app_settings_screen/widgets/subscriptions_tab.dart';
import 'backup_screen.dart';
import 'settings_tabs_screen.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({
    super.key,
    this.initialTab = 0,
    this.highlightCoreLogs = false,
    this.homeController,
    this.subController,
    this.autoUpdater,
  });

  /// 0 = General, 1 = Appearance (§541), 2 = Subscriptions, 3 = Diagnostics,
  /// 4 = Automation, 5 = History.
  /// Used by deep-links.
  final int initialTab;

app settings property  /// Если true — после первого render'а скроллим к «Forward sing-box logs»
  /// SwitchListTile и пульсируем подсветку 2.5s. Используется banner'ом
  /// в Live tab чтобы юзер сразу увидел нужный toggle.
  final bool highlightCoreLogs;

  /// Optional navigation context for journal links to DNS settings.
  final HomeController? homeController;
  final SubscriptionController? subController;
  final AutoUpdater? autoUpdater;

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> with WidgetsBindingObserver {
  final GlobalKey<SettingsTabsScreenState> _settingsTabsKey =
      GlobalKey<SettingsTabsScreenState>();
  final _vpn = BoxVpnClient();
  bool _autoStart = false;
  bool _haptic = true;
  bool _batteryWhitelisted = false;
  bool _notificationsEnabled = true;
  bool _backgroundLocationGranted = false;
  bool _nearbyWifiGranted = false;
  String? _wifiLocationIssue;
  bool _autoPing = true;
  bool _autoUpdateSubs = true;
  bool _autoUpdateDisabledSubs = false;
  bool _autoReloadOnChange = false;
  bool _autoCheckUpdates = true;
  // §220 — снятие портретной фиксации (default OFF = портрет).
  bool _allowRotation = false;
  // §541 — две колонки списка узлов на широком окне (default ON).
  bool _nodeListTwoColumns = true;
  bool _loaded = false;
  // §207 — pprof capture in flight (goroutine dump / CPU profile). Guards
  // both buttons so a double-tap can't spin two servers on the same port.

  bool _debugEnabled = false;
  String _debugToken = '';
  int _debugPort = SettingsStorage.debugPortDefault;
  late final TextEditingController _debugPortCtl;
  String _debugPortError = '';

  bool _coreLogsEnabled = false;
  bool _configLocked = false;

  // Для deep-link «highlightCoreLogs» из Live tab banner'а — скроллим
  // к этому tile'у после первого render'а и пульсируем background 2.5s.
  final GlobalKey _coreLogsTileKey = GlobalKey();
  bool _coreLogsHighlighted = false;
  Timer? _coreLogsHighlightTimer;
  // §051 Phase 3 — auto-record visited Wi-Fi networks (default off).
  bool _autoRecordWifi = false;

  // Stable targets used by the change journal to reveal the exact setting.
  final Map<String, GlobalKey> _journalKeys = {
    'usageRegion': GlobalKey(debugLabel: 'journal-usage-region'),
    'autoStart': GlobalKey(debugLabel: 'journal-auto-start'),
    'autoReload': GlobalKey(debugLabel: 'journal-auto-reload'),
    'autoCheckUpdates': GlobalKey(debugLabel: 'journal-auto-check-updates'),
    'autoPing': GlobalKey(debugLabel: 'journal-auto-ping'),
    'haptic': GlobalKey(debugLabel: 'journal-haptic'),
    'allowRotation': GlobalKey(debugLabel: 'journal-allow-rotation'),
    'theme': GlobalKey(debugLabel: 'journal-theme'),
    'language': GlobalKey(debugLabel: 'journal-language'),
    'nodeListTwoColumns': GlobalKey(debugLabel: 'journal-two-columns'),
    'autoUpdateSubs': GlobalKey(debugLabel: 'journal-auto-update-subs'),
    'autoUpdateDisabledSubs': GlobalKey(debugLabel: 'journal-auto-update-disabled-subs'),
    'debugApi': GlobalKey(debugLabel: 'journal-debug-api'),
    'debugPort': GlobalKey(debugLabel: 'journal-debug-port'),
    'configLocked': GlobalKey(debugLabel: 'journal-config-locked'),
    'coreLogs': GlobalKey(debugLabel: 'journal-core-logs'),
    'autoRecordWifi': GlobalKey(debugLabel: 'journal-auto-record-wifi'),
  };

  // §118 — subscription fetch identity (UA override + HWID + device-meta).
  // _deviceOs/_verOs/_deviceModel — OVERRIDE-значения (пусто = device-дефолт).
  String _userAgent = '';
  bool _sendHwid = false;
  String _hwid = '';
  String _deviceOs = '';
  String _verOs = '';
  String _deviceModel = '';
  // §425 — регион использования + автоопределённая страна.
  String _region = SettingsStorage.regionAuto;
  String _detectedRegion = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _debugPortCtl = TextEditingController();
    unawaited(_loadAutoStart());
    if (widget.highlightCoreLogs) {
      // Tile живёт в Diagnostics tab (initialTab=3). Tab сам строит
      // children когда юзер на нём — postFrame этого build'а гарантирует
      // что _coreLogsTileKey.currentContext доступен.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToAndHighlightCoreLogs();
      });
    }
  }

  void _scrollToAndHighlightCoreLogs() {
    final ctx = _coreLogsTileKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.3, // tile в верхней трети viewport'а — так юзер сразу видит
    );
    setState(() => _coreLogsHighlighted = true);
    _coreLogsHighlightTimer?.cancel();
    _coreLogsHighlightTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _coreLogsHighlighted = false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debugPortCtl.dispose();
    _coreLogsHighlightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Юзер вернулся из системных настроек — перечитать whitelist-статус.
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshBatteryStatus());
    }
  }

  Future<void> _loadAutoStart() async {
    // §189 — auto_start / core_logs читаем из JSON-зеркала native_prefs.
    final auto = await SettingsStorage.getNativeBool(NativePrefsKeys.autoStart);
    final haptic = await SettingsStorage.getVar(HapticService.prefsKey, 'true');
    final autoPing = await SettingsStorage.getVar('auto_ping_on_start', 'true');
    final battery = await _vpn.isIgnoringBatteryOptimizations();
    final notifications = await _vpn.areNotificationsEnabled();
    final bgLocation = await ul.UrlLauncher.checkBackgroundLocationPermission();
    final nearbyWifi = await ul.UrlLauncher.checkNearbyWifiPermission();
    final wifiLocationIssue = await _readWifiLocationIssue();
    final autoUpdateSubs = await SettingsStorage.getAutoUpdateSubs();
    final autoUpdateDisabledSubs =
        await SettingsStorage.getAutoUpdateDisabledSubs();
    final autoReloadOnChange = await SettingsStorage.getAutoReloadOnChange();
    final autoCheckUpdates = await SettingsStorage.getAutoCheckUpdates();
    final allowRotation = await SettingsStorage.getAllowRotation();
    final nodeListTwoColumns = await SettingsStorage.getNodeListTwoColumns();
    final debugEnabled = await SettingsStorage.getDebugEnabled();
    final debugToken = await SettingsStorage.getDebugToken();
    final debugPort = await SettingsStorage.getDebugPort();
    final coreLogsEnabled =
        await SettingsStorage.getNativeBool(NativePrefsKeys.coreLogsEnabled);
    final configLocked = await SettingsStorage.getConfigLockedForDebug();
    final autoRecordWifi = await SettingsStorage.getAutoRecordWifi();
    final userAgent =
        await SettingsStorage.getVar(SubscriptionIdentity.varUserAgent, '');
    final sendHwid =
        (await SettingsStorage.getVar(SubscriptionIdentity.varSendHwid,
            'false')) ==
            'true';
    final hwid =
        await SettingsStorage.getVar(SubscriptionIdentity.varHwid, '');
    final deviceOs =
        await SettingsStorage.getVar(SubscriptionIdentity.varDeviceOs, '');
    final verOs =
        await SettingsStorage.getVar(SubscriptionIdentity.varVerOs, '');
    final deviceModel =
        await SettingsStorage.getVar(SubscriptionIdentity.varDeviceModel, '');
    final region = await SettingsStorage.getRegion();
    final detectedRegion = await UsageRegion.detected();
    if (mounted) {
      setState(() {
        _region = region;
        _detectedRegion = detectedRegion;
        _userAgent = userAgent;
        _sendHwid = sendHwid;
        _hwid = hwid;
        _deviceOs = deviceOs;
        _verOs = verOs;
        _deviceModel = deviceModel;
        _autoStart = auto;
        _haptic = haptic != 'false';
        _autoPing = autoPing != 'false';
        _batteryWhitelisted = battery;
        _notificationsEnabled = notifications;
        _backgroundLocationGranted = bgLocation;
        _nearbyWifiGranted = nearbyWifi;
        _wifiLocationIssue = wifiLocationIssue;
        _autoUpdateSubs = autoUpdateSubs;
        _autoUpdateDisabledSubs = autoUpdateDisabledSubs;
        _autoReloadOnChange = autoReloadOnChange;
        _autoCheckUpdates = autoCheckUpdates;
        _allowRotation = allowRotation;
        _nodeListTwoColumns = nodeListTwoColumns;
        _debugEnabled = debugEnabled;
        _debugToken = debugToken;
        _debugPort = debugPort;
        _debugPortCtl.text = debugPort.toString();
        _coreLogsEnabled = coreLogsEnabled;
        _configLocked = configLocked;
        _autoRecordWifi = autoRecordWifi;
        _loaded = true;
      });
    }
  }

  String _journalBoolLabel(bool value) =>
      getLocalText.s(value ? "Enabled" : "Off");

  void _recordSettingChange({
    required String title,
    required String beforeText,
    required String afterText,
    required String path,
    required String target,
    String category = 'important',
    String? actionKey,
    String? beforeValue,
    String? afterValue,
  }) {
    unawaited(ChangeJournalService.record(
      category: category,
      title: title,
      beforeText: beforeText,
      afterText: afterText,
      path: path,
      target: target,
      actionKey: actionKey,
      beforeValue: beforeValue,
      afterValue: afterValue,
    ));
  }

  Future<void> _navigateToJournalEntry(
    BuildContext context,
    ChangeJournalEntry entry,
  ) async {
    final target = entry.target;
    if (target.startsWith('routing.')) {
      final homeController = widget.homeController;
      final subController = widget.subController;
      if (homeController == null || subController == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(getLocalText.s(
              "Open the journal from the main menu to jump to a routing rule.",
            )),
          ),
        );
        return;
      }
      final ruleId = target.startsWith('routing.rule:')
          ? target.substring('routing.rule:'.length)
          : null;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => RoutingScreen(
          subController: subController,
          homeController: homeController,
          focusRuleId: ruleId,
          initialRulesTab:
              target.startsWith('routing.rule:') || target == 'routing.rules',
          focusRouteFinal: target == 'routing.routeFinal',
        ),
      ));
      return;
    }
    if (target.startsWith('subscriptions.entry:')) {
      final homeController = widget.homeController;
      final subController = widget.subController;
      final autoUpdater = widget.autoUpdater;
      if (homeController == null ||
          subController == null ||
          autoUpdater == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(getLocalText.s(
              "Open the journal from the main menu to jump to a server list entry.",
            )),
          ),
        );
        return;
      }
      final entryId = target.substring('subscriptions.entry:'.length);
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SubscriptionsScreen(
          subController: subController,
          homeController: homeController,
          autoUpdater: autoUpdater,
          focusEntryId: entryId,
        ),
      ));
      return;
    }
    if (target.startsWith('dns.')) {
      final homeController = widget.homeController;
      final subController = widget.subController;
      if (homeController == null || subController == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(getLocalText.s(
              "Open DNS navigation from the main screen to jump directly to a DNS setting.",
            )),
          ),
        );
        return;
      }
      final focusServerTag = target.startsWith('dns.server:')
          ? target.substring('dns.server:'.length)
          : null;
      final focusRuleIdentity = target.startsWith('dns.rule:')
          ? target.substring('dns.rule:'.length)
          : null;
      final focusField = switch (target) {
        'dns.strategy' => 'strategy',
        'dns.final' => 'dnsFinal',
        'dns.defaultResolver' => 'defaultResolver',
        'dns.cacheCapacity' => 'cacheCapacity',
        'dns.optimistic' => 'optimistic',
        'dns.storeCache' => 'storeCache',
        _ => null,
      };
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => DnsSettingsScreen(
          subController: subController,
          homeController: homeController,
          focusServerTag: focusServerTag,
          focusField: focusField,
          focusRuleIdentity: focusRuleIdentity,
        ),
      ));
      if (!mounted) return;
      return;
    }
    final tabIndex = target.startsWith('appearance.')
        ? 1
        : target.startsWith('subscriptions.')
            ? 2
            : target.startsWith('diagnostics.')
                ? 3
                : target.startsWith('automation.')
                    ? 4
                    : 0;
    _settingsTabsKey.currentState?.selectTab(tabIndex);

    String? keyName;
    if (target == 'general.usageRegion') keyName = 'usageRegion';
    if (target == 'general.autoStart') keyName = 'autoStart';
    if (target == 'general.autoReload') keyName = 'autoReload';
    if (target == 'general.autoCheckUpdates') keyName = 'autoCheckUpdates';
    if (target == 'general.autoPing') keyName = 'autoPing';
    if (target == 'general.haptic') keyName = 'haptic';
    if (target == 'appearance.allowRotation') keyName = 'allowRotation';
    if (target == 'appearance.theme') keyName = 'theme';
    if (target == 'appearance.language') keyName = 'language';
    if (target == 'appearance.nodeListTwoColumns') keyName = 'nodeListTwoColumns';
    if (target == 'subscriptions.autoUpdate') keyName = 'autoUpdateSubs';
    if (target == 'subscriptions.autoUpdateDisabled') keyName = 'autoUpdateDisabledSubs';
    if (target == 'diagnostics.debugApi') keyName = 'debugApi';
    if (target == 'diagnostics.debugPort') keyName = 'debugPort';
    if (target == 'diagnostics.configLock') keyName = 'configLocked';
    if (target == 'diagnostics.coreLogs') keyName = 'coreLogs';
    if (target == 'diagnostics.autoRecordWifi') keyName = 'autoRecordWifi';
    if (keyName == null) return;

    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!context.mounted) return;
    final itemContext = _journalKeys[keyName]?.currentContext;
    if (itemContext != null) {
      await Scrollable.ensureVisible(
        itemContext,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.25,
      );
    }
  }

  Future<void> _applyJournalAction(
    ChangeJournalEntry entry,
    bool redo,
  ) async {
    final actionKey = entry.actionKey;
    if (actionKey == null) return;
    final targetValue = (redo ? entry.afterValue : entry.beforeValue) == 'true';
    late final bool currentValue;

    if (actionKey == 'auto_start_vpn') {
      currentValue =
          await SettingsStorage.getNativeBool(NativePrefsKeys.autoStart);
      if (currentValue != targetValue) {
        if (!mounted) return;
        setState(() => _autoStart = targetValue);
        await SettingsStorage.setNativeBool(
          NativePrefsKeys.autoStart,
          targetValue,
        );
      }
    } else if (actionKey == 'auto_check_updates') {
      currentValue = await SettingsStorage.getAutoCheckUpdates();
      if (currentValue != targetValue) {
        if (!mounted) return;
        setState(() => _autoCheckUpdates = targetValue);
        await SettingsStorage.setAutoCheckUpdates(targetValue);
      }
    } else {
      return;
    }

    final expectedCurrentValue =
        (redo ? entry.beforeValue : entry.afterValue) == 'true';
    if (currentValue != expectedCurrentValue) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(getLocalText.s("Setting changed since this entry")),
          content: Text(getLocalText.s(
            "Current value: %s. Expected value: %s. Continue anyway?",
            _journalBoolLabel(currentValue),
            _journalBoolLabel(expectedCurrentValue),
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(getLocalText.s("Cancel")),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(getLocalText.s("Continue")),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    await ChangeJournalService.setUndone(entry.id, !redo);
    if (currentValue != targetValue) {
      await ChangeJournalService.record(
        category: 'info',
        title:
            '${getLocalText.s(redo ? "Change redone" : "Change undone")}: ${entry.title}',
        beforeText: _journalBoolLabel(currentValue),
        afterText: _journalBoolLabel(targetValue),
        path: entry.path,
        target: entry.target,
      );
    }
  }

  /// §037 — toggle config_locked_for_debug.
  /// Когда true — `SubscriptionController.generateConfig()` тихо skip'ает
  /// rebuild при UI-действиях, и pinned config.json (например, отправленный
  /// через Debug API `PUT /config`) остаётся в живых.
  Future<void> _toggleConfigLocked(bool locked) async {
    final previous = _configLocked;
    if (previous == locked) return;
    setState(() => _configLocked = locked);
    await SettingsStorage.setConfigLockedForDebug(locked);
    _recordSettingChange(
      title: getLocalText.s("Lock config (debug)"),
      beforeText: _journalBoolLabel(previous),
      afterText: _journalBoolLabel(locked),
      path: '${getLocalText.s("App Settings")} › ${getLocalText.s("Diagnostics")} › ${getLocalText.s("Lock config (debug)")}',
      target: 'diagnostics.configLock',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(locked
            ? getLocalText.s("Config locked. UI actions will not rebuild config.")
            : getLocalText.s("Config unlocked. Next UI action will rebuild from settings.")),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // §031 Debug API — toggle / token / port handlers.
  //
  // Все изменения ведут к [applyDebugApiSettings], который читает SettingsStorage
  // и приводит DebugServer в соответствие (start/stop/rebind).
  // ---------------------------------------------------------------------------

  Future<void> _toggleDebugApi(bool enable) async {
    final previous = _debugEnabled;
    if (previous == enable) return;
    setState(() => _debugEnabled = enable);
    await SettingsStorage.setDebugEnabled(enable);
    _recordSettingChange(
      title: getLocalText.s("Debug API"),
      beforeText: _journalBoolLabel(previous),
      afterText: _journalBoolLabel(enable),
      path: '${getLocalText.s("App Settings")} › ${getLocalText.s("Diagnostics")} › ${getLocalText.s("Debug API")}',
      target: 'diagnostics.debugApi',
    );
    if (enable && _debugToken.isEmpty) {
      final token = DebugServer.generateToken();
      await SettingsStorage.setDebugToken(token);
      if (mounted) setState(() => _debugToken = token);
    }
    // §037 — config lock is a debug-only feature. Disabling Debug API
    // implicitly unlocks: иначе юзер останется с pinned config'ом без
    // UI-способа его разблокировать (lock toggle живёт под Debug API
    // блоком и спрятан, когда API выключен).
    if (!enable && _configLocked) {
      await SettingsStorage.setConfigLockedForDebug(false);
      if (mounted) setState(() => _configLocked = false);
    }
    await applyDebugApiSettings();
  }

  Future<void> _regenerateDebugToken() async {
    final token = DebugServer.generateToken();
    await SettingsStorage.setDebugToken(token);
    if (mounted) setState(() => _debugToken = token);
    await applyDebugApiSettings();
  }

  Future<void> _copyDebugToken() async {
    await Clipboard.setData(ClipboardData(text: _debugToken));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(getLocalText.s("Token copied")),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _applyDebugPort(String raw) async {
    final port = int.tryParse(raw);
    if (port == null ||
        port < SettingsStorage.debugPortMin ||
        port > SettingsStorage.debugPortMax) {
      setState(() => _debugPortError =
          'port must be ${SettingsStorage.debugPortMin}..${SettingsStorage.debugPortMax}');
      return;
    }
    if (port == _debugPort) {
      setState(() => _debugPortError = '');
      return;
    }
    final previousPort = _debugPort;
    setState(() {
      _debugPort = port;
      _debugPortError = '';
    });
    await SettingsStorage.setDebugPort(port);
    _recordSettingChange(
      title: getLocalText.s("Debug API port"),
      beforeText: previousPort.toString(),
      afterText: port.toString(),
      path: '${getLocalText.s("App Settings")} › ${getLocalText.s("Diagnostics")} › ${getLocalText.s("Debug API port")}',
      target: 'diagnostics.debugPort',
    );
    await applyDebugApiSettings();
  }

  /// §043: toggle forwarding sing-box логов в наш AppLog как `DebugSource.core`.
  /// Изменение применяется ТОЛЬКО после полного рестарта процесса — `Libbox.setup`
  /// с флагом `debug` вызывается один раз в `BoxApplication.initialize` (см.
  /// гард `if (initialized) return`). Stop/start VPN не помогает (service-level,
  /// не process-level), нужен force-stop + relaunch. Кнопка «Quit & reopen»
  /// рядом с toggle делает это вызовом `quitApp()` (finishAffinity + killProcess
  /// в Kotlin); юзер сам тапает иконку и получает свежий процесс.
  Future<void> _toggleCoreLogs(bool enable) async {
    final previous = _coreLogsEnabled;
    if (previous == enable) return;
    setState(() => _coreLogsEnabled = enable);
    // §189 — через NativePrefs (JSON-истина + зеркало в native).
    await SettingsStorage.setNativeBool(
        NativePrefsKeys.coreLogsEnabled, enable);
    _recordSettingChange(
      title: getLocalText.s("Forward sing-box logs"),
      beforeText: _journalBoolLabel(previous),
      afterText: _journalBoolLabel(enable),
      path: '${getLocalText.s("App Settings")} › ${getLocalText.s("Diagnostics")} › ${getLocalText.s("Forward sing-box logs")}',
      target: 'diagnostics.coreLogs',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(getLocalText.s("Saved. Force-stop & reopen app to apply.")),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// §043 follow-up: confirm-диалог + `BoxVpnClient.quitApp()`. Process умрёт
  /// через ~250ms; Future от quitApp в норме не ресолвится — поэтому ничего
  /// не делаем после await.
  Future<void> _confirmQuitApp() async {
    final ok = await AppSettingsDialogs.confirmQuitApp(context);
    if (ok != true) return;
    await _vpn.quitApp();
  }

  /// §220 — toggle «Allow rotation». Применяется мгновенно (helper дёргает
  /// SystemChrome.setPreferredOrientations), рестарт не нужен.
  Future<void> _toggleAllowRotation(bool allow) async {
    final previous = _allowRotation;
    if (previous == allow) return;
    setState(() => _allowRotation = allow);
    await SettingsStorage.setAllowRotation(allow);
    _recordSettingChange(
      title: getLocalText.s("Allow rotation"),
      beforeText: _journalBoolLabel(previous),
      afterText: _journalBoolLabel(allow),
      path: '${getLocalText.s("App Settings")} › ${getLocalText.s("Appearance")} › ${getLocalText.s("Allow rotation")}',
      target: 'appearance.allowRotation',
    );
    await applyAllowRotationSetting();
  }

  /// §032 Quick Connect — кнопка «Add tile» в General-табе.
  /// На API 33+ система сама покажет prompt; на более старых — даём
  /// текстовую инструкцию (drag через шторку).
  Future<void> _addQuickSettingsTile() async {
    final result = await _vpn.requestAddTile();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final msg = switch (result) {
      'added' => getLocalText.s("Tile added to Quick Settings."),
      'already' => getLocalText.s("Tile is already in Quick Settings."),
      'dismissed' => getLocalText.s("Add tile dismissed."),
      'unsupported' => getLocalText.s(
          "Your Android version doesn't support an in-app prompt. "
          "Pull down the status bar → edit tiles → drag L×Box to active tiles."),
      'no_activity' =>
        getLocalText.s("Cannot show prompt right now — try again."),
      _ => getLocalText.s(
          "Could not request tile add (%s). "
          "Pull down the status bar → edit tiles → drag L×Box manually.",
          result),
    };
    final duration = (result == 'unsupported' ||
            result.startsWith('error') ||
            result == 'no_activity')
        ? const Duration(seconds: 6)
        : const Duration(seconds: 3);
    messenger.showSnackBar(SnackBar(content: Text(msg), duration: duration));
  }

  /// Tap on the Notifications row in Background → System setup.
  ///
  /// — granted   → open per-app notification settings (toggle categories etc.)
  /// — denied    → try the runtime POST_NOTIFICATIONS prompt; if that returns
  ///               with permission still denied (user picked "Don't allow", or
  ///               had previously selected "Don't ask again"), fall back to
  ///               the App Permissions screen.
  Future<void> _onNotificationsTap() async {
    final granted = await ul.UrlLauncher.checkNotificationPermission();
    if (granted) {
      await _vpn.openNotificationSettings();
      return;
    }
    await ul.UrlLauncher.requestNotificationPermission();
    // Re-check; system dialog is async, but on API 33+ it resolves before the
    // call returns. If "Don't ask again" was previously chosen, the prompt
    // is silently skipped — push the user to Settings instead.
    final after = await ul.UrlLauncher.checkNotificationPermission();
    if (mounted) {
      setState(() => _notificationsEnabled = after);
    }
    if (!after) {
      await ul.UrlLauncher.openAppSettings();
    }
  }

  Future<void> _refreshBatteryStatus() async {
    final battery = await _vpn.isIgnoringBatteryOptimizations();
    final notifications = await _vpn.areNotificationsEnabled();
    final bgLocation = await ul.UrlLauncher.checkBackgroundLocationPermission();
    final nearbyWifi = await ul.UrlLauncher.checkNearbyWifiPermission();
    final wifiLocationIssue = await _readWifiLocationIssue();
    if (mounted) {
      setState(() {
        _batteryWhitelisted = battery;
        _notificationsEnabled = notifications;
        _backgroundLocationGranted = bgLocation;
        _nearbyWifiGranted = nearbyWifi;
        _wifiLocationIssue = wifiLocationIssue;
      });
    }
  }

  /// §051 — tap на «Nearby Wi-Fi» row. Симметрично Notifications row:
  /// - granted → App Permissions screen (юзер видит/может revoke)
  /// - denied  → shared `WifiPermissionDialog` (объяснение + runtime prompt
  ///             + Settings fallback)
  /// State после возврата из Settings рефрешится через
  /// `didChangeAppLifecycleState` → `_refreshBatteryStatus`.
  Future<void> _onNearbyWifiTap() async {
    final granted = await ul.UrlLauncher.checkNearbyWifiPermission();
    if (granted) {
      await ul.UrlLauncher.openAppSettings();
      return;
    }
    if (!mounted) return;
    await WifiPermissionDialog.show(
      context,
      missing: const ['android.permission.NEARBY_WIFI_DEVICES'],
    );
    final after = await ul.UrlLauncher.checkNearbyWifiPermission();
    if (mounted) setState(() => _nearbyWifiGranted = after);
  }

  /// §567 — причина, по которой SSID не читается при выданных
  /// разрешениях строки «Location (background)»: `fine_location_missing`
  /// (FINE в списке отсутствующих) или `location_disabled`. Иначе null.
  Future<String?> _readWifiLocationIssue() async {
    final r = await ul.UrlLauncher.getCurrentWifiInfo();
    if (r is! ul.WifiInfoError) return null;
    if (r.missing.contains('android.permission.ACCESS_FINE_LOCATION')) {
      return 'fine_location_missing';
    }
    return r.reason == 'location_disabled' ? 'location_disabled' : null;
  }

  /// §051 — tap на «Location (background)» row.
  /// - granted → App Permissions screen
  /// - denied  → shared `WifiPermissionDialog` (для BACKGROUND_LOCATION
  ///             runtime prompt бесполезен на API 30+, dialog покажет
  ///             только «Open Settings»).
  Future<void> _onBackgroundLocationTap() async {
    final granted =
        await ul.UrlLauncher.checkBackgroundLocationPermission();
    if (granted) {
      // §567 — BACKGROUND есть, но SSID всё равно не читается: ведём туда,
      // где чинится конкретная причина.
      switch (await _readWifiLocationIssue()) {
        case 'location_disabled':
          await ul.UrlLauncher.openLocationSettings();
        case 'fine_location_missing':
          if (!mounted) return;
          await WifiPermissionDialog.show(
            context,
            missing: const ['android.permission.ACCESS_FINE_LOCATION'],
          );
        default:
          await ul.UrlLauncher.openAppSettings();
      }
      return;
    }
    if (!mounted) return;
    await WifiPermissionDialog.show(
      context,
      missing: const ['android.permission.ACCESS_BACKGROUND_LOCATION'],
    );
    final after =
        await ul.UrlLauncher.checkBackgroundLocationPermission();
    if (mounted) setState(() => _backgroundLocationGranted = after);
  }

  /// Preset-инструкции перед переходом в system App info — OEM'ы прячут
  /// нужные тоглы в разных местах, юзер без подсказки теряется.
  Future<void> _openAppInfoWithHint() async {
    final proceed = await AppSettingsDialogs.openAppInfoHint(context);
    if (proceed == true) await _vpn.openAppDetailsSettings();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      // §279 — слушаем и LocaleController: этот экран показан как pushed route,
      // rebuild корневого MaterialApp его не перестраивает (Navigator держит
      // route поверх). Без подписки смена языка не двигала radio-галку picker'а
      // и не перерисовывала строки самого экрана настроек.
      animation: Listenable.merge([themeNotifier, LocaleController.I]),
      builder: (context, _) {
        return SettingsTabsScreen(
          key: _settingsTabsKey,
          overlayTitle: getLocalText.s("App Settings"),
          initialIndex: widget.initialTab.clamp(0, 5),
          tabs: [
            SettingsTabSpec(getLocalText.s("General"), Icons.tune),
            SettingsTabSpec(getLocalText.s("Appearance"), Icons.palette_outlined),
            SettingsTabSpec(getLocalText.s("Subscriptions"), Icons.rss_feed),
            SettingsTabSpec(
              getLocalText.s("Diagnostics"),
              Icons.monitor_heart_outlined,
            ),
            // Automation was added as a separate settings tab; keep it in both
            // the browser bar and the tab-tile overlay.
            SettingsTabSpec(getLocalText.s("Automation"), Icons.bolt),
            SettingsTabSpec(getLocalText.s("History"), Icons.history),
          ],
          pages: [
            _buildGeneralTab(context),
            _buildAppearanceTab(context),
            _buildSubscriptionsTab(context),
            _buildDiagnosticsTab(context),
            AutomationTab(padding: _tabPadding(context)),
            Builder(
              builder: (journalContext) => ChangeJournalTab(
                padding: _tabPadding(journalContext),
                onNavigate: (entry) => unawaited(
                  _navigateToJournalEntry(journalContext, entry),
                ),
                onApplyAction: _applyJournalAction,
              ),
            ),
          ],
        );
      },
    );
  }

  EdgeInsets _tabPadding(BuildContext context) => EdgeInsets.fromLTRB(
      12, 12, 12, MediaQuery.of(context).padding.bottom + 24);

  // ─── §118 subscription fetch identity (UA override + HWID + meta) ──────

  Future<String?> _editIdentityText({
    required String title,
    required String initial,
    String? hint,
    bool monospace = false,
  }) async {
    final ctl = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLines: null,
          style: monospace
              ? const TextStyle(fontFamily: 'monospace', fontSize: 13)
              : null,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(getLocalText.s("Cancel")),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctl.text),
            child: Text(getLocalText.s("Save")),
          ),
        ],
      ),
    );
    ctl.dispose();
    return result;
  }

  Future<void> _editUserAgent() async {
    // §610 — общий диалог с пресетами популярных клиентов.
    final trimmed = await showUserAgentDialog(context, initial: _userAgent);
    if (trimmed == null || !mounted) return;
    setState(() => _userAgent = trimmed);
    await SettingsStorage.setVar(SubscriptionIdentity.varUserAgent, trimmed);
    SubscriptionIdentity.apply(userAgentOverride: trimmed);
  }

  void _setSendHwid(bool val) {
    // §118 — лениво генерим UUID при первом включении (решение №2/№3).
    if (val && _hwid.isEmpty) {
      _hwid = generateUuidV4();
      unawaited(SettingsStorage.setVar(SubscriptionIdentity.varHwid, _hwid));
      SubscriptionIdentity.apply(hwid: _hwid);
    }
    setState(() => _sendHwid = val);
    unawaited(SettingsStorage.setVar(
        SubscriptionIdentity.varSendHwid, val.toString()));
    SubscriptionIdentity.apply(sendHwid: val);
  }

  Future<void> _editHwid() async {
    final v = await _editIdentityText(
      title: 'HWID',
      initial: _hwid,
      monospace: true,
    );
    if (v == null) return;
    final trimmed = v.trim();
    setState(() => _hwid = trimmed);
    await SettingsStorage.setVar(SubscriptionIdentity.varHwid, trimmed);
    SubscriptionIdentity.apply(hwid: trimmed);
  }

  void _regenerateHwid() {
    final v = generateUuidV4();
    setState(() => _hwid = v);
    unawaited(SettingsStorage.setVar(SubscriptionIdentity.varHwid, v));
    SubscriptionIdentity.apply(hwid: v);
  }

  Future<void> _editDeviceOs() async {
    final v = await _editIdentityText(
      title: 'x-device-os',
      initial: _deviceOs,
      hint: SubscriptionIdentity.deviceOsDefault,
    );
    if (v == null) return;
    final t = v.trim();
    setState(() => _deviceOs = t);
    await SettingsStorage.setVar(SubscriptionIdentity.varDeviceOs, t);
    SubscriptionIdentity.apply(deviceOsOverride: t);
  }

  Future<void> _editVerOs() async {
    final v = await _editIdentityText(
      title: 'x-ver-os',
      initial: _verOs,
      hint: SubscriptionIdentity.osVersion,
    );
    if (v == null) return;
    final t = v.trim();
    setState(() => _verOs = t);
    await SettingsStorage.setVar(SubscriptionIdentity.varVerOs, t);
    SubscriptionIdentity.apply(verOsOverride: t);
  }

  Future<void> _editDeviceModel() async {
    final v = await _editIdentityText(
      title: 'x-device-model',
      initial: _deviceModel,
      hint: SubscriptionIdentity.deviceModel,
    );
    if (v == null) return;
    final t = v.trim();
    setState(() => _deviceModel = t);
    await SettingsStorage.setVar(SubscriptionIdentity.varDeviceModel, t);
    SubscriptionIdentity.apply(deviceModelOverride: t);
  }

  Widget _buildSubscriptionsTab(BuildContext context) {
    return SubscriptionsTab(
      loaded: _loaded,
      padding: _tabPadding(context),
      journalKeys: _journalKeys,
      autoUpdateSubs: _autoUpdateSubs,
      onAutoUpdateSubsChanged: (val) {
        final previous = _autoUpdateSubs;
        if (previous == val) return;
        setState(() => _autoUpdateSubs = val);
        unawaited(SettingsStorage.setAutoUpdateSubs(val));
        _recordSettingChange(
          title: getLocalText.s("Auto-update subscriptions"),
          beforeText: _journalBoolLabel(previous),
          afterText: _journalBoolLabel(val),
          path: '${getLocalText.s("App Settings")} › ${getLocalText.s("Subscriptions")} › ${getLocalText.s("Auto-update subscriptions")}',
          target: 'subscriptions.autoUpdate',
        );
      },
      autoUpdateDisabledSubs: _autoUpdateDisabledSubs,
      onAutoUpdateDisabledSubsChanged: (val) {
        final previous = _autoUpdateDisabledSubs;
        if (previous == val) return;
        setState(() => _autoUpdateDisabledSubs = val);
        unawaited(SettingsStorage.setAutoUpdateDisabledSubs(val));
        _recordSettingChange(
          title: getLocalText.s("Update disabled subscriptions"),
          beforeText: _journalBoolLabel(previous),
          afterText: _journalBoolLabel(val),
          path: '${getLocalText.s("App Settings")} › ${getLocalText.s("Subscriptions")} › ${getLocalText.s("Update disabled subscriptions")}',
          target: 'subscriptions.autoUpdateDisabled',
        );
      },
      userAgent: _userAgent,
      defaultUserAgent: resolveSubscriptionUserAgent(),
      onEditUserAgent: () => unawaited(_editUserAgent()),
      sendHwid: _sendHwid,
      onSendHwidChanged: _setSendHwid,
      hwid: _hwid,
      deviceOs: SubscriptionIdentity.effectiveDeviceOs,
      verOs: SubscriptionIdentity.effectiveVerOs,
      deviceModel: SubscriptionIdentity.effectiveDeviceModel,
      onEditHwid: () => unawaited(_editHwid()),
      onRegenerateHwid: _regenerateHwid,
      onEditDeviceOs: () => unawaited(_editDeviceOs()),
      onEditVerOs: () => unawaited(_editVerOs()),
      onEditDeviceModel: () => unawaited(_editDeviceModel()),
    );
  }

  Widget _buildAppearanceTab(BuildContext context) {
    return AppearanceTab(
      loaded: _loaded,
      allowRotation: _allowRotation,
      nodeListTwoColumns: _nodeListTwoColumns,
      padding: _tabPadding(context),
      journalKeys: _journalKeys,
      onAllowRotationChanged: (val) => unawaited(_toggleAllowRotation(val)),
      onNodeListTwoColumnsChanged: (val) {
        final previous = _nodeListTwoColumns;
        if (previous == val) return;
        setState(() => _nodeListTwoColumns = val);
        unawaited(SettingsStorage.setNodeListTwoColumns(val));
        _recordSettingChange(
          title: getLocalText.s("Two columns on wide screens"),
          beforeText: _journalBoolLabel(previous),
          afterText: _journalBoolLabel(val),
          path: '${getLocalText.s("App Settings")} › ${getLocalText.s("Appearance")} › ${getLocalText.s("Two columns on wide screens")}',
          target: 'appearance.nodeListTwoColumns',
        );
      },
    );
  }

  Widget _buildGeneralTab(BuildContext context) {
    return GeneralTab(
      loaded: _loaded,
      autoStart: _autoStart,
      autoCheckUpdates: _autoCheckUpdates,
      autoPing: _autoPing,
      haptic: _haptic,
      autoReloadOnChange: _autoReloadOnChange, // §338
      padding: _tabPadding(context),
      journalKeys: _journalKeys,
      onAutoStartChanged: (val) {
        final previous = _autoStart;
        if (previous == val) return;
        setState(() => _autoStart = val);
        // §189 — через NativePrefs (JSON-истина + зеркало в native).
        unawaited(
            SettingsStorage.setNativeBool(NativePrefsKeys.autoStart, val));
        _recordSettingChange(
          title: getLocalText.s("Auto-start on boot"),
          beforeText: _journalBoolLabel(previous),
          afterText: _journalBoolLabel(val),
          path: '${getLocalText.s("App Settings")} › ${getLocalText.s("General")} › ${getLocalText.s("Auto-start on boot")}',
          target: 'general.autoStart',
          actionKey: 'auto_start_vpn',
          beforeValue: previous.toString(),
          afterValue: val.toString(),
        );
      },
      // §338 — автоприменение изменений конфига (любой источник, не подписки).
      onAutoReloadOnChangeChanged: (val) {
        final previous = _autoReloadOnChange;
        if (previous == val) return;
        setState(() => _autoReloadOnChange = val);
        unawaited(SettingsStorage.setAutoReloadOnChange(val));
        _recordSettingChange(
          title: getLocalText.s("Auto-restart VPN on settings change"),
          beforeText: _journalBoolLabel(previous),
          afterText: _journalBoolLabel(val),
          path: '${getLocalText.s("App Settings")} › ${getLocalText.s("General")} › ${getLocalText.s("Auto-restart VPN on settings change")}',
          target: 'general.autoReload',
        );
      },
      onAutoCheckUpdatesChanged: (val) {
        final previous = _autoCheckUpdates;
        if (previous == val) return;
        setState(() => _autoCheckUpdates = val);
        unawaited(SettingsStorage.setAutoCheckUpdates(val));
        _recordSettingChange(
          title: getLocalText.s("Check for updates on launch"),
          beforeText: _journalBoolLabel(previous),
          afterText: _journalBoolLabel(val),
          path: '${getLocalText.s("App Settings")} › ${getLocalText.s("General")} › ${getLocalText.s("Check for updates on launch")}',
          target: 'general.autoCheckUpdates',
          actionKey: 'auto_check_updates',
          beforeValue: previous.toString(),
          afterValue: val.toString(),
        );
      },
      onAutoPingChanged: (val) {
        final previous = _autoPing;
        if (previous == val) return;
        setState(() => _autoPing = val);
        unawaited(SettingsStorage.setVar(
            'auto_ping_on_start', val.toString()));
        _recordSettingChange(
          title: getLocalText.s("Auto-ping after connect"),
          beforeText: _journalBoolLabel(previous),
          afterText: _journalBoolLabel(val),
          path: '${getLocalText.s("App Settings")} › ${getLocalText.s("General")} › ${getLocalText.s("Auto-ping after connect")}',
          target: 'general.autoPing',
        );
      },
      onHapticChanged: (val) {
        final previous = _haptic;
        if (previous == val) return;
        setState(() => _haptic = val);
        HapticService.I.enabled = val;
        unawaited(SettingsStorage.setVar(HapticService.prefsKey, val.toString()));
        _recordSettingChange(
          title: getLocalText.s("Haptic feedback"),
          beforeText: _journalBoolLabel(previous),
          afterText: _journalBoolLabel(val),
          path: '${getLocalText.s("App Settings")} › ${getLocalText.s("General")} › ${getLocalText.s("Haptic feedback")}',
          target: 'general.haptic',
        );
        if (val) {
          HapticService.I.onConnectTap();
        }
      },
      onAddQuickSettingsTile: () => unawaited(_addQuickSettingsTile()),
      onOpenBackup: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BackupScreen()),
      ),
      region: _region,
      detectedRegion: _detectedRegion,
      onEditRegion: () => unawaited(_editRegion()),
    );
  }

  /// §425 — выбор региона использования: auto / none / известные регионы
  /// (сегодня — ключи `loc` пула WARP) / произвольный код страны.
  Future<void> _editRegion() async {
    const other = '__other__';
    final known = await WarpEndpointPicker.availableRegions();
    if (!mounted) return;
    final options = [
      SettingsStorage.regionAuto,
      SettingsStorage.regionNone,
      ...known,
      // Явно выбранный код вне известного списка — показать, не терять.
      if (_region != SettingsStorage.regionAuto &&
          _region != SettingsStorage.regionNone &&
          !known.contains(_region))
        _region,
    ];
    var picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(getLocalText.s("Usage region")),
        children: [
          for (final o in options)
            RadioListTile<String>(
              value: o,
              // ignore: deprecated_member_use
              groupValue: _region,
              title: Text(GeneralTab.regionLabel(o, _detectedRegion)),
              // ignore: deprecated_member_use
              onChanged: (v) => Navigator.of(ctx).pop(v),
            ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(getLocalText.s("Other country code…")),
            onTap: () => Navigator.of(ctx).pop(other),
          ),
        ],
      ),
    );
    if (picked == other && mounted) {
      final ctl = TextEditingController(
          text: options.contains(_region) ? '' : _region.toUpperCase());
      picked = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(getLocalText.s("Country code (2 letters)")),
          content: TextField(
            controller: ctl,
            autofocus: true,
            maxLength: 2,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'IL'), // l10n-exempt
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(getLocalText.s("Cancel")),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(ctl.text),
              child: Text(getLocalText.s("Save")),
            ),
          ],
        ),
      );
      if (picked != null &&
          SettingsStorage.normalizeRegion(picked) ==
              SettingsStorage.regionAuto) {
        picked = null; // мусор вместо кода — не сохраняем
      }
    }
    if (picked == null || !mounted) return;
    final previous = _region;
    final norm = SettingsStorage.normalizeRegion(picked);
    if (previous == norm) return;
    setState(() => _region = norm);
    await SettingsStorage.setRegion(norm);
    _recordSettingChange(
      title: getLocalText.s("Usage region"),
      beforeText: GeneralTab.regionLabel(previous, _detectedRegion),
      afterText: GeneralTab.regionLabel(norm, _detectedRegion),
      path: '${getLocalText.s("App Settings")} › ${getLocalText.s("General")} › ${getLocalText.s("Usage region")}',
      target: 'general.usageRegion',
    );
  }

  Widget _buildDiagnosticsTab(BuildContext context) {
    return DiagnosticsTab(
      loaded: _loaded,
      padding: _tabPadding(context),
      batteryWhitelisted: _batteryWhitelisted,
      notificationsEnabled: _notificationsEnabled,
      backgroundLocationGranted: _backgroundLocationGranted,
      nearbyWifiGranted: _nearbyWifiGranted,
      wifiLocationIssue: _wifiLocationIssue,
      debugEnabled: _debugEnabled,
      debugPort: _debugPort,
      debugToken: _debugToken,
      debugPortError: _debugPortError,
      debugPortCtl: _debugPortCtl,
      configLocked: _configLocked,
      coreLogsEnabled: _coreLogsEnabled,
      coreLogsHighlighted: _coreLogsHighlighted,
      coreLogsTileKey: _coreLogsTileKey,
      journalKeys: _journalKeys,
      autoRecordWifi: _autoRecordWifi,
      onBatteryTap: () async {
        await _vpn.openBatteryOptimizationSettings();
      },
      onNotificationsTap: _onNotificationsTap,
      onBackgroundLocationTap: _onBackgroundLocationTap,
      onNearbyWifiTap: _onNearbyWifiTap,
      onAppInfoTap: _openAppInfoWithHint,
      onDebugApiChanged: (val) => unawaited(_toggleDebugApi(val)),
      onCopyDebugToken: _copyDebugToken,
      onRegenerateDebugToken: () => unawaited(_regenerateDebugToken()),
      onDebugPortSubmitted: (v) => unawaited(_applyDebugPort(v)),
      onConfigLockedChanged: (val) => unawaited(_toggleConfigLocked(val)),
      onCoreLogsChanged: (val) => unawaited(_toggleCoreLogs(val)),
      onQuitApp: () => unawaited(_confirmQuitApp()),
      onAutoRecordWifiChanged: (val) => unawaited(_toggleAutoRecordWifi(val)),
    );
  }

  /// §051 Phase 3 — toggle для auto-record. Сразу sync'ит state в native
  /// observer (start/stop NetworkCallback). Существующая история не
  /// чистится при OFF — это user data, явный поход в Pick saved.
  Future<void> _toggleAutoRecordWifi(bool enabled) async {
    final previous = _autoRecordWifi;
    if (previous == enabled) return;
    setState(() => _autoRecordWifi = enabled);
    await SettingsStorage.setAutoRecordWifi(enabled);
    _recordSettingChange(
      title: getLocalText.s("Auto-record visited Wi-Fi networks"),
      beforeText: _journalBoolLabel(previous),
      afterText: _journalBoolLabel(enabled),
      path: '${getLocalText.s("App Settings")} › ${getLocalText.s("Diagnostics")} › ${getLocalText.s("Auto-record visited Wi-Fi networks")}',
      target: 'diagnostics.autoRecordWifi',
    );
    await WifiHistoryListener.I.setEnabled(enabled);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(enabled
            ? getLocalText.s("Auto-record on. Networks added after 5 min of stay.")
            : getLocalText.s("Auto-record off. Existing history kept.")),
      ),
    );
  }
}
