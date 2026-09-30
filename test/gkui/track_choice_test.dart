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

  test('remembered title distinguishes tracks sharing a language', () {
    const variants = <PlexTrack>[
      PlexTrack(
          id: '1', type: 'subtitle', languageCode: 'zho', title: 'Traditional'),
      PlexTrack(
          id: '2', type: 'subtitle', languageCode: 'zho', title: 'Simplified'),
    ];
    expect(
        trackForPreference(variants,
                language: 'zh', title: 'Simplified', ordinal: 0)
            ?.id,
        '2');
  });

  test('container position distinguishes unlabeled same-language audio', () {
    const variants = <PlexTrack>[
      PlexTrack(id: '1', type: 'audio', languageCode: 'eng'),
      PlexTrack(id: '2', type: 'audio', languageCode: 'eng'),
    ];
    expect(trackForPreference(variants, language: 'en', ordinal: 1)?.id, '2');
  });

  test('native title and ordinal are retained for the next episode', () {
    final choice = playerTrackChoice(
      <String, dynamic>{
        'subtitleTrackId': null,
        'subtitleLanguage': 'zh',
        'subtitleTitle': 'Simplified',
        'subtitleOrdinal': 1,
      },
      audioTracks: audio,
      subtitleTracks: const <PlexTrack>[
        PlexTrack(
            id: '1',
            type: 'subtitle',
            languageCode: 'zho',
            title: 'Traditional'),
        PlexTrack(
            id: '2',
            type: 'subtitle',
            languageCode: 'zho',
            title: 'Simplified'),
      ],
    );
    expect(choice?.subtitleTrackId, '2');
    expect(choice?.subtitleTitle, 'Simplified');
    expect(choice?.subtitleOrdinal, 1);
  });

  test('nothing remembered leaves the choice to Plex', () {
    const subtitles = <PlexTrack>[
      PlexTrack(id: '1', type: 'subtitle', languageCode: 'eng'),
      PlexTrack(id: '2', type: 'subtitle', languageCode: 'zho'),
    ];
    // Null means "use Plex's selected track", which for subtitles may be none.
    expect(trackForPreference(subtitles), isNull);
    expect(trackForPreference(subtitles, id: 'gone'), isNull);
    expect(trackForPreference(subtitles, id: 'gone', language: 'zh')?.id, '2');
  });

  test('subtitles default to on, preferring Plex\'s selected track', () {
    const subtitles = <PlexTrack>[
      PlexTrack(id: '1', type: 'subtitle', languageCode: 'eng'),
      PlexTrack(id: '2', type: 'subtitle', languageCode: 'zho', selected: true),
    ];
    expect(defaultSubtitleTrack(subtitles)?.id, '2');
    expect(defaultSubtitleTrack(subtitles.sublist(0, 1))?.id, '1');
    expect(defaultSubtitleTrack(const <PlexTrack>[]), isNull);
  });
}
