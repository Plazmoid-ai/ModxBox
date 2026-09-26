import '../../models/node_spec.dart';
import '../../models/tunnel_status.dart';
import '../../vpn/box_vpn_client.dart';
import '../probe/probe_runner.dart';

/// Самостоятельный тест направленных пар WARP.
///
/// Пара трактуется как:
///   first  -> транспортный WARP
///   second -> выходной WARP
///
/// Поэтому sing-box detour строится как [second] <- [first]:
/// запрос сначала идёт через first, затем через second.
///
/// Сервис намеренно не знает о WARP Generator, папках или UI.
class WarpChainProbe {
  WarpChainProbe({
    ProbeRunner? runner,
    BoxVpnClient? vpn,
  })  : _runner = runner ?? ProbeRunner(),
        _vpn = vpn ?? BoxVpnClient();

  final ProbeRunner _runner;
  final BoxVpnClient _vpn;

  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _runner.cancel();
  }

  /// Проверяет все направленные пары.
  ///
  /// Для N узлов создаётся N * (N - 1) пар. Сам узел с собой не тестируется.
  /// [nodes] должен содержать уже отобранные пользователем WARP-ноды.
  ///
  /// Возвращает результаты по мере завершения через [onResult].
  /// first — первый/транспортный WARP, second — второй/выходной.
  Future<String> run(
    List<NodeSpec> nodes, {
    required String url,
    required int timeoutMs,
    required void Function(
      int done,
      int total,
      WarpChainProbeResult result,
    ) onResult,
  }) async {
    _cancelled = false;

    if (nodes.length < 2) return '';

    final vpnStatus = await _vpn.getVpnStatus();
    if (vpnStatus == TunnelStatus.connected) {
      return kProbeVpnRunning;
    }

    final pairs = <({NodeSpec first, NodeSpec second})>[];
    for (var first = 0; first < nodes.length; first++) {
      for (var second = 0; second < nodes.length; second++) {
        if (first == second) continue;
        pairs.add((first: nodes[first], second: nodes[second]));
      }
    }

    var done = 0;
    final chainNodes = <NodeSpec>[
      for (final pair in pairs) withChained(pair.second, pair.first),
    ];

    final error = await _runner.run(
      chainNodes,
      url: url,
      timeoutMs: timeoutMs,
      onResult: (index, probe) {
        if (_cancelled) return;
        done++;
        final pair = pairs[index];
        onResult(
          done,
          pairs.length,
          WarpChainProbeResult(
            first: pair.first,
            second: pair.second,
            status: probe.status,
            delayMs: probe.delayMs,
            message: probe.message,
          ),
        );
      },
    );

    return error;
  }
}

/// Результат одного направленного WARP -> WARP теста.
class WarpChainProbeResult {
  const WarpChainProbeResult({
    required this.first,
    required this.second,
    required this.status,
    this.delayMs = 0,
    this.message = '',
  });

  /// Первый WARP — транспортный хоп.
  final NodeSpec first;

  /// Второй WARP — конечный/выходной хоп.
  final NodeSpec second;

  final ProbeStatus status;
  final int delayMs;
  final String message;

  bool get ok => status == ProbeStatus.ok;
}

/// Число направленных пар без повторения одного и того же узла.
int warpChainPairCount(int nodeCount) =>
    nodeCount < 2 ? 0 : nodeCount * (nodeCount - 1);
