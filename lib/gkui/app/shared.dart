part of '../../main_gkui.dart';

enum AppPhase { starting, signedOut, signingIn, chooseServer, ready, error }

enum PlaybackMode { direct, transcode720, transcode480 }

/// Reads the audio/subtitle tracks picked inside the native player and maps
/// them to Plex streams. Returns null when the driver changed nothing.
PlaybackChoice? playerTrackChoice(
  Map<String, dynamic>? raw, {
  required List<PlexTrack> audioTracks,
  required List<PlexTrack> subtitleTracks,
}) {
  if (raw == null) return null;
  final audioChanged = raw.containsKey('audioLanguage');
  final subtitleChanged = raw.containsKey('subtitleLanguage');
  if (!audioChanged && !subtitleChanged) return null;

  String? audioId;
  String? audioLanguage;
  String? audioTitle;
  int? audioOrdinal;
  if (audioChanged) {
    final track = trackForPreference(
      audioTracks,
      id: raw['audioTrackId']?.toString(),
      language: raw['audioLanguage']?.toString(),
      title: raw['audioTitle']?.toString(),
      ordinal: (raw['audioOrdinal'] as num?)?.toInt(),
    );
    audioId = track?.id;
    audioLanguage = track?.languageCode ?? raw['audioLanguage']?.toString();
    audioTitle = track?.title ?? raw['audioTitle']?.toString();
    audioOrdinal = track == null
        ? (raw['audioOrdinal'] as num?)?.toInt()
        : audioTracks.indexOf(track);
  }

  String? subtitleId;
  String? subtitleLanguage;
  String? subtitleTitle;
  int? subtitleOrdinal;
  if (subtitleChanged) {
    if (raw['subtitleTrackId'] == 'off') {
      subtitleId = 'off';
      subtitleLanguage = 'off';
    } else {
      final track = trackForPreference(
        subtitleTracks,
        id: raw['subtitleTrackId']?.toString(),
        language: raw['subtitleLanguage']?.toString(),
        title: raw['subtitleTitle']?.toString(),
        ordinal: (raw['subtitleOrdinal'] as num?)?.toInt(),
      );
      subtitleId = track?.id;
      subtitleLanguage =
          track?.languageCode ?? raw['subtitleLanguage']?.toString();
      subtitleTitle = track?.title ?? raw['subtitleTitle']?.toString();
      subtitleOrdinal = track == null
          ? (raw['subtitleOrdinal'] as num?)?.toInt()
          : subtitleTracks.indexOf(track);
    }
  }
  return PlaybackChoice(
    audioTrackId: audioId,
    subtitleTrackId: subtitleId,
    audioLanguage: audioLanguage,
    subtitleLanguage: subtitleLanguage,
    audioTitle: audioTitle,
    subtitleTitle: subtitleTitle,
    audioOrdinal: audioOrdinal,
    subtitleOrdinal: subtitleOrdinal,
  );
}

PlaybackMode? playbackFallback(PlaybackMode mode, String? failureKind) {
  // A transcode of a missing file fails the same way, so none is attempted.
  if (failureKind == 'network' ||
      failureKind == 'http' ||
      failureKind == 'missing' ||
      failureKind == 'initialization') {
    return null;
  }
  return switch (mode) {
    PlaybackMode.direct => PlaybackMode.transcode720,
    PlaybackMode.transcode720 => PlaybackMode.transcode480,
    PlaybackMode.transcode480 => null,
  };
}

/// A failed refresh leaves already-shown content in place unless Plex
/// rejected the token, which needs a new sign-in.
bool keepsCachedContent({required bool hasContent, required Object error}) =>
    hasContent && !(error is DioException && error.response?.statusCode == 401);

/// A playing stream that dropped gets one automatic resume from where it
/// stopped; a video that never started keeps the normal failure dialog.
bool shouldAutoResume(
        {required bool renderedFrame,
        required String? failureKind,
        required bool alreadyResumed}) =>
    renderedFrame &&
    !alreadyResumed &&
    (failureKind == 'network' || failureKind == 'http');

