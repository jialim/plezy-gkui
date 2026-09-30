import 'package:json_annotation/json_annotation.dart';

import '../i18n/strings.g.dart';
import '../utils/codec_utils.dart';
import '../utils/formatters.dart';
import '../utils/json_utils.dart';
import '../utils/resolution_label.dart';
import 'media_part.dart';
import 'media_stream.dart';

part 'media_version.g.dart';

/// Convert backend bitrates reported in bits-per-second to app-standard kbps.
int? bitrateKbpsFromBps(int? bps) {
  if (bps == null || bps <= 0) return null;
  return (bps / 1000).round();
}

/// A single media variant available for an item — represents one quality level
/// or transcode profile of the underlying file. An item with multiple versions
/// (e.g. 4K + 1080p re-encode) exposes one [MediaVersion] per option.
@JsonSerializable(includeIfNull: false, explicitToJson: true)
class MediaVersion {
  /// Backend-opaque version identifier.
  @JsonKey(fromJson: stringOrEmpty)
  final String id;
  @JsonKey(fromJson: flexibleInt)
  final int? width;
  @JsonKey(fromJson: flexibleInt)
  final int? height;
  final String? videoResolution; // "1080", "4k", "sd"
  final String? videoCodec;
  @JsonKey(fromJson: flexibleInt)
  final int? bitrate;
  final String? container;
  @JsonKey(fromJson: _partsFromJson, toJson: _partsToJson)
  final List<MediaPart> parts;

  /// Human-readable name for this version (e.g. "Director's Cut").
  /// Plex doesn't surface a name on `Media` entries, so this is null on the
  /// Plex path and set from `MediaSource.Name` on the Jellyfin path when the
  /// names differ across sources.
  final String? name;

  const MediaVersion({
    required this.id,
    this.width,
    this.height,
    this.videoResolution,
    this.videoCodec,
    this.bitrate,
    this.container,
    this.parts = const [],
    this.name,
  });

  factory MediaVersion.fromJson(Map<String, dynamic> json) => _$MediaVersionFromJson(json);

  Map<String, dynamic> toJson() => _$MediaVersionToJson(this);

  /// Defaults to true when file-access fields are absent. Plex only populates
  /// them when metadata is fetched with `checkFiles=1`.
  bool get isPlayable => parts.isEmpty || parts.any((part) => part.isPlayable);

  Iterable<MediaStream> get _videoStreams => parts.expand((part) => part.streams).where(
    (stream) => stream.kind == MediaStreamKind.video,
  );

  bool get isHdr => _videoStreams.any((stream) => stream.hdr);

  bool get isDolbyVision => _videoStreams.any((stream) => stream.dolbyVision);

  /// Approximate vertical resolution, for ordering versions best-first.
  ///
  /// Plex reports either a numeric height (`"1080"`) or a named tier
  /// (`"sd"`, `"4k"`) and usually both; Jellyfin reports [height] directly.
  /// Null when the backend gave neither.
  int? get resolutionHeight {
    final reported = height;
    if (reported != null && reported > 0) return reported;
    final named = (videoResolution ?? '').trim().toLowerCase();
    return switch (named) {
      '' => null,
      'sd' => 480,
      'hd' => 720,
      '4k' => 2160,
      '8k' => 4320,
      _ => int.tryParse(named),
    };
  }

  /// Display label with detailed information: "1080p H.264 MKV (8.5 Mbps)".
  /// When [name] is set, it prefixes the technical label so a user can tell
  /// "Director's Cut · 1080p H.264 MKV" apart from "Theatrical Cut · 1080p
  /// H.264 MKV" when the underlying tech specs collide.
  String get displayLabel {
    final parts = <String>[];

    if (videoResolution != null && videoResolution!.isNotEmpty) {
      parts.add(resolutionDisplayLabel(videoResolution!));
    } else if (height != null) {
      parts.add('${height}p');
    }

    if (videoCodec != null && videoCodec!.isNotEmpty) {
      parts.add(CodecUtils.formatVideoCodec(videoCodec!));
    }

    if (container != null && container!.isNotEmpty) {
      parts.add(container!.toUpperCase());
    }

    String label = parts.isNotEmpty ? parts.join(' ') : t.common.unknown;

    if (bitrate != null && bitrate! > 0) {
      label += ' (${ByteFormatter.formatBitrate(bitrate!)})';
    }

    if (name != null && name!.isNotEmpty) {
      return parts.isEmpty && (bitrate == null || bitrate! <= 0) ? name! : '$name · $label';
    }
    return label;
  }

