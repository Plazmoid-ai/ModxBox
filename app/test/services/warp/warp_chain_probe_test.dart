// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/services/platform_channels.dart';
import 'package:lxbox/services/warp/warp_chain_probe.dart';
import 'package:lxbox/services/probe/probe_runner.dart';

class _FakeRunner extends ProbeRunner {
  List<NodeSpec>? seenNodes;

  @override
  Future<String> run(
    List<NodeSpec?> nodes, {
    required String url,
    required int timeoutMs,
    required void Function(int index, ProbeResult result) onResult,
  }) async {
    seenNodes = [for (final node in nodes) node!];
    for (var i = 0; i < nodes.length; i++) {
      onResult(i, const ProbeResult(ProbeStatus.ok, delayMs: 123));
    }
    return '';
  }
}

WireguardSpec _node(String tag) => WireguardSpec(
      id: tag,
      tag: tag,
      label: tag,
      server: '192.0.2.1',
      port: 51820,
      rawSource: 'wg://$tag',
      privateKey: '',
      localAddresses: const ['10.0.0.2/32'],
      peers: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methods = MethodChannel(PlatformChannels.methods);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(methods, (call) async {
      if (call.method == 'getVpnStatus') return 'Stopped';
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
  });

  test('N nodes produce N*(N-1) directed pairs', () {
    expect(warpChainPairCount(0), 0);
    expect(warpChainPairCount(1), 0);
    expect(warpChainPairCount(2), 2);
    expect(warpChainPairCount(20), 380);
    expect(warpChainPairCount(30), 870);
  });

  test('first is transport and second is exit', () async {
    final runner = _FakeRunner();
    final first = _node('WARP 1');
    final second = _node('WARP 2');

    final results = <WarpChainProbeResult>[];
    final error = await WarpChainProbe(runner: runner).run(
      [first, second],
      url: 'https://probe.example/204',
      timeoutMs: 3000,
      onResult: (_, __, result) => results.add(result),
    );

    expect(error, isEmpty);
    expect(results.length, 2);

    final firstPair = results.firstWhere(
      (r) => r.first.tag == 'WARP 1' && r.second.tag == 'WARP 2',
    );
    expect(firstPair.ok, isTrue);
    expect(firstPair.delayMs, 123);

    final chain = runner.seenNodes!.firstWhere(
      (n) => n.tag == 'WARP 2',
    );
    expect(chain.chained?.tag, 'WARP 1');
  });

  test('active VPN prevents chain probe', () async {
    messenger.setMockMethodCallHandler(methods, (call) async {
      if (call.method == 'getVpnStatus') return 'Started';
      return null;
    });

    final runner = _FakeRunner();
    final results = <WarpChainProbeResult>[];

    final error = await WarpChainProbe(runner: runner).run(
      [_node('A'), _node('B')],
      url: 'https://probe.example/204',
      timeoutMs: 3000,
      onResult: (_, __, result) => results.add(result),
    );

    expect(error, kProbeVpnRunning);
    expect(results, isEmpty);
    expect(runner.seenNodes, isNull);
  });
}
