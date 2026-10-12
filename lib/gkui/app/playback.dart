part of '../../main_gkui.dart';

/// Opening a title in the native player, plus the retry, fallback and
/// next-episode flow around it.
extension GkuiPlayback on GkuiController {
  Future<void> play(BuildContext context, PlexMedia media, PlaybackMode mode,
      {int? mediaIndex,
      String? audioTrackId,
      String? subtitleTrackId,
      int? startMs,
      bool autoResumed = false,
      bool checkFiles = true,
      bool allowAutoNext = true}) async {
    String? failureKind;
    // Only a failure the native player reported may change video profile;
    // a metadata or channel error before it opened is not a codec problem.
    var playerReportedFailure = false;
    var renderedFrame = false;
    int? resumeAtMs = startMs;
    PlaybackRequest? activeRequest;
    var preparingVisible = false;
    // Retries and fallbacks reuse any track the driver picked inside the player.
    var retryAudioTrackId = audioTrackId;
    var retrySubtitleTrackId = subtitleTrackId;
    var selectedIndex = mediaIndex ?? 0;
    var item = media;
    var reconnectAttempts = 0;
    try {
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
                child:
                    Text('Preparing video…', style: TextStyle(fontSize: 19))),
          ]),
        ),
      ));
      preparingVisible = true;
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // One request loads the title and asks Plex about its files. A retry
      // of a file that was just streaming skips the check.
      Map<String, dynamic>? checkedMetadata;
      var filesChecked = false;
      if (item.versions.isEmpty && checkFiles) {
        final loaded = await api!.loadMetadataCheckingFiles(item.ratingKey);
        item = loaded.item;
        checkedMetadata = loaded.checked;
        filesChecked = true;
      } else if (item.versions.isEmpty) {
        item = await api!.loadMetadata(item.ratingKey);
      }
      final remembered = api!.loadPlaybackChoice(item);
      final rememberedIndex = remembered.mediaIndex;
      selectedIndex = mediaIndex ??
          (rememberedIndex != null &&
                  item.versions
                      .any((version) => version.index == rememberedIndex)
              ? rememberedIndex
              : PlexMediaVersion.preferredIndex(item.versions));
      // Plex knows when a file is gone; say so instead of opening a player
      // that can only fail on it.
      final missingReason = !checkFiles
          ? null
          : checkedMetadata != null
              ? PlexApi.fileProblem(checkedMetadata, selectedIndex)
              : filesChecked
                  ? null
                  : await api!.missingFileReason(item.ratingKey, selectedIndex);
      if (missingReason != null) {
        failureKind = 'missing';
        throw StateError(missingReason);
      }
      final selectedVersion = item.versions
          .where((version) => version.index == selectedIndex)
          .firstOrNull;
      lastSelectedVersion = selectedVersion?.displayLabel ?? 'Original';
      final startAt = startMs ?? resumeOffsetFor(item);
      final playbackDurationMs = selectedVersion?.durationMs ?? item.durationMs;
      resumeAtMs = startAt;

      final versionAudio = selectedVersion?.audioTracks ?? const <PlexTrack>[];
      final versionSubtitles =
          selectedVersion?.subtitleTracks ?? const <PlexTrack>[];
      final tracks = resolvePlaybackTracks(selectedVersion,
          remembered: remembered,
          settings: settings,
          audioTrackId: audioTrackId,
          subtitleTrackId: subtitleTrackId);
      final selectedAudio = tracks.audio;
      final selectedSubtitle = tracks.subtitle;
      final resolvedAudioTrackId = selectedAudio?.id;
      final resolvedSubtitleTrackId = tracks.subtitleId;
      await api!.savePlaybackChoice(
          item,
          PlaybackChoice(
            mediaIndex: selectedIndex,
            audioTrackId: resolvedAudioTrackId,
            subtitleTrackId: resolvedSubtitleTrackId,
            audioLanguage:
                selectedAudio?.languageCode ?? remembered.audioLanguage,
            subtitleLanguage: resolvedSubtitleTrackId == 'off'
                ? 'off'
                : selectedSubtitle?.languageCode ?? remembered.subtitleLanguage,
            audioTitle: selectedAudio?.title,
            subtitleTitle: selectedSubtitle?.title,
            audioOrdinal: selectedAudio == null
                ? null
                : versionAudio.indexOf(selectedAudio),
            subtitleOrdinal: selectedSubtitle == null
                ? null
                : versionSubtitles.indexOf(selectedSubtitle),
            playbackMode: remembered.playbackMode,
          ));

      final markers = settings.skipMode != SkipMode.off
          ? api!.cachedMarkers(item.ratingKey)
          : const <PlexMarker>[];
      final bitrate = mode == PlaybackMode.transcode480 ? 1500 : 3000;
      final request = api!.playback(
        item,
        transcode: mode != PlaybackMode.direct,
        bitrate: bitrate,
        mediaIndex: selectedIndex,
        audioTrackId: resolvedAudioTrackId,
        subtitleTrackId:
            resolvedSubtitleTrackId == 'off' ? null : resolvedSubtitleTrackId,
      );
      activeRequest = request;
      logs.add(
          'Opening ${request.transcoding ? '${bitrate}kbps HLS' : 'direct'} playback (${lastSelectedVersion!}): ${item.title}.');
      if (preparingVisible && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        preparingVisible = false;
      }
      final playerFuture = nativeChannel
          .invokeMapMethod<String, dynamic>('playVideo', <String, dynamic>{
        'url': request.url,
        'headers': request.headers,
        'title': item.title,
        'startMs': startAt,
        'ratingKey': item.ratingKey,
        // The chosen file's own length: a different cut of the title must
        // not look like a stream that ended early.
        'durationMs': playbackDurationMs,
        'timelineUrl': '${api!.session!.baseUrl}/:/timeline',
        'sessionId': request.sessionId,
        'audioLanguage': selectedAudio?.languageCode ?? settings.audioLanguage,
        'subtitleLanguage': resolvedSubtitleTrackId == 'off'
            ? 'off'
            : selectedSubtitle?.languageCode ?? settings.subtitleLanguage,
        'audioTrackId': resolvedAudioTrackId ?? '',
        'audioTitle': selectedAudio?.title ?? selectedAudio?.displayLabel ?? '',
        'audioCodec': selectedAudio?.codec ?? '',
        'subtitleTrackId': resolvedSubtitleTrackId ?? '',
        'subtitleUrl': request.transcoding
            ? ''
            : api!.streamUrl(selectedSubtitle?.key) ?? '',
        'subtitleTitle':
            selectedSubtitle?.title ?? selectedSubtitle?.displayLabel ?? '',
        'subtitleCodec': selectedSubtitle?.codec ?? '',
        // Container-ordered Plex IDs let the player map its tracks back to
        // Plex streams. A transcode only carries the chosen tracks.
        'audioTrackIds': request.transcoding
            ? const <String>[]
            : versionAudio.map((track) => track.id).toList(),
        'subtitleTrackIds': request.transcoding
            ? const <String>[]
            : versionSubtitles
                .where((track) => track.key == null || track.key!.isEmpty)
                .map((track) => track.id)
                .toList(),
        'seekBackMs': settings.seekBackSeconds * 1000,
        'seekForwardMs': settings.seekForwardSeconds * 1000,
        'skipMode': settings.skipMode.name,
        'startupHardTimeoutMs': playbackStartupHardTimeoutMs(mode),
        'markers': markers
            .map((marker) => <String, dynamic>{
                  'type': marker.type,
                  'startMs': marker.startMs,
                  'endMs': marker.endMs,
                })
            .toList(),
      });
      // Cold marker requests can arrive after PlayerActivity has started.
      // The native session ID prevents a late response updating a later video.
      if (settings.skipMode != SkipMode.off && markers.isEmpty) {
        unawaited(api!.loadMarkers(item.ratingKey).then<void>((loaded) async {
          if (loaded.isEmpty || disposed) return;
          await nativeChannel.invokeMethod<bool>('updatePlaybackMarkers', {
            'sessionId': request.sessionId,
            'markers': loaded
                .map((marker) => <String, dynamic>{
                      'type': marker.type,
                      'startMs': marker.startMs,
                      'endMs': marker.endMs,
                    })
                .toList(),
          });
        }).catchError((Object _) {}));
      }
      // Telemetry must never delay the native player opening.
      unawaited(api!.reportProgress(item, startAt, 'playing',
          sessionId: request.sessionId, durationMs: playbackDurationMs));
      final raw = await playerFuture;
      final playerLines = (raw?['diagnostics'] as List<dynamic>? ?? const [])
          .map((line) => line.toString())
          .toList();
      playerLines.forEach(logs.add);
      reconnectAttempts = reconnectAttemptsFrom(playerLines);
      failureKind = raw?['failureKind']?.toString();
      renderedFrame = raw?['renderedFrame'] == true;
      final position = (raw?['positionMs'] as num?)?.toInt() ?? startAt;
      final ended = raw?['ended'] == true;
      if (renderedFrame) resumeAtMs = position;
      lastFirstFrameMs = (raw?['firstFrameMs'] as num?)?.toInt();
      lastDecoder = raw?['decoder']?.toString();
      lastVideoFormat = raw?['videoFormat']?.toString();
      lastStartupNetworkBytes = (raw?['networkBytes'] as num?)?.toInt();
      lastPlaybackFailure = failureKind;
      final inPlayerChoice = playerTrackChoice(
        raw,
        audioTracks: versionAudio,
        subtitleTracks: versionSubtitles,
      );
      if (inPlayerChoice != null) {
        final current = api!.loadPlaybackChoice(item);
        final audioChanged = raw?.containsKey('audioLanguage') == true;
        final subtitleChanged = raw?.containsKey('subtitleLanguage') == true;
        await api!.savePlaybackChoice(
            item,
            PlaybackChoice(
              mediaIndex: selectedIndex,
              audioTrackId: audioChanged
                  ? inPlayerChoice.audioTrackId
                  : current.audioTrackId,
              subtitleTrackId: subtitleChanged
                  ? inPlayerChoice.subtitleTrackId
                  : current.subtitleTrackId,
              audioLanguage: audioChanged
                  ? inPlayerChoice.audioLanguage
                  : current.audioLanguage,
              subtitleLanguage: subtitleChanged
                  ? inPlayerChoice.subtitleLanguage
                  : current.subtitleLanguage,
              audioTitle:
                  audioChanged ? inPlayerChoice.audioTitle : current.audioTitle,
              subtitleTitle: subtitleChanged
                  ? inPlayerChoice.subtitleTitle
                  : current.subtitleTitle,
              audioOrdinal: audioChanged
                  ? inPlayerChoice.audioOrdinal
                  : current.audioOrdinal,
              subtitleOrdinal: subtitleChanged
                  ? inPlayerChoice.subtitleOrdinal
                  : current.subtitleOrdinal,
              playbackMode: current.playbackMode,
            ));
        if (inPlayerChoice.audioTrackId != null) {
          retryAudioTrackId = inPlayerChoice.audioTrackId;
        }
        if (inPlayerChoice.subtitleTrackId != null) {
          retrySubtitleTrackId = inPlayerChoice.subtitleTrackId;
        }
        logs.add('Remembered in-player track choice.');
      }
      if (renderedFrame) {
        lastPlaybackProblem = null;
        _updateLocalProgress(item.ratingKey, ended ? 0 : position,
            watched: ended);
        await api!.savePlaybackMode(item, rememberedPlaybackMode(mode));
      }
      notifySafely();
      // Both calls have short total budgets, and neither holds up Retry,
      // a codec fallback or the next episode when mobile data disappears.
      unawaited(Future.wait<void>([
        if (renderedFrame)
          api!.reportProgress(item, position, ended ? 'stopped' : 'paused',
              sessionId: request.sessionId, durationMs: playbackDurationMs),
        api!.stopPlaybackSession(request),
      ]));
      activeRequest = null;
      final playerError = raw?['error']?.toString();
      if (playerError != null && playerError.isNotEmpty) {
        playerReportedFailure = true;
        throw StateError(playerError);
      }
      if (ended && settings.autoPlayNext && allowAutoNext) {
        final next = await api!.loadNextEpisode(item);
        if (next != null && context.mounted) {
          final proceed = await _showPlayNextCountdown(context, next);
          if (proceed && context.mounted) {
            logs.add('Autoplaying next episode: ${next.title}.');
            // Episodes of one show share encoding, so the mode that just
            // worked is the one to start the next episode in.
            await play(context, next, mode, startMs: 0, allowAutoNext: true);
          }
        }
      }
      unawaited(refreshHomeQuietly());
    } catch (caught) {
      if (preparingVisible && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        preparingVisible = false;
      }
      logs.add('Playback failed: ${GkuiController.compact(caught)}');
      if (context.mounted) {
        // A no-frame timeout often means the source codec/container cannot be
        // rendered by this API-19 head unit. Let it use the normal 720p then
        // 480p compatibility ladder instead of treating it as a dead server.
        final connectionFailed = failureKind == 'network' ||
            failureKind == 'http' ||
            failureKind == 'initialization';
        final fallback =
            playerReportedFailure ? playbackFallback(mode, failureKind) : null;
        if (fallback == null &&
            playerReportedFailure &&
            shouldAutoResume(
                renderedFrame: renderedFrame,
                failureKind: failureKind,
                alreadyResumed: autoResumed)) {
          final resumeAt = resumeAtMs ?? 0;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Connection dropped; resuming at ${formatPlaybackTime(resumeAt)}…'),
          ));
          await Future<void>.delayed(const Duration(seconds: 1));
          if (context.mounted) {
            await play(context, item, mode,
                mediaIndex: selectedIndex,
                audioTrackId: retryAudioTrackId,
                subtitleTrackId: retrySubtitleTrackId,
                startMs: resumeAt,
                autoResumed: true,
                checkFiles: false,
                allowAutoNext: allowAutoNext);
          }
          return;
        }
        if (fallback != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(mode == PlaybackMode.direct
                ? 'Direct play failed; retrying compatible 720p…'
                : '720p failed; retrying 480p safe mode…'),
          ));
          await Future<void>.delayed(const Duration(milliseconds: 500));
          if (context.mounted) {
            await play(context, item, fallback,
                mediaIndex: selectedIndex,
                audioTrackId: retryAudioTrackId,
                subtitleTrackId: retrySubtitleTrackId,
                startMs: resumeAtMs,
                autoResumed: autoResumed,
                checkFiles: false,
                allowAutoNext: allowAutoNext);
          }
          return;
        }
        lastPlaybackProblem = PlaybackProblem(
          media: item,
          message: GkuiController.compact(caught),
          mode: mode,
          resumeAtMs: renderedFrame ? resumeAtMs : null,
          reconnectAttempts: reconnectAttempts,
        );
        notifySafely();
        final retry = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                  title: Text(failureKind == 'missing'
                      ? 'Video file missing'
                      : connectionFailed
                          ? 'Player connection failed'
                          : failureKind == 'startup_timeout'
                              ? 'Video could not start'
                              : 'Playback failed'),
                  content: SingleChildScrollView(
                      child: Text(<String>[
                    GkuiController.compact(caught),
                    if (renderedFrame && resumeAtMs != null)
                      'Retry continues from ${formatPlaybackTime(resumeAtMs)}.',
                    'The Status screen contains the connection details.',
                  ].join('\n\n'))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Close')),
                    ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context, true),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'))
                  ],
                ));
        if (retry == true && context.mounted) {
          await play(context, item, mode,
              mediaIndex: selectedIndex,
              audioTrackId: retryAudioTrackId,
              subtitleTrackId: retrySubtitleTrackId,
              startMs: resumeAtMs,
              allowAutoNext: allowAutoNext);
        }
      }
    } finally {
      if (activeRequest != null) {
        unawaited(api!.stopPlaybackSession(activeRequest));
      }
    }
  }

  Future<bool> _showPlayNextCountdown(
      BuildContext context, PlexMedia next) async {
    final seconds = settings.playNextCountdownSeconds;
    if (seconds <= 0) return true;
    var remaining = seconds;
    Timer? timer;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          timer ??= Timer.periodic(const Duration(seconds: 1), (value) {
            remaining--;
            if (remaining <= 0) {
              value.cancel();
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            } else if (dialogContext.mounted) {
              setState(() {});
            }
          });
          return AlertDialog(
            title: const Text('Playing next episode'),
            content: Text('${next.title}\n\nStarting in $remaining seconds.'),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Play now')),
            ],
          );
        },
      ),
    );
    timer?.cancel();
    return result == true;
  }
}
