part of '../../main_gkui.dart';

class DetailsScreen extends StatefulWidget {
  const DetailsScreen(
      {required this.media, required this.controller, super.key});
  final PlexMedia media;
  final GkuiController controller;
  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  Future<List<PlexMedia>>? children;
  Future<PlexMedia>? details;
  int? selectedMediaIndex;
  String? selectedAudioTrackId;
  String? selectedSubtitleTrackId;

  @override
  void initState() {
    super.initState();
    children = widget.media.children
        ? widget.controller.api!.loadChildren(widget.media)
        : null;
    if (children == null) {
      details = widget.controller.api!
          .loadMetadata(widget.media.ratingKey)
          .then((item) {
        final remembered = widget.controller.api!.loadPlaybackChoice(item);
        selectedMediaIndex ??= remembered.mediaIndex != null &&
                item.versions
                    .any((version) => version.index == remembered.mediaIndex)
            ? remembered.mediaIndex
            : PlexMediaVersion.preferredIndex(item.versions);
        if (widget.controller.settings.skipMode != SkipMode.off) {
          unawaited(widget.controller.api!
              .loadMarkers(item.ratingKey)
              .catchError((Object _) => const <PlexMarker>[]));
        }
        return item;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    final image = widget.controller.api!
        .imageUrl(media.art ?? media.thumb, width: 900, height: 500);
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: <Widget>[
        if (image != null)
          // Blending in the image paint avoids an extra compositing layer,
          // which Opacity would cost the head unit's GPU on every frame.
          CachedNetworkImage(
            imageUrl: image,
            httpHeaders: widget.controller.api!.imageHeaders,
            fit: BoxFit.cover,
            memCacheWidth: 900,
            color: const Color(0xD90B0B0B),
            colorBlendMode: BlendMode.srcOver,
            fadeInDuration: Duration.zero,
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        // Rebuilds after playback so Resume and progress show where the
        // video actually stopped.
        SafeArea(
          child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 20, 14),
                    child: LayoutBuilder(builder: (context, constraints) {
                      // The poster column grows with the screen, so a
                      // 1280x720 unit does not show a stamp-sized poster.
                      final side = (constraints.maxWidth * 0.2)
                          .clamp(150.0, 250.0)
                          .toDouble();
                      return children == null
                          ? FutureBuilder<PlexMedia>(
                              future: details,
                              initialData: media,
                              builder: (context, snapshot) =>
                                  playableDetails(snapshot.data ?? media, side),
                            )
                          : childrenList(media, side);
                    }),
                  )),
        ),
      ]),
    );
  }

  Widget playableDetails(PlexMedia media, double side) {
    final resumeOffset = widget.controller.resumeOffsetFor(media);
    final version = currentVersion(media);
    final rememberedMode = playbackModeFrom(
        widget.controller.api!.loadPlaybackChoice(media).playbackMode);
    final choices = <Widget>[
      if (media.versions.length > 1)
        DetailsChoiceButton(
          icon: Icons.video_settings,
          caption: 'Version',
          value: currentVersion(media)?.shortLabel ?? 'Original',
          onPressed: () => chooseVersion(media),
        ),
      if (version != null && version.audioTracks.isNotEmpty)
        DetailsChoiceButton(
          icon: Icons.audiotrack,
          caption: 'Audio',
          value: resolvedTracks(media).audio?.shortLabel ?? 'Automatic',
          onPressed: () => chooseAudioTrack(media),
        ),
      if (version != null && version.subtitleTracks.isNotEmpty)
        DetailsChoiceButton(
          icon: Icons.subtitles,
          caption: 'Subtitles',
          value: subtitleButtonLabel(media),
          onPressed: () => chooseSubtitleTrack(media),
        ),
    ];
    return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: side,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const DetailsBackButton(),
                  const SizedBox(height: 12),
                  Expanded(
                      child: DetailsPoster(
                          media: media,
                          controller: widget.controller,
                          resumeOffsetMs: resumeOffset)),
                ]),
          ),
          const SizedBox(width: 20),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                Text(media.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        height: 1.15)),
                const SizedBox(height: 4),
                Text(
                    <String>[
                      if (episodeLabel(media) case final label?
                          when label.isNotEmpty)
                        label
                      else if (media.subtitle != null)
                        media.subtitle!,
                      if (media.year != null) '${media.year}',
                      if ((version?.durationMs ?? media.durationMs) > 0)
                        formatRuntime(version?.durationMs ?? media.durationMs),
                      if (widget.controller.isWatched(media)) 'Watched',
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 17, color: Colors.white70)),
                const SizedBox(height: 10),
                // A long summary scrolls in place; the controls never move off screen.
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(media.summary ?? 'No summary available.',
                        style: const TextStyle(fontSize: 17, height: 1.35)),
                  ),
                ),
                if (choices.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Row(children: <Widget>[
                    for (var i = 0; i < choices.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: choices[i]),
                    ],
                  ]),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  height: 84,
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(
                          flex: 3,
                          child: ElevatedButton(
                            onPressed: () => playIn(media, rememberedMode),
                            child: DetailsActionLabel(
                              icon: Icons.play_arrow,
                              title: resumeOffset > 0
                                  ? 'Resume ${formatPlaybackTime(resumeOffset)}'
                                  : 'Play',
                              detail: rememberedMode == PlaybackMode.direct
                                  ? null
                                  : playbackModeLabel(rememberedMode),
                            ),
                          ),
                        ),
                        if (resumeOffset > 0) ...<Widget>[
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: OutlinedButton(
                              onPressed: () =>
                                  playIn(media, rememberedMode, startMs: 0),
                              child: const DetailsActionLabel(
                                  icon: Icons.replay, title: 'Start over'),
                            ),
                          ),
                        ],
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 84,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.zero),
                            onPressed: () =>
                                choosePlaybackMode(media, rememberedMode),
                            child: const Icon(Icons.tune,
                                size: 34, semanticLabel: 'Playback quality'),
                          ),
                        ),
                      ]),
                ),
              ])),
        ]);
  }

  Future<void> playIn(PlexMedia media, PlaybackMode mode, {int? startMs}) =>
      widget.controller.play(context, media, mode,
          mediaIndex: requestedMediaIndex(media),
          audioTrackId: selectedAudioTrackId,
          subtitleTrackId: selectedSubtitleTrackId,
          startMs: startMs);

  /// Quality choices live behind one button: the app already falls back to
  /// 720p and 480p by itself, so they are rarely needed by hand.
  Future<void> choosePlaybackMode(PlexMedia media, PlaybackMode current) async {
    final choice = await showDialog<PlaybackMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Play in'),
        children: <Widget>[
          for (final mode in PlaybackMode.values)
            RadioListTile<PlaybackMode>(
              value: mode,
              groupValue: current,
              title: Text(playbackModeLabel(mode), style: pickerText),
              subtitle: Text(switch (mode) {
                PlaybackMode.direct =>
                  'The file as it is, when this car can decode it',
                PlaybackMode.transcode720 =>
                  'Converted by the Plex server; plays most files',
                PlaybackMode.transcode480 =>
                  'Lowest data use, for weak signal or old files',
              }),
              onChanged: (value) => Navigator.pop(context, value),
            ),
        ],
      ),
    );
    if (choice != null && mounted) await playIn(media, choice);
  }

  int selectedIndex(PlexMedia media) =>
      selectedMediaIndex ?? PlexMediaVersion.preferredIndex(media.versions);

  int? requestedMediaIndex(PlexMedia media) =>
      media.versions.isEmpty ? null : selectedIndex(media);

  PlexMediaVersion? currentVersion(PlexMedia media) {
    final index = selectedIndex(media);
    for (final version in media.versions) {
      if (version.index == index) return version;
    }
    return null;
  }

  String subtitleButtonLabel(PlexMedia media) {
    final tracks = resolvedTracks(media);
    return tracks.subtitlesOff
        ? 'Off'
        : tracks.subtitle?.shortLabel ?? 'Automatic';
  }

  PlaybackTracks resolvedTracks(PlexMedia media) =>
      resolvePlaybackTracks(currentVersion(media),
          remembered: widget.controller.api!.loadPlaybackChoice(media),
          settings: widget.controller.settings,
          audioTrackId: selectedAudioTrackId,
          subtitleTrackId: selectedSubtitleTrackId);

  Future<void> chooseVersion(PlexMedia media) async {
    final choice = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose video version'),
        children: media.versions
            .map((version) => RadioListTile<int>(
                  value: version.index,
                  groupValue: selectedIndex(media),
                  title: Text(version.displayLabel, style: pickerText),
                  subtitle: version.index ==
                          PlexMediaVersion.preferredIndex(media.versions)
                      ? const Text('Recommended for this head unit')
                      : null,
                  onChanged: (value) => Navigator.pop(context, value),
                ))
            .toList(),
      ),
    );
    if (choice != null && mounted) {
      setState(() {
        selectedMediaIndex = choice;
        selectedAudioTrackId = null;
        selectedSubtitleTrackId = null;
      });
    }
  }

  Future<void> chooseAudioTrack(PlexMedia media) async {
    final tracks = currentVersion(media)?.audioTracks ?? const <PlexTrack>[];
    final resolvedId = resolvedTracks(media).audio?.id ?? '';
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose audio track'),
        children: <Widget>[
          RadioListTile<String>(
            value: '',
            groupValue: resolvedId,
            title: const Text('Automatic', style: pickerText),
            onChanged: (value) => Navigator.pop(context, value),
          ),
          ...tracks.map((track) => RadioListTile<String>(
                value: track.id,
                groupValue: resolvedId,
                title: Text(track.displayLabel, style: pickerText),
                onChanged: (value) => Navigator.pop(context, value),
              )),
        ],
      ),
    );
    if (choice != null && mounted) {
      setState(() => selectedAudioTrackId = choice.isEmpty ? null : choice);
    }
  }

  Future<void> chooseSubtitleTrack(PlexMedia media) async {
    final tracks = currentVersion(media)?.subtitleTracks ?? const <PlexTrack>[];
    final resolvedId = resolvedTracks(media).subtitleId ?? '';
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose subtitles'),
        children: <Widget>[
          RadioListTile<String>(
            value: '',
            groupValue: resolvedId,
            title: const Text('Automatic', style: pickerText),
            onChanged: (value) => Navigator.pop(context, value),
          ),
          RadioListTile<String>(
            value: 'off',
            groupValue: resolvedId,
            title: const Text('Off', style: pickerText),
            onChanged: (value) => Navigator.pop(context, value),
          ),
          ...tracks.map((track) => RadioListTile<String>(
                value: track.id,
                groupValue: resolvedId,
                title: Text(track.displayLabel, style: pickerText),
                onChanged: (value) => Navigator.pop(context, value),
              )),
        ],
      ),
    );
    if (choice != null && mounted) {
      setState(() => selectedSubtitleTrackId = choice.isEmpty ? null : choice);
    }
  }

  Widget childrenList(PlexMedia media, double side) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          SizedBox(width: side, child: const DetailsBackButton()),
          const SizedBox(width: 16),
          Expanded(
            child: Text(media.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          ),
        ]),
        if (media.summary != null && media.summary!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(media.summary!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, color: Colors.white70)),
          ),
        const SizedBox(height: 12),
        Expanded(
            child: FutureBuilder<List<PlexMedia>>(
          future: children,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                  child: Text(
                      'Could not load items: ${GkuiController.compact(snapshot.error!)}'));
            }
            final items = snapshot.data ?? const <PlexMedia>[];
            return GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 160,
                childAspectRatio: 0.62,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) =>
                  MediaCard(media: items[index], controller: widget.controller),
            );
          },
        )),
      ]);
}

