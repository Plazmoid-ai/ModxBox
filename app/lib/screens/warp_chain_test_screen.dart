import 'dart:async';

import 'package:flutter/material.dart';

import '../models/node_spec.dart';
import '../services/l10n/locale_controller.dart';
import '../services/settings_storage.dart';
import '../services/warp/warp_chain_probe.dart';

class WarpChainTestScreen extends StatefulWidget {
  const WarpChainTestScreen({super.key});

  @override
  State<WarpChainTestScreen> createState() => _WarpChainTestScreenState();
}

class _WarpChainTestScreenState extends State<WarpChainTestScreen> {
  final _probe = WarpChainProbe();
  List<NodeSpec> _nodes = const [];
  final _selected = <String>{};
  final _results = <WarpChainProbeResult>[];

  String _url = '';
  int _timeoutMs = 5000;
  String? _loadError;
  String? _runError;
  bool _loading = true;
  bool _running = false;
  int _done = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _probe.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final lists = await SettingsStorage.getServerLists();
      final opts = await SettingsStorage.getPingOptions();
      final nodes = <NodeSpec>[];
      final seen = <String>{};

      for (final list in lists) {
        for (final node in list.nodes) {
          if (node is! WireguardSpec) continue;
          final isWarp = node.peers.any((p) => p.reserved != null);
          if (!isWarp) continue;
          final key = '${node.id}${node.tag}';
          if (seen.add(key)) nodes.add(node);
        }
      }

      final url = (opts['url'] as String?)?.trim() ?? '';
      final timeout = (opts['timeout_ms'] as num?)?.toInt() ?? 5000;

      if (!mounted) return;
      setState(() {
        _nodes = nodes;
        _url = url;
        _timeoutMs = timeout > 0 ? timeout : 5000;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  int get _pairCount => warpChainPairCount(_selected.length);

  String _nodeKey(NodeSpec node) => '${node.id}${node.tag}';

  void _toggleAll(bool value) {
    setState(() {
      if (value) {
        _selected
          ..clear()
          ..addAll(_nodes.map(_nodeKey));
      } else {
        _selected.clear();
      }
    });
  }

  Future<void> _run() async {
    if (_running || _selected.length < 2) return;

    final nodes = [
      for (final node in _nodes)
        if (_selected.contains(_nodeKey(node))) node,
    ];

    if (_url.isEmpty) {
      setState(() => _runError =
          getLocalText.s('Test URL is not configured.'));
      return;
    }

    setState(() {
      _running = true;
      _runError = null;
      _results.clear();
      _done = 0;
      _total = _pairCount;
    });

    final error = await _probe.run(
      nodes,
      url: _url,
      timeoutMs: _timeoutMs,
      onResult: (done, total, result) {
        if (!mounted) return;
        setState(() {
          _done = done;
          _total = total;
          _results.add(result);
        });
      },
    );

    if (!mounted) return;
    setState(() {
      _running = false;
      if (error.isNotEmpty) _runError = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(getLocalText.s('WARP chain test'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(getLocalText.s('WARP chain test'))),
      body: Column(
        children: [
          _buildSelectionHeader(),
          Expanded(
            child: _results.isEmpty ? _buildNodeList() : _buildResults(),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildSelectionHeader() {
    final allSelected =
        _nodes.isNotEmpty && _selected.length == _nodes.length;

    return Material(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              getLocalText.s(
                'Select WARP nodes. Each pair is tested in both directions: A → B and B → A.',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_selected.length} selected · ${_pairCount} directed pairs',
                  ),
                ),
                TextButton(
                  onPressed: _nodes.isEmpty
                      ? null
                      : () => _toggleAll(!allSelected),
                  child: Text(
                    allSelected
                        ? getLocalText.s('Clear all')
                        : getLocalText.s('Select all'),
                  ),
                ),
              ],
            ),
            if (_runError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _runError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            if (_loadError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _loadError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNodeList() {
    if (_nodes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            getLocalText.s('No WARP nodes found in saved server lists.'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _nodes.length,
      itemBuilder: (context, index) {
        final node = _nodes[index];
        final selected = _selected.contains(_nodeKey(node));
        return CheckboxListTile(
          value: selected,
          onChanged: _running
              ? null
              : (value) {
                  setState(() {
                    if (value == true) {
                      _selected.add(_nodeKey(node));
                    } else {
                      _selected.remove(_nodeKey(node));
                    }
                  });
                },
          title: Text(
            node.label.isNotEmpty ? node.label : node.tag,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${node.server}:${node.port} · ${node.protocol}',
            overflow: TextOverflow.ellipsis,
          ),
          secondary: Text('${index + 1}'),
          controlAffinity: ListTileControlAffinity.leading,
        );
      },
    );
  }

  Widget _buildResults() {
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final r = _results[index];
        final first = r.first.label.isNotEmpty ? r.first.label : r.first.tag;
        final second =
            r.second.label.isNotEmpty ? r.second.label : r.second.tag;

        return ListTile(
          leading: Icon(
            r.ok ? Icons.check_circle_outline : Icons.error_outline,
            color: r.ok
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
          ),
          title: Text(
            '${first} → ${second}',
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            r.ok
                ? '${r.ip} · ${r.countryName.isNotEmpty ? r.countryName : r.country} · ${r.delayMs} ms'
                : (r.message.isNotEmpty ? r.message : 'Failed'),
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    final progress =
        _total > 0 ? (_done / _total).clamp(0.0, 1.0).toDouble() : 0.0;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_running) ...[
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 6),
            Text('${_done} / ${_total}', textAlign: TextAlign.center),
            const SizedBox(height: 6),
          ],
          FilledButton.icon(
            onPressed: _running || _selected.length < 2 ? null : _run,
            icon: Icon(_running ? Icons.hourglass_top : Icons.play_arrow),
            label: Text(
              _running
                  ? getLocalText.s('Testing…')
                  : getLocalText.s('Test selected chains'),
            ),
          ),
        ],
      ),
    );
  }
}
