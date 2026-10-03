import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/gkui/plex_api.dart';
import 'package:plezy/main_gkui.dart';

void main() {
  test('no-frame timeout follows the full compatibility ladder', () {
    expect(playbackFallback(PlaybackMode.direct, 'startup_timeout'),
        PlaybackMode.transcode720);
    expect(playbackFallback(PlaybackMode.transcode720, 'startup_timeout'),
        PlaybackMode.transcode480);
    expect(
        playbackFallback(PlaybackMode.transcode480, 'startup_timeout'), isNull);
  });

  test('real connection failures do not request another video profile', () {
    for (final kind in <String>['network', 'http', 'initialization']) {
      expect(playbackFallback(PlaybackMode.direct, kind), isNull);
    }
  });

  test('decoder and source failures also use compatibility playback', () {
    expect(playbackFallback(PlaybackMode.direct, 'decoder'),
        PlaybackMode.transcode720);
    expect(playbackFallback(PlaybackMode.transcode720, 'source'),
        PlaybackMode.transcode480);
  });

  test('mobile startup ceilings allow slower transcodes', () {
    expect(playbackStartupHardTimeoutMs(PlaybackMode.direct), 90000);
    expect(playbackStartupHardTimeoutMs(PlaybackMode.transcode720), 120000);
    expect(playbackStartupHardTimeoutMs(PlaybackMode.transcode480), 120000);
  });

  test('startup network diagnostics use compact units', () {
    expect(formatDiagnosticBytes(512), '512 B');
    expect(formatDiagnosticBytes(1536), '1.5 KiB');
    expect(formatDiagnosticBytes(3 * 1024 * 1024), '3.0 MiB');
  });

  test('a dropped stream resumes once, only after it was playing', () {
    expect(
        shouldAutoResume(
            renderedFrame: true, failureKind: 'network', alreadyResumed: false),
        isTrue);
    expect(
        shouldAutoResume(
            renderedFrame: true, failureKind: 'http', alreadyResumed: false),
        isTrue);
    expect(
        shouldAutoResume(
            renderedFrame: true, failureKind: 'network', alreadyResumed: true),
        isFalse);
    expect(
        shouldAutoResume(
            renderedFrame: false,
            failureKind: 'network',
            alreadyResumed: false),
        isFalse);
    expect(
        shouldAutoResume(
            renderedFrame: true, failureKind: 'decoder', alreadyResumed: false),
        isFalse);
  });

  test('resume times and runtimes read like a player clock', () {
    expect(formatPlaybackTime(0), '00:00');
    expect(formatPlaybackTime(754000), '12:34');
    expect(formatPlaybackTime(3723000), '1:02:03');
    expect(formatRuntime(45 * 60000), '45 min');
    expect(formatRuntime(102 * 60000), '1 h 42 min');
    expect(formatRuntime(120 * 60000), '2 h');
  });

  test('episodes show their season and episode number', () {
    const episode = PlexMedia(
        ratingKey: '9',
        key: '/library/metadata/9',
        type: 'episode',
        title: 'Pilot',
        subtitle: 'Some Show',
        parentIndex: 1,
        index: 3);
    expect(episodeLabel(episode), 'S1 E3 · Some Show');
    const movie = PlexMedia(
        ratingKey: '1', key: '/library/metadata/1', type: 'movie', title: 'M');
    expect(episodeLabel(movie), isNull);
  });
}
