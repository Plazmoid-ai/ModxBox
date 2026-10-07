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
/// Если VPN уже работает и все тестируемые ноды присутствуют в действующем
/// конфиге, тест идёт через уже запущенный pingClient боевого ядра: Android-слой
/// защищает исходящие сокеты этого ядра от собственного TUN, поэтому VPN
/// пользователю не мешает. Если часть нод отсутствует в текущем конфиге
/// (например, выключенная подписка), runner временно останавливает VPN и
/// выполняет полный headless probe, затем восстанавливает VPN.
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
    /// Итоговый tag ноды в ЖИВОМ конфиге.
    ///
    /// При активном VPN:
    /// - если все реальные ноды имеют live-tag → тест идёт через боевое ядро;
    /// - если хотя бы одна реальная нода отсутствует в активном конфиге →
    ///   VPN временно останавливается, выполняется полный headless probe,
    ///   затем VPN автоматически восстанавливается.
    List<String?>? liveTags,
  }) async {
    _cancelled = false;
    // §286 — регистрируем отмену в общем реестре: stop VPN / смерть туннеля /
    // сворачивание дёрнут ProbeLifecycle.haltAll() → cancel() здесь, и sweep
    // прекратится, даже если экран деталей папки не в фокусе. Снимаем в finally.
    final canceller = ProbeLifecycle.I.register(cancel);
    try {
      if (liveTags != null) {
        final vpn = BoxVpnClient();
        final status = await vpn.getVpnStatus();
        final vpnUp = status != TunnelStatus.disconnected &&
            status != TunnelStatus.error &&
            status != TunnelStatus.revoked &&
            status != TunnelStatus.unknown;

        if (vpnUp) {
          if (_requiresTemporaryVpnStop(nodes, liveTags)) {
            return await _runWithTemporaryVpnStop(
              vpn,
              nodes,
              canceller: canceller,
              url: url,
              timeoutMs: timeoutMs,
              onResult: onResult,
            );
          }
          return await _runLive(
            nodes,
            liveTags: liveTags,
            url: url,
            timeoutMs: timeoutMs,
            onResult: onResult,
          );
        }
      }

      return await _runHeadless(
        nodes,
        url: url,
        timeoutMs: timeoutMs,
        onResult: onResult,
      );
    } finally {
      ProbeLifecycle.I.deregister(canceller);
    }
  }

  /// При активном VPN проверяем, есть ли среди реальных нод те, которых нет
  /// в действующем конфиге. Группы и уже сломанные null-слоты самостоятельного
  /// подключения не требуют.
  static bool _requiresTemporaryVpnStop(
    List<NodeSpec?> nodes,
    List<String?> liveTags,
  ) {
    if (liveTags.length != nodes.length) return false;
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node == null || node is AutoSelectSpec) continue;
      final tag = liveTags[i];
      if (tag == null || tag.isEmpty) return true;
    }
    return false;
  }

  /// Тест полного списка через обычную headless probe-сессию.
  Future<String> _runHeadless(
    List<NodeSpec?> nodes, {
    required String url,
    required int timeoutMs,
    required void Function(int index, ProbeResult result) onResult,
  }) async {
    // §518 — конфигов может быть несколько: naive-узлы гейтятся по
    // kProbeMaxNaivePerConfig (каждый поднимает Chromium-движок, десяток в
    // одном конфиге = OOM всего процесса). Батчи прогоняются
    // ПОСЛЕДОВАТЕЛЬНО, каждый своей probe-сессией: ProbeSession.start
    // поверх живой сессии — рестарт, так что движки предыдущего батча
    // освобождаются до старта следующего. Без naive батч один, и прогон
    // дословно как до §518.
    final batches = buildProbeBatches(nodes);

    // Битые/несобираемые/группы — вердикт сразу, без ядра. Вердикты лежат
    // в первом батче (§518 _assemble), покрывают весь список целиком.
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
        // VPN активен → probe-сессию не поднять. В штатном гибридном режиме
        // это означает, что VPN успел подняться во время временной остановки.
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
        // Сессию гасим ПОСЛЕ каждого батча, чтобы naive-движки предыдущего
        // батча не жили до конца sweep'а.
        await _cc.probeStop();
      }
    }
    return '';
  }

  /// Активный VPN нужен пользователю для обычной работы, но часть тестируемых
  /// нод отсутствует в его конфиге. В этом случае временно останавливаем
  /// собственный VPN, запускаем тот же полный probe, а затем восстанавливаем
  /// VPN в исходное состояние.
  Future<String> _runWithTemporaryVpnStop(
    BoxVpnClient vpn,
    List<NodeSpec?> nodes, {
    required void Function() canceller,
    required String url,
    required int timeoutMs,
    required void Function(int index, ProbeResult result) onResult,
  }) async {
    var result = '';
    var restoreError = '';
    var stopSucceeded = false;
    var lifecycleReRegistered = false;

    // Intentional VPN stop would normally trigger HomeController.haltAllProbing().
    // Temporarily detach this runner; user cancellation still calls [cancel()]
    // directly through the screen, and we re-register before the actual probe.
    ProbeLifecycle.I.deregister(canceller);

    try {
      final stopOk = await vpn.stopVPN();
      if (!stopOk) {
        AppLog.I.warning('Probe: could not temporarily stop VPN');
        return 'Could not temporarily stop VPN for full server test';
      }
      stopSucceeded = true;

      // stopVPN() по контракту блокируется до Stopped. Всё же проверяем
      // фактическое состояние перед запуском второго CommandServer.
      var disconnected = false;
      for (var attempt = 0; attempt < 20; attempt++) {
        if ((await vpn.getVpnStatus()) == TunnelStatus.disconnected) {
          disconnected = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      if (!disconnected) {
        AppLog.I.warning('Probe: VPN did not reach disconnected state');
        result = 'VPN did not stop completely for server test';
      } else {
        // Теперь туннель действительно остановлен: обычная lifecycle-отмена снова
        // должна работать во время длительного headless-теста.
        ProbeLifecycle.I.register(canceller);
        lifecycleReRegistered = true;

        result = await _runHeadless(
          nodes,
          url: url,
          timeoutMs: timeoutMs,
          onResult: onResult,
        );
      }
    } finally {
      if (!lifecycleReRegistered) {
        // stop failed / VPN did not reach Stopped — вернуть runner в реестр.
        ProbeLifecycle.I.register(canceller);
      }

      if (stopSucceeded) {
        // Восстанавливаем VPN даже после отмены теста или ошибки probe-сессии.
        // Если пользователь успел включить его вручную, второй start не нужен.
        var status = await vpn.getVpnStatus();
        if (status == TunnelStatus.disconnected) {
          final startOk = await vpn.startVPN();
          if (!startOk) {
            restoreError = 'VPN could not be restored after server test';
          } else {
            status = await vpn.getVpnStatus();
          }
        }
        if (restoreError.isEmpty) {
          for (var attempt = 0;
              attempt < 60 && status != TunnelStatus.connected;
              attempt++) {
            if (status == TunnelStatus.error ||
                status == TunnelStatus.revoked) {
              restoreError = 'VPN failed to start after server test';
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 250));
            status = await vpn.getVpnStatus();
          }
          if (restoreError.isEmpty && status != TunnelStatus.connected) {
            restoreError = 'VPN did not become active after server test';
          }
        }
      }
    }

    if (restoreError.isNotEmpty) {
      AppLog.I.warning('Probe: $restoreError');
      if (result.isEmpty) return restoreError;
      return '$result\n$restoreError';
    }
    return result;
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
        // При активном VPN такие ноды не доходят сюда: run() заранее переводит
        // весь прогон во временный VPN-off headless-режим.
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
  }) {
    if (node == null) return null;
    for (final entry in liveTagMap.entries) {
      if (entry.value == node) return entry.key;
    }
    // Нет соответствия — значит узел не присутствует в последней реально
    // собранной конфигурации. Не подставляем предположительный tag: это могло
    // превратить отсутствующий outbound в мгновенный ложный ERR.
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
