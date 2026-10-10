import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/gkui/plex_api.dart';
import 'package:plezy/main_gkui.dart';

void main() {
  Map<String, dynamic> metadata(List<Map<String, dynamic>> parts) =>
      <String, dynamic>{
        'Media': <Map<String, dynamic>>[
          <String, dynamic>{'Part': parts},
        ],
      };

  test('a file Plex reports as missing is explained before playback', () {
    final reason = PlexApi.fileProblem(
        metadata(<Map<String, dynamic>>[
          <String, dynamic>{
            'key': '/library/parts/1/file.mkv',
            'exists': false
          },
        ]),
        0);
    expect(reason, contains('missing on the Plex server'));
  });

  test('an unreadable file and numeric flags are recognised', () {
    expect(
        PlexApi.fileProblem(
            metadata(<Map<String, dynamic>>[
              <String, dynamic>{
                'key': '/library/parts/1/file.mkv',
                'exists': 1,
                'accessible': 0,
              },
            ]),
            0),
        contains('cannot read'));
  });

  test('a title without any file is explained', () {
    expect(
        PlexApi.fileProblem(<String, dynamic>{}, 0), contains('no video file'));
    expect(PlexApi.fileProblem(metadata(const <Map<String, dynamic>>[]), 0),
        contains('no video file'));
  });

  test('a present file, or one Plex did not check, plays normally', () {
    expect(
        PlexApi.fileProblem(
            metadata(<Map<String, dynamic>>[
              <String, dynamic>{
                'key': '/library/parts/1/file.mkv',
                'exists': true,
                'accessible': true,
              },
            ]),
            0),
        isNull);
    expect(
        PlexApi.fileProblem(
            metadata(<Map<String, dynamic>>[
              <String, dynamic>{'key': '/library/parts/1/file.mkv'},
            ]),
            0),
        isNull);
  });

  test('a missing file never triggers the transcode fallbacks', () {
    expect(playbackFallback(PlaybackMode.direct, 'missing'), isNull);
    expect(playbackFallback(PlaybackMode.transcode720, 'missing'), isNull);
  });
}
