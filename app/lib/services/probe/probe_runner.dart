import 'dart:async';

import '../../models/node_spec.dart';
import '../../models/tunnel_status.dart';
import '../../vpn/box_vpn_client.dart';
import '../../vpn/cc_channel.dart';
import '../app_log.dart';
import 'probe_config.dart';
import 'probe_lifecycle.dart';

/// §236 — маркер, что тест не запустился из-за активного VPN. UI ловит его
/// (равенством) и показывает попап-гейт с кнопкой Stop VPN вместо ошибки.
/// Не человеко-читаемый текст: наружу как сообщение не идёт.
const kProbeVpnRunning = '__vpn_running__';

/// §236 — вердикт теста одного члена папки.
enum ProbeStatus {
  /// Тест ещё не дошёл (или отменён до старта).
  pending,

  /// Успех: [ProbeResult.delayMs] валиден (0мс — тоже успех, Variant B).
  ok,

  /// Ядро вернуло ошибку/таймаут — нода недоступна.
  failed,

  /// raw члена не парсится (нода битая) — тесту не подлежит.
  broken,

  /// emit ноды упал — конфиг из неё не собрать.
  invalid,

  /// §336 — узел-группа (§322): своего замера нет, члены тестируются
  /// поштучно. Не ошибка — нейтральный вердикт.
  group,
}

class ProbeResult {
  const ProbeResult(this.status, {this.delayMs = 0, this.message = ''});

  final ProbeStatus status;
  final int delayMs;
  final String message;
}

/// §236/§296 — прогон теста по списку нод (общий для всей подсистемы
/// ServerList: папки/подписки/серверы).
///
/// В обычном режиме (VPN выключен) используется отдельная headless probe-сессия.
/// Если VPN уже работает и вызывающий передал [liveTags], тест идёт через
/// уже запущенный pingClient боевого ядра: Android-слой защищает исходящие
/// сокеты этого ядра от собственного TUN, поэтому VPN пользователю не мешает.
/// Это сохраняет тестирование активных нод без остановки туннеля. Ноды, которых
/// нет в текущем конфиге (например, отключённые), в live-режиме не тестируются.
class ProbeRunner {
  ProbeRunner({CcChannel? cc}) : _cc = cc ?? CcChannel.instance;

  final CcChannel _cc;
  bool _cancelled = false;

  /// Конкурентность пула: ядро меряет по одной ноде synchronous+stateless
  /// (SPEC 014), мультиплекс на одном клиенте — как mass-ping §209.
  static const _concurrency = 6;

  void cancel() {
    _cancelled = true;
    // §175 — в live-режиме это рвёт in-flight urlTestOutbound через отдельный
    // pingClient, не затрагивая status/screen/profiler-клиенты.
    unawaited(_cc.cancelPing());
  }

  /// Прогоняет тест по всем [nodes] (null-слот → вердикт 'broken', индекс
  /// сохраняется). Результаты отдаются по мере готовности в [onResult]
  /// (index, result). Возвращает '' или текст фатальной ошибки (не пер-нодной).
  ///
  /// §296 — вызывающий приводит свой домен к `List<NodeSpec?>`: папка передаёт
  /// `folder.members.map((m)=>m.node)` (nullable, unfiltered — НЕ `folder.nodes`,
  /// тот отфильтрован); подписка/сервер — `list.nodes` (disabled §283 → null).
  Future<String> run(
    List<NodeSpec?> nodes, {
    required String url,
    required int timeoutMs,
    required void Function(int index, ProbeResult result) onResult,
    /// Итоговый tag ноды в ЖИВОМ конфиге. Если список передан, а VPN включён,
    /// runner использует именно боевое ядро вместо ProbeSession.
    List<String?>? liveTags,
  }) async {
    _cancelled = false;
    // §286 — регистрируем отмену в общем реестре: stop VPN / смерть туннеля /
    // сворадивание дёрнут ProbeLifecycle.haltAll() → cancel() здесь, и sweep
    // прекратится, даже если экран деталей папки не в фокусе. Снимаем в finally.
    final canceller = ProbeLifecycle.I.register(cancel);
    try {
      if (liveTags != null) {
        final vpnUp = (await BoxVpnClient().getVpnStatus()) !=
            TunnelStatus.disconnected;
        if (vpnUp) {
          return await _runLive(
            nodes,
            liveTags: liveTags,
            url: url,
            timeoutMs: timeoutMs,
            onResult: onResult,
          );
        }
      }

      // §518 — конфигов может быть несколько: naive-узлы гейтятся по
      // kProbeMaxNaivePerConfig (каждый поднимает Chromium-движок, десяток в
      // одном конфиге = OOM всего процесса). Батчи прогоняются
      // ПОСЛЕДОВАТЕЛЬНО, каждый своей probe-сессией: `ProbeSession.start`
      // поверх живой сессии — рестарт, так что движки предыдущего батча
      // освобождаются до старта следующего. Без naive батч один, и прогон
      // дословно как до §518.
      final batches = buildProbeBatches(nodes);

      // Битые/несобираемые/группы — вердикт сразу, без ядра. Вердикты лежат
      // в первом батче (§518 `_assemble`), покрывают весь список целиком.
      final broken = batches.isEmpty
          ? buildProbeConfig(nodes).brokenByIndex
          : batches.first.brokenByIndex;
      broken.forEach((i, why) {
        onResult(
            i,
            ProbeResult(
              switch (why) {
                'broken' => ProbeStatus.broken,
                'group' => ProbeStatus.group, // §336
                _ => ProbeStatus.invalid,
              },
              message: why,
            ));
      });
      if (batches.isEmpty) return '';

      for (final cfg in batches) {
        if (_cancelled) return '';
        if (cfg.configJson == null) continue;
        final err = await _cc.probeStart(cfg.configJson!);
        if (err.isNotEmpty) {
          // VPN активен → probe-сессию не поднять. UI гейтит тест ещё до run()
          // (getVpnStatus), но между проверкой и probeStart VPN мог стартовать —
          // ловим здесь маркером, не боевой веткой.
          if (_looksLikeVpnRunning(err)) return kProbeVpnRunning;
          AppLog.I.warning('Probe session failed to start: $err');
          return err;
        }
        try {
          await _runPool(
            cfg.tagByIndex,
            test: (tag) =>
                _cc.probeUrlTest(tag, link: url, timeoutMs: timeoutMs),
            onResult: onResult,
          );
        } finally {
          // Сессию гасим ПОСЛЕ каждого батча, а не в конце прогона: иначе
          // движки naive-узлов предыдущего батча жили бы до конца sweep'а и
          // гейт не давал бы ничего.
          await _cc.probeStop();
        }
      }
      return '';
    } finally {
      ProbeLifecycle.I.deregister(canceller);
    }
  }