/// A large back target for a touch screen used at arm's length.
/// Picker rows are read and tapped from the driver's seat.
const TextStyle pickerText = TextStyle(fontSize: 20);

class DetailsBackButton extends StatelessWidget {
  const DetailsBackButton({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 64,
        child: OutlinedButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back, size: 30),
          label: const Text('Back', style: TextStyle(fontSize: 21)),
        ),
      );
}

class DetailsPoster extends StatelessWidget {
  const DetailsPoster(
      {required this.media,
      required this.controller,
      required this.resumeOffsetMs,
      super.key});
  final PlexMedia media;
  final GkuiController controller;
  final int resumeOffsetMs;

  @override
  Widget build(BuildContext context) {
    final image = controller.api!.imageUrl(media.thumb);
    final duration = media.durationMs;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Flexible(
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: const Color(0xFF272727),
                  child: image == null
                      ? const Icon(Icons.movie_outlined,
                          size: 48, color: Colors.white38)
                      : CachedNetworkImage(
                          imageUrl: image,
                          httpHeaders: controller.api!.imageHeaders,
                          fit: BoxFit.cover,
                          memCacheWidth: 260,
                          maxWidthDiskCache: 320,
                          fadeInDuration: Duration.zero,
                          errorWidget: (_, __, ___) => const Icon(
                              Icons.broken_image_outlined,
                              size: 44,
                              color: Colors.white38),
                        ),
                ),
              ),
            ),
          ),
          if (resumeOffsetMs > 0 && duration > 0) ...<Widget>[
            const SizedBox(height: 6),
            LinearProgressIndicator(
                value: (resumeOffsetMs / duration).clamp(0.0, 1.0),
                minHeight: 4),
          ],
        ]);
  }
}

/// Track and version pickers: what is chosen is readable without opening them.
class DetailsChoiceButton extends StatelessWidget {
  const DetailsChoiceButton(
      {required this.icon,
      required this.caption,
      required this.value,
      required this.onPressed,
      super.key});
  final IconData icon;
  final String caption;
  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 72),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          alignment: Alignment.centerLeft,
        ),
        onPressed: onPressed,
        child: Row(children: <Widget>[
          Icon(icon, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(caption,
                      style:
                          const TextStyle(fontSize: 15, color: Colors.white60)),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 19, color: Colors.white)),
                ]),
          ),
        ]),
      );
}

class DetailsActionLabel extends StatelessWidget {
  const DetailsActionLabel(
      {required this.icon, required this.title, this.detail, super.key});
  final IconData icon;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 36),
          const SizedBox(width: 8),
          Flexible(
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 25, fontWeight: FontWeight.w600)),
              if (detail != null)
                Text(detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15)),
            ]),
          ),
        ],
      );
}