  /// Version signature used for matching equivalent versions across episodes.
  /// Format: "resolution:codec:container".
  String get signature {
    final res = videoResolution ?? '';
    final codec = videoCodec ?? '';
    final cont = container ?? '';
    return '$res:$codec:$cont'.toLowerCase();
  }

  String get _resolutionPart => (videoResolution ?? '').toLowerCase();
  String get _codecPart => (videoCodec ?? '').toLowerCase();

  /// Find the best matching version index from a set of accepted signatures.
  ///
  /// Matching runs globally by tier: exact signature, resolution+codec, then
  /// resolution only. Within a tier, accepted-signature iteration order wins
  /// first, followed by candidate-list order. Malformed signatures are skipped.
  static int? findMatchingIndex(List<MediaVersion> versions, Set<String> acceptedSignatures) {
    if (versions.isEmpty || acceptedSignatures.isEmpty) return null;

    final accepted = <({String signature, String resolution, String codec})>[];
    for (final signature in acceptedSignatures) {
      final parts = signature.split(':');
      if (parts.length != 3) continue;
      accepted.add((signature: signature, resolution: parts[0], codec: parts[1]));
    }

    for (final target in accepted) {
      for (var i = 0; i < versions.length; i++) {
        if (versions[i].signature == target.signature) return i;
      }
    }
    for (final target in accepted) {
      for (var i = 0; i < versions.length; i++) {
        if (versions[i]._resolutionPart == target.resolution && versions[i]._codecPart == target.codec) return i;
      }
    }
    for (final target in accepted) {
      for (var i = 0; i < versions.length; i++) {
        if (versions[i]._resolutionPart == target.resolution) return i;
      }
    }

    return null;
  }

  /// Pick a sofa-friendly source for a 1080p low-memory display.
  ///
  /// This does not impose a bitrate ceiling and never invents a transcode. It
  /// only chooses among files the server already exposes, favouring a playable
  /// 1080p SDR source over 4K/HDR/Dolby Vision. If there is no HD source at or
  /// below the display resolution, the caller keeps the server's selection.
  static int? findFamilyProjectorIndex(List<MediaVersion> versions) {
    if (versions.length < 2) return null;

    final candidates = <int>[];
    for (var i = 0; i < versions.length; i++) {
      final version = versions[i];
      final height = version.resolutionHeight;
      if (version.isPlayable && height != null && height >= 720 && height <= 1200) candidates.add(i);
    }
    if (candidates.isEmpty) return null;

    int score(MediaVersion version) {
      final height = version.resolutionHeight!;
      var value = height >= 900 ? 100 : 70;
      value -= ((height - 1080).abs() / 30).round();
      if (!version.isHdr) value += 35;
      if (version.isDolbyVision) value -= 20;
      value += switch ((version.videoCodec ?? '').toLowerCase()) {
        'h264' || 'avc' => 15,
        'hevc' || 'h265' => 10,
        'vp9' => 5,
        _ => 0,
      };
      return value;
    }

    var best = candidates.first;
    var bestScore = score(versions[best]);
    for (final index in candidates.skip(1)) {
      final candidateScore = score(versions[index]);
      if (candidateScore > bestScore) {
        best = index;
        bestScore = candidateScore;
      }
    }
    return best;
  }
}

List<MediaPart> _partsFromJson(Object? raw) {
  return raw is List
      ? [
          for (final part in raw)
            if (part is Map<String, dynamic>) MediaPart.fromJson(part),
        ]
      : const [];
}

List<Map<String, dynamic>> _partsToJson(List<MediaPart> parts) => [for (final part in parts) part.toJson()];
