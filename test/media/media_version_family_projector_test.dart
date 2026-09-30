import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_part.dart';
import 'package:plezy/media/media_stream.dart';
import 'package:plezy/media/media_version.dart';

MediaVersion version({
  required String id,
  required int height,
  required String codec,
  bool hdr = false,
  bool dolbyVision = false,
  int bitrate = 20000,
}) => MediaVersion(
  id: id,
  height: height,
  videoResolution: height >= 2000 ? '4k' : height.toString(),
  videoCodec: codec,
  bitrate: bitrate,
  parts: [
    MediaPart(
      id: '$id-part',
      streams: [
        MediaStream(
          id: '$id-video',
          kind: MediaStreamKind.video,
          codec: codec,
          hdr: hdr,
          dolbyVision: dolbyVision,
        ),
      ],
    ),
  ],
);

void main() {
  test('prefers an existing 1080p SDR source over 4K Dolby Vision', () {
    final versions = [
      version(id: '4k', height: 2160, codec: 'hevc', hdr: true, dolbyVision: true, bitrate: 70000),
      version(id: '1080', height: 1080, codec: 'h264', bitrate: 30000),
    ];

    expect(MediaVersion.findFamilyProjectorIndex(versions), 1);
  });

  test('does not impose a bitrate ceiling on a good 1080p source', () {
    final versions = [
      version(id: '4k', height: 2160, codec: 'hevc', hdr: true),
      version(id: '1080-high', height: 1080, codec: 'h264', bitrate: 30000),
      version(id: '720-low', height: 720, codec: 'h264', bitrate: 4000),
    ];

    expect(MediaVersion.findFamilyProjectorIndex(versions), 1);
  });

  test('leaves upstream selection alone when no HD display-sized source exists', () {
    final versions = [
      version(id: '4k-sdr', height: 2160, codec: 'hevc'),
      version(id: '4k-hdr', height: 2160, codec: 'hevc', hdr: true),
    ];

    expect(MediaVersion.findFamilyProjectorIndex(versions), isNull);
  });
}
