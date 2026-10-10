part of '../../main_gkui.dart';

class MediaShelf extends StatelessWidget {
  const MediaShelf({required this.shelf, required this.controller, super.key});
  final PlexShelf shelf;
  final GkuiController controller;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(shelf.title,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        SizedBox(
            height: 222,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: shelf.items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) => SizedBox(
                  width: 128,
                  child: MediaCard(
                      media: shelf.items[index], controller: controller)),
            )),
      ]);
}

class MediaCard extends StatelessWidget {
  const MediaCard({required this.media, required this.controller, super.key});
  final PlexMedia media;
  final GkuiController controller;
  @override
  Widget build(BuildContext context) {
    final image = controller.api!.imageUrl(media.thumb);
    final offset = controller.resumeOffsetFor(media);
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => DetailsScreen(media: media, controller: controller))),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Stack(fit: StackFit.expand, children: <Widget>[
                  Container(
                    color: const Color(0xFF272727),
                    width: double.infinity,
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
                            placeholder: (_, __) => const Center(
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            errorWidget: (_, __, ___) => const Icon(
                                Icons.broken_image_outlined,
                                size: 44,
                                color: Colors.white38),
                          ),
                  ),
                  if (controller.settings.showWatchedIndicators &&
                      controller.isWatched(media))
                    const Positioned(
                      top: 7,
                      right: 7,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: Color(0xFFE5A00D), shape: BoxShape.circle),
                        child: Padding(
                          padding: EdgeInsets.all(4),
                          child:
                              Icon(Icons.check, size: 18, color: Colors.black),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            Text(media.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15)),
            if (episodeLabel(media) case final label? when label.isNotEmpty)
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Colors.white60)),
            if (offset > 0 && media.durationMs > 0)
              LinearProgressIndicator(
                  value: (offset / media.durationMs).clamp(0.0, 1.0),
                  minHeight: 3),
          ]),
    );
  }
}
