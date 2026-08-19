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

/// Packs declared in freight.yaml.
///
/// The list cannot come from [Freight.allPacks] alone: under a development
/// URL override the system does not pre-populate packs, so nothing is known
/// until something asks for it. A real app knows its own pack ids anyway.
const declaredPacks = ['tutorial', 'maps_europe'];

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

          final known = {for (final pack in snapshot.data ?? const []) pack.id};
          final ids = [
            ...declaredPacks,
            ...known.where((id) => !declaredPacks.contains(id)),
          ];

          return Column(
            children: [
              if (snapshot.hasError)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'allPacks failed: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  itemCount: ids.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _PackTile(packId: ids[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PackTile extends StatefulWidget {
  const _PackTile({required this.packId});

  final String packId;

  @override
  State<_PackTile> createState() => _PackTileState();
}

class _PackTileState extends State<_PackTile> {
  String? _lastAction;

  @override
  Widget build(BuildContext context) {
    final handle = Freight.pack(widget.packId);

    return StreamBuilder<PackStatus>(
      stream: handle.watch(),
      builder: (context, snapshot) {
        final status = snapshot.data;
        return ListTile(
          // Reading a file is the only proof that the pack's contents actually
          // arrived; a status of "ready" is the system's word for it.
          onTap: () => _read(),
          title: Text(widget.packId),
          subtitle: Text(_lastAction ?? _describe(status)),
          trailing: switch (status) {
            PackDownloading(:final fraction) => SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(value: fraction, strokeWidth: 3),
            ),
            PackReady() => IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove',
              onPressed: () => _run('remove', handle.remove),
            ),
            _ => IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Download',
              onPressed: () => _run('download', handle.ensureDownloaded),
            ),
          },
        );
      },
    );
  }

  /// Reads a known file out of the pack and reports what came back.
  Future<void> _read() async {
    final path = widget.packId == 'tutorial' ? 'welcome.txt' : 'index.txt';
    setState(() => _lastAction = 'reading $path…');
    try {
      final bytes = await Freight.read(path, inPack: widget.packId);
      final text = String.fromCharCodes(bytes).trim();
      if (mounted) {
        setState(() => _lastAction = '$path: ${bytes.length} bytes "$text"');
      }
    } catch (e) {
      if (mounted) setState(() => _lastAction = 'read failed: $e');
    }
  }

  Future<void> _run(String what, Future<void> Function() action) async {
    setState(() => _lastAction = '$what…');
    try {
      await action();
      if (mounted) setState(() => _lastAction = '$what ok');
    } catch (e) {
      if (mounted) setState(() => _lastAction = '$what failed: $e');
    }
  }

  String _describe(PackStatus? status) => switch (status) {
    PackDownloading(:final completedBytes, :final totalBytes) =>
      '$completedBytes of $totalBytes bytes',
    PackPaused() => 'Paused',
    PackReady(:final version) => 'Ready, v$version',
    PackFailed(:final error) => 'Failed: ${error.message}',
    _ => 'Tap row to read, arrow to download',
  };
}
