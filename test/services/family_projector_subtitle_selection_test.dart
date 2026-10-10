// Run with --dart-define=FAMILY_PROJECTOR_MODE=true (see xgimi-lite.yml).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_source_info.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/family_projector_profile.dart';
import 'package:plezy/services/track_selection_service.dart';
import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

class _StubPlayer implements Player {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TrackSelectionService _svc(List<MediaSubtitleTrack> plexSubs, {MediaItem? item}) => TrackSelectionService(
  player: _StubPlayer(),
  metadata: item ?? testMediaItem(id: 'rk1', backend: MediaBackend.plex, kind: MediaKind.movie),
  plexMediaInfo: MediaSourceInfo(videoUrl: '', audioTracks: const [], subtitleTracks: plexSubs, chapters: const []),
);

MediaItem _episode(String id, String showId) =>
    testMediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.episode, grandparentId: showId);

MediaSubtitleTrack _plexSub(int id, String language) =>
    MediaSubtitleTrack(id: id, language: language, languageCode: language, selected: false, forced: false);

void main() {
  final enabled = FamilyProjectorProfile.enabled;

  test('Chinese subtitles turn on for foreign audio when Plex selected none', () {
    final service = _svc([_plexSub(1, 'eng'), _plexSub(2, 'chi')]);
    final result = service.selectSubtitleTrack(
      const [
        SubtitleTrack(id: '1', language: 'eng'),
        SubtitleTrack(id: '2', language: 'chi', title: 'Chinese (Simplified)'),
      ],
      null,
      const AudioTrack(id: 'a1', language: 'eng'),
    );
    expect(result?.track.id, '2');
  }, skip: !enabled);

  group('remembered choice for a show', () {
    const audio = AudioTrack(id: 'a1', language: 'eng');
    const tracks = [
      SubtitleTrack(id: '1', language: 'eng', title: 'English'),
      SubtitleTrack(id: '2', language: 'chi', title: 'Chinese (Simplified)'),
      SubtitleTrack(id: '3', language: 'chi', title: 'Chinese (Traditional)'),
    ];
    final plexSubs = [_plexSub(1, 'eng'), _plexSub(2, 'chi'), _plexSub(3, 'chi')];
    late SharedPreferencesWithCache prefs;

    setUp(() async {
      resetSharedPreferencesForTest();
      prefs = await BaseSharedPreferencesService.sharedCache();
      FamilyProjectorSubtitleMemory.load(prefs);
    });
    tearDown(FamilyProjectorSubtitleMemory.resetForTest);

    test('Off chosen in one episode keeps the rest of the show off', () async {
      await FamilyProjectorSubtitleMemory.record(
        FamilyProjectorSubtitleMemory.keyFor(_episode('e1', 'show-a')),
        SubtitleTrack.off,
      );

      final nextEpisode = _svc(plexSubs, item: _episode('e2', 'show-a')).selectSubtitleTrack(tracks, null, audio);
      expect(nextEpisode?.track, SubtitleTrack.off);
      final otherShow = _svc(plexSubs, item: _episode('e9', 'show-b')).selectSubtitleTrack(tracks, null, audio);
      expect(otherShow?.track.id, '2', reason: 'other shows keep the Chinese default');
    }, skip: !enabled);

    test('a chosen track carries to later episodes and survives a restart', () async {
      await FamilyProjectorSubtitleMemory.record(
        FamilyProjectorSubtitleMemory.keyFor(_episode('e1', 'show-a')),
        const SubtitleTrack(id: '7', language: 'chi', title: 'Chinese (Traditional)'),
      );
      FamilyProjectorSubtitleMemory.load(prefs);

      final result = _svc(plexSubs, item: _episode('e2', 'show-a')).selectSubtitleTrack(tracks, null, audio);
      expect(result?.track.id, '3');
    }, skip: !enabled);

    test('a later choice replaces the earlier one', () async {
      final key = FamilyProjectorSubtitleMemory.keyFor(_episode('e1', 'show-a'));
      await FamilyProjectorSubtitleMemory.record(key, SubtitleTrack.off);
      await FamilyProjectorSubtitleMemory.record(key, const SubtitleTrack(id: '1', language: 'eng', title: 'English'));

      final result = _svc(plexSubs, item: _episode('e3', 'show-a')).selectSubtitleTrack(tracks, null, audio);
      expect(result?.track.id, '1');
    }, skip: !enabled);
  });

  test('English-only subtitles stay off, as Plex selected none', () {
    final service = _svc([_plexSub(1, 'eng')]);
    final result = service.selectSubtitleTrack(
      const [SubtitleTrack(id: '1', language: 'eng')],
      null,
      const AudioTrack(id: 'a1', language: 'eng'),
    );
    expect(result?.track, SubtitleTrack.off);
  }, skip: !enabled);

  test('Chinese audio keeps subtitles off', () {
    final service = _svc([_plexSub(2, 'chi')]);
    final result = service.selectSubtitleTrack(
      const [SubtitleTrack(id: '2', language: 'chi')],
      null,
      const AudioTrack(id: 'a1', language: 'zh-CN'),
    );
    expect(result?.track, SubtitleTrack.off);
  }, skip: !enabled);

  test('recognizes Simplified and Traditional from common title words and codes', () {
    int rank(String? language, String? title) =>
        familyProjectorSubtitleRank(SubtitleTrack(id: 'x', language: language, title: title));

    expect(rank('chi', 'Chinese (Simplified)'), greaterThan(rank('chi', 'Chinese (Traditional)')));
    expect(rank('chi', '簡體中文'), greaterThan(rank('chi', '繁體中文')));
    expect(rank('chs', null), greaterThan(rank('cht', null)));
    expect(rank('zh-Hans-CN', null), 400);
    expect(rank('chi', 'Traditional'), greaterThan(rank('chi', null)));
    expect(isFamilyProjectorChineseLanguage('yue'), isTrue);
    expect(isFamilyProjectorChineseLanguage('eng'), isFalse);
  });
}