  static bool _looksLikeVpnRunning(String err) =>
      err.toLowerCase().contains('vpn is running');

  /// Experiment — live-режим: не создаём второй CommandServer. Используем уже
  /// работающий pingClient боевого ядра; его transport sockets идут через
  /// PlatformInterface.autoDetectInterfaceControl -> VpnService.protect().
  Future<String> _runLive(
    List<NodeSpec?> nodes, {
    required List<String?> liveTags,
    required String url,
    required int timeoutMs,
    required void Function(int index, ProbeResult result) onResult,
  }) async {
    if (liveTags.length != nodes.length) {
      return 'live ping: tag map size mismatch';
    }

    final tags = <int, String>{};
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node == null) {
        onResult(i, const ProbeResult(ProbeStatus.broken, message: 'broken'));
        continue;
      }
      if (node is AutoSelectSpec) {
        onResult(i, const ProbeResult(ProbeStatus.group, message: 'group'));
        continue;
      }
      final tag = liveTags[i];
      if (tag == null || tag.isEmpty) {
        // Нода есть на экране, но в текущий live-конфиг не попала (например,
        // отключена). Не выдаём ей ложный timeout — отдельный нейтральный
        // статус отсутствия live-tag здесь не предусмотрен контрактом,
        // поэтому считаем её failed с явной причиной.
        onResult(
          i,
          const ProbeResult(
            ProbeStatus.failed,
            message: 'not in active config',
          ),
        );
        continue;
      }
      tags[i] = tag;
    }

    if (tags.isEmpty) return '';
    await _runPool(
      tags,
      test: (tag) => _cc.urlTestOutbound(
        tag,
        link: url,
        timeoutMs: timeoutMs,
      ),
      onResult: onResult,
    );
    return '';
  }

  /// Находит итоговый display-tag текущей сборки для конкретного объекта ноды.
  /// [liveTagMap] — controller.lastEmittedTagMap: единственный источник истины
  /// для реального тега в рабочем конфиге.
  static String? liveTagForNode(
    NodeSpec? node, {
    required Map<String, NodeSpec> liveTagMap,
    required String fallbackTag,
  }) {
    if (node == null) return null;
    for (final entry in liveTagMap.entries) {
      if (identical(entry.value, node)) return entry.key;
    }
    final mapped = liveTagMap[fallbackTag];
    if (mapped != null && identical(mapped, node)) return fallbackTag;
    return null;
  }

  Future<void> _runPool(
    Map<int, String> tags, {
    required Future<CcDelayResult> Function(String tag) test,
    required void Function(int index, ProbeResult result) onResult,
  }) async {
    final queue = tags.entries.toList();
    var next = 0;
    Future<void> worker() async {
      while (true) {
        if (_cancelled) return;
        if (next >= queue.length) return;
        final entry = queue[next++];
        final r = await test(entry.value);
        if (_cancelled) return;
        onResult(
          entry.key,
          r.ok
              ? ProbeResult(ProbeStatus.ok, delayMs: r.delay)
              : ProbeResult(ProbeStatus.failed, message: r.error),
        );
      }
    }

    await Future.wait([
      for (var w = 0; w < _concurrency; w++) worker(),
    ]);
  }
}

/// §236 — пороги цветовой шкалы (мс). Дефолты — из запроса NeoCat (4PDA).
class ProbeThresholds {
  const ProbeThresholds({
    this.greenMs = 250,
    this.yellowMs = 500,
    this.orangeMs = 700,
  });

  /// §296 — единственный источник дефолтов (был триплет 250/500/700,
  /// скопированный в folder_detail 3×).
  static const defaults = ProbeThresholds();

  final int greenMs;
  final int yellowMs;
  final int orangeMs;

  /// 0=зелёный, 1=жёлтый, 2=оранжевый, 3=красный.
  int bandOf(int delayMs) {
    if (delayMs <= greenMs) return 0;
    if (delayMs <= yellowMs) return 1;
    if (delayMs <= orangeMs) return 2;
    return 3;
  }
}
