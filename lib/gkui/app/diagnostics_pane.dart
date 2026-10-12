part of '../../main_gkui.dart';

class DiagnosticsPane extends StatefulWidget {
  const DiagnosticsPane(
      {required this.logs, required this.controller, super.key});
  final RedactingLogStore logs;
  final GkuiController controller;
  @override
  State<DiagnosticsPane> createState() => _DiagnosticsPaneState();
}

class _DiagnosticsPaneState extends State<DiagnosticsPane> {
  late Future<DeviceDiagnostics> diagnostics = DeviceDiagnostics.load();

  Future<void> copyDiagnostics() async {
    final snapshot = await diagnostics;
    final details = snapshot.values.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('\n');
    await Clipboard.setData(ClipboardData(
        text:
            '$buildLabel\n$sourceLabel\n$toolchainLabel\n$details\n\n${widget.logs.exportText()}'));
    widget.logs.add('Diagnostics copied to clipboard.');
  }

  /// Shows the redacted diagnostics as a QR code a phone can scan.
  Future<void> showQr() async {
    final snapshot = await diagnostics;
    if (!mounted) return;
    final header = <String>[
      buildLabel,
      toolchainLabel,
      ...snapshot.values.entries.map((entry) => '${entry.key}: ${entry.value}'),
      'endpoint: ${widget.controller.api?.safeEndpoint ?? 'not connected'}',
      'last failure: ${widget.controller.lastPlaybackFailure ?? 'none'}',
    ].join('\n');
    final text = qrDiagnostics(header, widget.logs.exportText());
    final size =
        (MediaQuery.of(context).size.shortestSide - 110).clamp(200.0, 420.0);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const EdgeInsets.all(16),
        content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(8),
            child: QrImageView(data: text, size: size.toDouble()),
          ),
          const SizedBox(height: 8),
          const Text('Scan with a phone camera to share the latest logs.',
              style: TextStyle(fontSize: 15)),
        ]),
        actions: <Widget>[
          TextButton(
              onPressed: () {
                copyDiagnostics();
                Navigator.pop(context);
              },
              child: const Text('Copy all', style: TextStyle(fontSize: 18))),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(fontSize: 18))),
        ],
      ),
    );
    widget.logs.add('Diagnostics shown as a QR code.');
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(children: <Widget>[
                const Expanded(
                    child: PageHeading(
                        title: 'Device status',
                        subtitle: 'Plex, player, memory and redacted logs')),
                ElevatedButton.icon(
                  onPressed: () =>
                      setState(() => diagnostics = DeviceDiagnostics.load()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                    onPressed: showQr,
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('QR')),
                const SizedBox(width: 8),
                OutlinedButton(
                    onPressed: widget.controller.signOut,
                    child: const Text('Sign out')),
              ]),
              const SizedBox(height: 12),
              Expanded(
                  child: Row(children: <Widget>[
                Expanded(
                    child: Card(
                        child: FutureBuilder<DeviceDiagnostics>(
                  future: diagnostics,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());
                    final rows = <MapEntry<String, String>>[
                      const MapEntry<String, String>('build', buildLabel),
                      const MapEntry<String, String>('source', sourceLabel),
                      const MapEntry<String, String>(
                          'toolchain', toolchainLabel),
                      MapEntry<String, String>(
                          'server',
                          widget.controller.api?.session?.serverName ??
                              'not connected'),
                      ...snapshot.data!.values.entries,
                      MapEntry<String, String>(
                          'endpoint',
                          widget.controller.api?.safeEndpoint ??
                              'not connected'),
                      MapEntry<String, String>(
                          'profile',
                          widget.controller.currentHomeUser?.displayName ??
                              widget.controller.api?.currentHomeUserName ??
                              'Plex account'),
                      MapEntry<String, String>(
                          'media version',
                          widget.controller.lastSelectedVersion ??
                              'not played yet'),
                      MapEntry<String, String>(
                          'content startup',
                          widget.controller.lastContentLoadMs == null
                              ? 'not measured'
                              : '${widget.controller.lastContentLoadMs} ms'),
                      MapEntry<String, String>(
                          'first frame',
                          widget.controller.lastFirstFrameMs == null
                              ? 'not measured'
                              : '${widget.controller.lastFirstFrameMs} ms'),
                      MapEntry<String, String>('decoder',
                          widget.controller.lastDecoder ?? 'not reported'),
                      MapEntry<String, String>('video format',
                          widget.controller.lastVideoFormat ?? 'not reported'),
                      MapEntry<String, String>(
                          'startup network',
                          widget.controller.lastStartupNetworkBytes == null
                              ? 'not measured'
                              : formatDiagnosticBytes(
                                  widget.controller.lastStartupNetworkBytes!)),
                      MapEntry<String, String>('last failure',
                          widget.controller.lastPlaybackFailure ?? 'none'),
                    ];
                    return ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 12),
                      itemBuilder: (_, index) => Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SizedBox(
                                width: 125,
                                child: Text(rows[index].key,
                                    style: const TextStyle(
                                        color: Colors.white60))),
                            Expanded(
                                child: SelectableText(rows[index].value,
                                    style: const TextStyle(fontSize: 15))),
                          ]),
                    );
                  },
                ))),
                const SizedBox(width: 14),
                Expanded(
                    child: Card(
                        child: AnimatedBuilder(
                  animation: widget.logs,
                  builder: (_, __) => ListView.builder(
                    padding: const EdgeInsets.all(14),
                    itemCount: widget.logs.entries.length,
                    itemBuilder: (_, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SelectableText(widget.logs.entries[index].line,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Colors.white70)),
                    ),
                  ),
                ))),
              ])),
            ]),
      );
}
