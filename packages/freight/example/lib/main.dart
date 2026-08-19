import 'package:flutter/material.dart';
import 'package:freight/freight.dart';

void main() => runApp(const FreightExampleApp());

class FreightExampleApp extends StatelessWidget {
  const FreightExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'freight',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: const PackListPage(),
    );
  }
}

class PackListPage extends StatefulWidget {
  const PackListPage({super.key});

  @override
  State<PackListPage> createState() => _PackListPageState();
}

class _PackListPageState extends State<PackListPage> {
  Future<List<PackInfo>>? _packs;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    // Block body, not an arrow: an arrow would return the assigned Future and
    // setState rejects a callback that returns one.
    setState(() {
      _packs = Freight.allPacks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asset packs'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
          ),
        ],
      ),
      body: FutureBuilder<List<PackInfo>>(
        future: _packs,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _Message(
              title: 'Could not list packs',
              detail: '${snapshot.error}',
            );
          }
          final packs = snapshot.data ?? const [];
          if (packs.isEmpty) {
            return const _Message(
              title: 'No asset packs',
              detail:
                  'Build a pack with ba-package and serve its download '
                  'manifest, then pull to reload.',
            );
          }
          return ListView.separated(
            itemCount: packs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => _PackTile(pack: packs[i]),
          );
        },
      ),
    );
  }
}

class _PackTile extends StatelessWidget {
  const _PackTile({required this.pack});

  final PackInfo pack;

  @override
  Widget build(BuildContext context) {
    final handle = Freight.pack(pack.id);

    return StreamBuilder<PackStatus>(
      stream: handle.watch(),
      builder: (context, snapshot) {
        final status = snapshot.data;
        return ListTile(
          title: Text(pack.id),
          subtitle: Text(_describe(status, pack)),
          trailing: switch (status) {
            PackDownloading(:final fraction) => SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(value: fraction, strokeWidth: 3),
            ),
            PackReady() => IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove',
              onPressed: handle.remove,
            ),
            _ => IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Download',
              onPressed: handle.ensureDownloaded,
            ),
          },
        );
      },
    );
  }

  String _describe(PackStatus? status, PackInfo info) {
    final size = _formatBytes(info.downloadSize);
    return switch (status) {
      PackDownloading(:final completedBytes, :final totalBytes) =>
        '${_formatBytes(completedBytes)} of ${_formatBytes(totalBytes)}',
      PackPaused() => 'Paused · $size',
      PackReady(:final version, :final hasUpdate) =>
        hasUpdate
            ? 'v$version · update available'
            : 'Ready · v$version · $size',
      PackFailed(:final error) => 'Failed · ${error.message}',
      _ => info.flags.downloaded ? 'Ready · $size' : 'Not downloaded · $size',
    };
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(1)} ${units[unit]}';
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