String formatPlaybackTime(int milliseconds) {
  final total = (milliseconds < 0 ? 0 : milliseconds) ~/ 1000;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${two(minutes)}:${two(seconds)}'
      : '${two(minutes)}:${two(seconds)}';
}

String formatRuntime(int milliseconds) {
  final minutes = (milliseconds / 60000).round();
  if (minutes < 60) return '$minutes min';
  final rest = minutes % 60;
  return rest == 0 ? '${minutes ~/ 60} h' : '${minutes ~/ 60} h $rest min';
}

class GkuiUpdateInfo {
  const GkuiUpdateInfo({
    required this.available,
    required this.currentVersion,
    required this.latestVersion,
    required this.assetSize,
  });

  final bool available;
  final String currentVersion;
  final String latestVersion;
  final int assetSize;

  factory GkuiUpdateInfo.fromMap(Map<Object?, Object?> raw) => GkuiUpdateInfo(
        available: raw['available'] == true,
        currentVersion: raw['currentVersion']?.toString() ?? 'unknown',
        latestVersion: raw['latestVersion']?.toString() ?? 'unknown',
        assetSize: (raw['assetSize'] as num?)?.toInt() ?? 0,
      );
}

const Duration updateRecheckInterval = Duration(hours: 12);

bool shouldRecheckForUpdate(DateTime? lastCheck, DateTime now) =>
    lastCheck == null || now.difference(lastCheck) >= updateRecheckInterval;

String formatUpdateSize(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB'
    : '${bytes ~/ 1024} KiB';

Future<void> offerGkuiUpdate(
  BuildContext context,
  GkuiController controller, {
  required bool silent,
}) async {
  final info = await controller.checkForAppUpdate(silent: silent);
  if (!context.mounted) return;
  if (info == null) {
    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(controller.updateError ?? 'Could not check for updates.')));
    }
    return;
  }
  if (!info.available) {
    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Plezy GKUI ${info.currentVersion} is up to date.')));
    }
    return;
  }

  final install = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Plezy GKUI update available'),
      content: Text(
        'Version ${info.latestVersion} is ready (${formatUpdateSize(info.assetSize)}).\n\n'
        'Plezy will download and verify the signed ARMv7 APK, then Android will ask you to confirm installation. No USB drive is needed.',
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Later')),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.system_update),
          label: const Text('Download and install'),
        ),
      ],
    ),
  );
  if (install != true || !context.mounted) return;

  var progressOpen = true;
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: <Widget>[
        SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 3)),
        SizedBox(width: 18),
        Expanded(
            child: Text('Downloading and verifying update…',
                style: TextStyle(fontSize: 18))),
      ]),
    ),
  ).whenComplete(() => progressOpen = false));
  await Future<void>.delayed(const Duration(milliseconds: 100));

  try {
    await controller.downloadAndInstallUpdate();
    if (context.mounted && progressOpen) {
      Navigator.of(context, rootNavigator: true).pop();
      progressOpen = false;
    }
  } catch (_) {
    if (context.mounted && progressOpen) {
      Navigator.of(context, rootNavigator: true).pop();
      progressOpen = false;
    }
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Update could not be installed'),
          content: Text(controller.updateError ?? 'The update failed.'),
          actions: <Widget>[
            ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close')),
          ],
        ),
      );
    }
  }
}

String? episodeLabel(PlexMedia media) {
  if (media.type != 'episode') return null;
  final number = <String>[
    if (media.parentIndex != null) 'S${media.parentIndex}',
    if (media.index != null) 'E${media.index}',
  ].join(' ');
  return <String>[
    if (number.isNotEmpty) number,
    if (media.subtitle != null && media.subtitle!.isNotEmpty) media.subtitle!,
  ].join(' · ');
}

int playbackStartupHardTimeoutMs(PlaybackMode mode) =>
    mode == PlaybackMode.direct ? 90000 : 120000;

String formatDiagnosticBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '$bytes B';
}

enum LibraryView { all, unwatched, collections }
