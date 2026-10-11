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
      appBar: AppBar(title: Text(media.title)),
      body: Stack(fit: StackFit.expand, children: <Widget>[
        if (image != null)
          Opacity(
              opacity: 0.18,
              child: CachedNetworkImage(
                imageUrl: image,
                httpHeaders: widget.controller.api!.imageHeaders,
                fit: BoxFit.cover,
                memCacheWidth: 900,
              )),
        Container(color: Colors.black.withOpacity(0.38)),
        // Rebuilds after playback so Resume and progress show where the
        // video actually stopped.
        AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => Padding(
                padding: const EdgeInsets.all(26),
                child: children == null
                    ? FutureBuilder<PlexMedia>(
                        future: details,
                        initialData: media,
                        builder: (context, snapshot) =>
                            playableDetails(snapshot.data ?? media),
                      )
                    : childrenList(media))),
      ]),
    );
  }

  Widget playableDetails(PlexMedia media) {
    final resumeOffset = widget.controller.resumeOffsetFor(media);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      SizedBox(
          width: 210,
          child: MediaCard(media: media, controller: widget.controller)),
      const SizedBox(width: 28),
      Expanded(
          child: ListView(children: <Widget>[
        Text(media.title,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
            <String>[
              if (episodeLabel(media) case final label? when label.isNotEmpty)
                label
              else if (media.subtitle != null)
                media.subtitle!,
              if (media.year != null) '${media.year}',
              if (media.durationMs > 0) formatRuntime(media.durationMs),
            ].join(' • '),
            style: const TextStyle(fontSize: 18, color: Colors.white70)),
        const SizedBox(height: 14),
        Text(media.summary ?? 'No summary available.',
            style: const TextStyle(fontSize: 17, height: 1.4)),
        const SizedBox(height: 22),
        if (media.versions.length > 1) ...<Widget>[
          OutlinedButton.icon(
            onPressed: () => chooseVersion(media),
            icon: const Icon(Icons.video_settings),
            label: Text('Version: ${selectedVersionLabel(media)}'),
          ),
          const SizedBox(height: 12),
        ],
        if (currentVersion(media) case final version?) ...<Widget>[
          Text('Selected media: ${version.displayLabel}',
              style: const TextStyle(fontSize: 16, color: Colors.white70)),
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 10, children: <Widget>[
            if (version.audioTracks.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => chooseAudioTrack(media),
                icon: const Icon(Icons.audiotrack),
                label: Text('Audio: ${selectedAudioLabel(media)}'),
              ),
            if (version.subtitleTracks.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => chooseSubtitleTrack(media),
                icon: const Icon(Icons.subtitles),
                label: Text('Subtitles: ${selectedSubtitleLabel(media)}'),
              ),
          ]),
          const SizedBox(height: 14),
        ],
        Wrap(spacing: 12, runSpacing: 12, children: <Widget>[
          ElevatedButton.icon(
            onPressed: () => widget.controller.play(
                context, media, PlaybackMode.direct,
                mediaIndex: requestedMediaIndex(media),
                audioTrackId: selectedAudioTrackId,
                subtitleTrackId: selectedSubtitleTrackId),
            icon: const Icon(Icons.play_arrow),
            label: Text(resumeOffset > 0
                ? 'Resume from ${formatPlaybackTime(resumeOffset)}'
                : 'Play'),
          ),
          if (resumeOffset > 0)
            OutlinedButton.icon(
              onPressed: () => widget.controller.play(
                  context, media, PlaybackMode.direct,
                  mediaIndex: requestedMediaIndex(media),
                  audioTrackId: selectedAudioTrackId,
                  subtitleTrackId: selectedSubtitleTrackId,
                  startMs: 0),
              icon: const Icon(Icons.replay),
              label: const Text('Play from beginning'),
            ),
          OutlinedButton(
            onPressed: () => widget.controller.play(
                context, media, PlaybackMode.transcode720,
                mediaIndex: requestedMediaIndex(media),
                audioTrackId: selectedAudioTrackId,
                subtitleTrackId: selectedSubtitleTrackId),
            child: const Text('720p compatible'),
          ),
          OutlinedButton(
            onPressed: () => widget.controller.play(
                context, media, PlaybackMode.transcode480,
                mediaIndex: requestedMediaIndex(media),
                audioTrackId: selectedAudioTrackId,
                subtitleTrackId: selectedSubtitleTrackId),
            child: const Text('480p safe mode'),
          ),
        ]),
      ])),
    ]);
  }

  int selectedIndex(PlexMedia media) =>
      selectedMediaIndex ?? PlexMediaVersion.preferredIndex(media.versions);

  int? requestedMediaIndex(PlexMedia media) =>
      media.versions.isEmpty ? null : selectedIndex(media);

  String selectedVersionLabel(PlexMedia media) {
    final index = selectedIndex(media);
    for (final version in media.versions) {
      if (version.index == index) return version.displayLabel;
    }
    return 'Original';
  }

  PlexMediaVersion? currentVersion(PlexMedia media) {
    final index = selectedIndex(media);
    for (final version in media.versions) {
      if (version.index == index) return version;
    }
    return null;
  }

  String selectedAudioLabel(PlexMedia media) {
    return resolvedTracks(media).audio?.displayLabel ?? 'Automatic';
  }

  String selectedSubtitleLabel(PlexMedia media) {
    final tracks = resolvedTracks(media);
    return tracks.subtitlesOff
        ? 'Off'
        : tracks.subtitle?.displayLabel ?? 'Automatic';
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
                  title: Text(version.displayLabel,
                      style: const TextStyle(fontSize: 18)),
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
            title: const Text('Automatic'),
            onChanged: (value) => Navigator.pop(context, value),
          ),
          ...tracks.map((track) => RadioListTile<String>(
                value: track.id,
                groupValue: resolvedId,
                title: Text(track.displayLabel),
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
            title: const Text('Automatic'),
            onChanged: (value) => Navigator.pop(context, value),
          ),
          RadioListTile<String>(
            value: 'off',
            groupValue: resolvedId,
            title: const Text('Off'),
            onChanged: (value) => Navigator.pop(context, value),
          ),
          ...tracks.map((track) => RadioListTile<String>(
                value: track.id,
                groupValue: resolvedId,
                title: Text(track.displayLabel),
                onChanged: (value) => Navigator.pop(context, value),
              )),
        ],
      ),
    );
    if (choice != null && mounted) {
      setState(() => selectedSubtitleTrackId = choice.isEmpty ? null : choice);
    }
  }

  Widget childrenList(PlexMedia media) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(media.title,
            style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w700)),
        if (media.summary != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            child: Text(media.summary!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16)),
          ),
        Expanded(
            child: FutureBuilder<List<PlexMedia>>(
          future: children,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError)
              return Center(
                  child: Text('Could not load items: ${snapshot.error}'));
            final items = snapshot.data ?? const <PlexMedia>[];
            return GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 175,
                childAspectRatio: 0.68,
                crossAxisSpacing: 16,
                mainAxisSpacing: 18,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) =>
                  MediaCard(media: items[index], controller: widget.controller),
            );
          },
        )),
      ]);
}
