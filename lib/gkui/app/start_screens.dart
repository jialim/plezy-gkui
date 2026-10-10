part of '../../main_gkui.dart';

class GkuiRoot extends StatefulWidget {
  const GkuiRoot({super.key});
  @override
  State<GkuiRoot> createState() => _GkuiRootState();
}

class _GkuiRootState extends State<GkuiRoot> with WidgetsBindingObserver {
  final GkuiController controller = GkuiController();
  Timer? updateCheckTimer;
  bool appActive = true;
  DateTime? lastUpdateCheck;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.initialize();
    updateCheckTimer =
        Timer(const Duration(seconds: 10), checkForUpdateQuietly);
  }

  /// The head unit usually sleeps rather than restarting the app, so the
  /// startup check alone could go days without running. Resuming checks again
  /// once [updateRecheckInterval] has passed, and also covers a startup check
  /// skipped because the car clock had not synced yet.
  void checkForUpdateQuietly() {
    if (!mounted || !appActive || !controller.clockValid) return;
    if (!shouldRecheckForUpdate(lastUpdateCheck, DateTime.now())) return;
    lastUpdateCheck = DateTime.now();
    unawaited(offerGkuiUpdate(context, controller, silent: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    appActive = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      unawaited(controller.reconnectAfterResume());
      updateCheckTimer?.cancel();
      updateCheckTimer =
          Timer(const Duration(seconds: 10), checkForUpdateQuietly);
    }
  }

  @override
  void didHaveMemoryPressure() {
    controller.handleMemoryPressure();
  }

  @override
  void dispose() {
    updateCheckTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (controller.phase == AppPhase.starting) {
            return const BusyScreen(label: 'Starting Plezy GKUI…');
          }
          if (!controller.clockValid)
            return ClockScreen(controller: controller);
          if (controller.phase == AppPhase.signedOut ||
              controller.phase == AppPhase.error) {
            return WelcomeScreen(controller: controller);
          }
          if (controller.phase == AppPhase.signingIn)
            return PinScreen(controller: controller);
          if (controller.phase == AppPhase.chooseServer)
            return ServerScreen(controller: controller);
          return GkuiShell(controller: controller);
        },
      );
}

class BusyScreen extends StatelessWidget {
  const BusyScreen({required this.label, super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 22),
          Text(label, style: const TextStyle(fontSize: 22)),
        ])),
      );
}

class ClockScreen extends StatelessWidget {
  const ClockScreen({required this.controller, super.key});
  final GkuiController controller;
  @override
  Widget build(BuildContext context) => CenteredPanel(
        icon: Icons.schedule,
        title: 'Car clock needs to sync',
        message:
            'This unit reports ${DateTime.now().year}. Secure Plex HTTPS requires the correct date. '
            'Connect the car to Wi-Fi or 4G, let its clock update, then tap Retry. TLS security will not be disabled.',
        error: controller.error,
        primaryLabel: 'Retry clock',
        primaryAction: controller.retryClock,
      );
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({required this.controller, super.key});
  final GkuiController controller;
  @override
  Widget build(BuildContext context) => CenteredPanel(
        icon: Icons.play_circle_fill,
        title: 'Plezy GKUI',
        message:
            'Sign in with Plex to browse your server and play video. Scan the QR code with your phone to approve this car display.',
        error: controller.error,
        primaryLabel: 'Sign in to Plex',
        primaryAction: controller.beginSignIn,
        secondaryLabel: controller.api?.session == null ? null : 'Retry server',
        secondaryAction:
            controller.api?.session == null ? null : controller.refreshContent,
      );
}

class CenteredPanel extends StatelessWidget {
  const CenteredPanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.error,
    required this.primaryLabel,
    required this.primaryAction,
    this.secondaryLabel,
    this.secondaryAction,
    super.key,
  });
  final IconData icon;
  final String title;
  final String message;
  final String? error;
  final String primaryLabel;
  final FutureOr<void> Function() primaryAction;
  final String? secondaryLabel;
  final FutureOr<void> Function()? secondaryAction;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Card(
              margin: const EdgeInsets.all(28),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 38, vertical: 26),
                child:
                    Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Icon(icon, size: 60, color: const Color(0xFFE5A00D)),
                  const SizedBox(height: 10),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 30, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Text(message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, height: 1.35)),
                  if (error != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Color(0xFFFF8A80), fontSize: 16)),
                  ],
                  const SizedBox(height: 20),
                  Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    ElevatedButton(
                        onPressed: primaryAction,
                        child: Text(primaryLabel,
                            style: const TextStyle(fontSize: 18))),
                    if (secondaryAction != null) ...<Widget>[
                      const SizedBox(width: 14),
                      OutlinedButton(
                          onPressed: secondaryAction,
                          child: Text(secondaryLabel!,
                              style: const TextStyle(fontSize: 18))),
                    ],
                  ]),
                ]),
              )),
        ))),
      );
}

class PinScreen extends StatelessWidget {
  const PinScreen({required this.controller, super.key});
  final GkuiController controller;
  @override
  Widget build(BuildContext context) {
    final pin = controller.pin!;
    return Scaffold(body: SafeArea(child: LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 1000 || constraints.maxHeight < 600;
        final qrSize = compact ? 220.0 : 285.0;
        final inset = compact ? 22.0 : 34.0;
        return Row(children: <Widget>[
          Expanded(
              child: Padding(
            padding: EdgeInsets.all(inset),
            child: Center(
                child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Sign in to Plex',
                        style: TextStyle(
                            fontSize: compact ? 28 : 32,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Text(
                        'Scan with your phone, approve Plezy GKUI, and leave this screen open.',
                        style: TextStyle(
                            fontSize: compact ? 17 : 20, height: 1.3)),
                    const SizedBox(height: 12),
                    Text('Code: ${pin.code}',
                        style: TextStyle(
                            fontSize: compact ? 23 : 27,
                            color: const Color(0xFFE5A00D),
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    const Row(children: <Widget>[
                      SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(strokeWidth: 3)),
                      SizedBox(width: 12),
                      Expanded(
                          child: Text('Waiting for approval…',
                              style: TextStyle(fontSize: 17))),
                    ]),
                    const SizedBox(height: 14),
                    OutlinedButton(
                        onPressed: controller.cancelSignIn,
                        child: const Text('Cancel',
                            style: TextStyle(fontSize: 17))),
                  ]),
            )),
          )),
          Container(
            color: Colors.white,
            margin: EdgeInsets.all(compact ? 16 : 24),
            padding: EdgeInsets.all(compact ? 12 : 16),
            child: QrImageView(
                data: pin.authUrl(controller.api!.clientIdentifier),
                size: qrSize),
          ),
        ]);
      },
    )));
  }
}

class ServerScreen extends StatelessWidget {
  const ServerScreen({required this.controller, super.key});
  final GkuiController controller;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Choose a Plex server')),
        body: ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: controller.servers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final server = controller.servers[index];
            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              tileColor: const Color(0xFF1D1D1D),
              leading: const Icon(Icons.dns, size: 38),
              title: Text(server.name, style: const TextStyle(fontSize: 22)),
              subtitle: Text('${server.connections.length} secure route(s)'),
              trailing: const Icon(Icons.chevron_right, size: 36),
              onTap: () => controller.chooseServer(server),
            );
          },
        ),
      );
}
