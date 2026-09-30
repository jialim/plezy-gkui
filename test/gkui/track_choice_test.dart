import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/gkui/plex_api.dart';
import 'package:plezy/main_gkui.dart';

void main() {
  const audio = <PlexTrack>[
    PlexTrack(id: '9001', type: 'audio', languageCode: 'jpn'),
    PlexTrack(id: '9002', type: 'audio', languageCode: 'eng'),
  ];
  const subtitles = <PlexTrack>[
    PlexTrack(id: '9101', type: 'subtitle', languageCode: 'eng'),
    PlexTrack(id: '9102', type: 'subtitle', languageCode: 'zho'),
  ];

  test('nothing changed in the player leaves the stored choice alone', () {
    expect(
        playerTrackChoice(<String, dynamic>{'positionMs': 10},
            audioTracks: audio, subtitleTracks: subtitles),
        isNull);
  });

  test('an in-player audio switch maps back to its Plex stream', () {
    final choice = playerTrackChoice(
        <String, dynamic>{'audioTrackId': '9002', 'audioLanguage': 'en'},
        audioTracks: audio, subtitleTracks: subtitles);
    expect(choice?.audioTrackId, '9002');
    expect(choice?.audioLanguage, 'eng');
    expect(choice?.subtitleTrackId, isNull);
  });

  test('an unknown player track falls back to its language', () {
    final choice = playerTrackChoice(
        <String, dynamic>{'audioTrackId': null, 'audioLanguage': 'ja'},
        audioTracks: audio, subtitleTracks: subtitles);
    expect(choice?.audioTrackId, '9001');
  });

  test('turning CC off in the player is remembered as off', () {
    final choice = playerTrackChoice(
        <String, dynamic>{'subtitleTrackId': 'off', 'subtitleLanguage': 'off'},
        audioTracks: audio, subtitleTracks: subtitles);
    expect(choice?.subtitleTrackId, 'off');
    expect(choice?.subtitleLanguage, 'off');
  });

  test('language matching ignores 2 and 3 letter code differences', () {
    expect(trackForLanguage(subtitles, 'zh')?.id, '9102');
    expect(trackForLanguage(subtitles, 'en-US')?.id, '9101');
    expect(trackForLanguage(subtitles, 'off'), isNull);
    expect(trackForLanguage(subtitles, null), isNull);
  });
}
