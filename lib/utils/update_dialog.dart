import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/strings.g.dart';
import '../services/update_service.dart';
import '../widgets/dialog_action_button.dart';
import 'app_logger.dart';
import 'dialogs.dart';

typedef XgimiUpdateDownloader =
    Future<String> Function(
      Map<String, dynamic> info, {
      ValueChanged<double?>? onProgress,
      XgimiUpdateCancellation? cancellation,
    });

Future<void> showUpdateAvailableDialog(
  BuildContext context,
  Map<String, dynamic> updateInfo, {
  required String title,
  required String dismissLabel,
  bool showSkipVersion = false,
  XgimiUpdateDownloader? xgimiDownloader,
}) {
  return showScopedDialog<void>(
    context: context,
    builder: (dialogContext) {
      final latestVersion = updateInfo['latestVersion'] as String;
      final releaseUrl = updateInfo['releaseUrl'] as String;
      final canInstall = updateInfo['canInstall'] == true;

      return AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            Text(
              t.update.versionAvailable(version: latestVersion),
              style: Theme.of(dialogContext).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              t.update.currentVersion(version: updateInfo['currentVersion']),
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          DialogActionButton(onPressed: () => Navigator.pop(dialogContext), label: dismissLabel),
          if (showSkipVersion)
            DialogActionButton(
              onPressed: () async {
                await UpdateService.skipVersion((updateInfo['skipVersionKey'] as String?) ?? latestVersion);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              label: t.update.skipVersion,
            ),
          DialogActionButton(
            onPressed: () async {
              if (canInstall) {
                Navigator.pop(dialogContext);
                await showScopedDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => _XgimiUpdateProgressDialog(
                    updateInfo: updateInfo,
                    download: xgimiDownloader ?? UpdateService.downloadAndInstallXgimiUpdate,
                  ),
                );
                return;
              }
              final url = Uri.parse(releaseUrl);
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            label: canInstall ? t.update.downloadAndInstall : t.update.viewRelease,
            isPrimary: true,
          ),
        ],
      );
    },
  );
}

class _XgimiUpdateProgressDialog extends StatefulWidget {
  const _XgimiUpdateProgressDialog({required this.updateInfo, required this.download});

  final Map<String, dynamic> updateInfo;
  final XgimiUpdateDownloader download;

  @override
  State<_XgimiUpdateProgressDialog> createState() => _XgimiUpdateProgressDialogState();
}

class _XgimiUpdateProgressDialogState extends State<_XgimiUpdateProgressDialog> {
  double? _progress;
  bool _permissionRequested = false;
  bool _failed = false;
  bool _running = false;
  bool _closing = false;
  XgimiUpdateFailure? _failure;
  String? _failureDetail;
  XgimiUpdateCancellation? _cancellation;

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }

  void _cancelAndClose() {
    _cancellation?.cancel();
    _close();
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.pop(context);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_running || _closing || !mounted) return;
    final cancellation = XgimiUpdateCancellation();
    _cancellation = cancellation;
    setState(() {
      _running = true;
      _failed = false;
      _failure = null;
      _failureDetail = null;
      _permissionRequested = false;
      _progress = null;
    });
    try {
      final result = await widget.download(
        widget.updateInfo,
        cancellation: cancellation,
        onProgress: (value) {
          if (!mounted || _closing) return;
          final previous = _progress;
          if (value == null || previous == null || value >= 1 || value - previous >= 0.01) {
            setState(() => _progress = value);
          }
        },
      );
      if (!mounted) return;
      if (result == 'permission_requested') {
        setState(() {
          _running = false;
          _permissionRequested = true;
        });
      } else {
        _close();
      }
    } on XgimiUpdateCancelled {
      _close();
    } catch (error, stackTrace) {
      appLogger.w('XGIMI update failed', error: error, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _running = false;
        _failed = true;
        _failure = error is XgimiUpdateException ? error.failure : XgimiUpdateFailure.network;
        // Shown under the message so a photo of the screen names the cause.
        _failureDetail = error is XgimiUpdateException && error.failure != XgimiUpdateFailure.network
            ? error.cause?.toString()
            : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = widget.updateInfo['latestVersion'];
    final canClose = _failed || _permissionRequested;
    return PopScope(
      canPop: canClose,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _running) _cancelAndClose();
      },
      child: AlertDialog(
        title: Text(t.update.downloading(version: version)),
        content: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            if (_permissionRequested)
              Text(t.update.allowInstall)
            else if (_failed)
              Text(switch (_failure) {
                XgimiUpdateFailure.storage => t.update.storageFailed,
                XgimiUpdateFailure.verification => t.update.verificationFailed,
                XgimiUpdateFailure.installer => t.update.installerFailed,
                XgimiUpdateFailure.busy => t.update.downloadBusy,
                _ => t.update.downloadFailed,
              })
            else ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 12),
              Text(
                _progress == null ? '…' : '${(_progress! * 100).clamp(0, 100).round()}%',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
            if (_failed && !_permissionRequested && _failureDetail != null) ...[
              const SizedBox(height: 8),
              Text(_failureDetail!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
        actions: [
          if (_running) DialogActionButton(onPressed: _cancelAndClose, label: t.common.cancel),
          if (canClose) DialogActionButton(onPressed: () => Navigator.pop(context), label: t.common.close),
          if (_failed) DialogActionButton(onPressed: _start, label: t.common.retry, isPrimary: true),
        ],
      ),
    );
  }
}
