import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/gkui/diagnostics.dart';
import 'package:plezy/gkui/plex_api.dart';
import 'package:plezy/main_gkui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('endpoint probing', () {
    test('a fast remote address wins over a home address that never answers',
        () async {
      final home = Completer<String?>();
      final winner = await firstVerified<String>(
        <Future<String?>>[home.future, Future<String?>.value('remote')],
        isFallback: (value) => value == 'relay',
      );
      expect(winner, 'remote');
    });

    test('a relay is used only once every direct address has failed', () async {
      final direct = Completer<String?>();
      final result = firstVerified<String>(
        <Future<String?>>[Future<String?>.value('relay'), direct.future],
        isFallback: (value) => value == 'relay',
      );
      var done = false;
      unawaited(result.then((_) => done = true));
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      direct.complete(null);
      expect(await result, 'relay');
    });

    test('no working address yields null', () async {
      expect(
        await firstVerified<String>(
          <Future<String?>>[Future<String?>.value(), Future<String?>.value()],
          isFallback: (_) => false,
        ),
        isNull,
      );
      expect(
          await firstVerified<String>(const <Future<String?>>[],
              isFallback: (_) => false),
          isNull);
    });

    test('only an unanswered request counts as unreachable', () {
      final options = RequestOptions(path: '/hubs');
      expect(
          PlexApi.isUnreachable(DioException(
              requestOptions: options,
              type: DioExceptionType.connectionTimeout)),
          isTrue);
      expect(
          PlexApi.isUnreachable(DioException(
              requestOptions: options,
              response:
                  Response<dynamic>(requestOptions: options, statusCode: 500))),
          isFalse);
      expect(
          PlexApi.isUnreachable(DioException(
              requestOptions: options, type: DioExceptionType.cancel)),
          isFalse);
      expect(PlexApi.isUnreachable(StateError('x')), isFalse);
    });
  });

  group('refresh failures', () {
    final options = RequestOptions(path: '/hubs');

    test('keep cached content on screen when the server is unreachable', () {
      expect(
          keepsCachedContent(
              hasContent: true,
              error: DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionError)),
          isTrue);
    });

    test('ask for sign-in only when Plex rejects the token', () {
      expect(
          keepsCachedContent(
              hasContent: true,
              error: DioException(
                  requestOptions: options,
                  response: Response<dynamic>(
                      requestOptions: options, statusCode: 401))),
          isFalse);
    });

    test('show the error screen when nothing was cached', () {
      expect(keepsCachedContent(hasContent: false, error: StateError('x')),
          isFalse);
    });
  });

  test('remembered choices drop the least recently played title', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final api = await PlexApi.create(RedactingLogStore());
    api.session = const PlexSession(
      accountToken: 'account',
      serverToken: 'server',
      serverName: 'Test',
      serverId: 'test-id',
      baseUrl: 'https://example.test',
    );
    PlexMedia movie(int key) => PlexMedia(
          ratingKey: '$key',
          key: '/library/metadata/$key',
          type: 'movie',
          title: 'Movie $key',
        );
    for (var key = 0; key < 200; key++) {
      await api.savePlaybackChoice(
          movie(key), const PlaybackChoice(audioLanguage: 'en'));
    }
    // Replaying the oldest title keeps its choice when the store overflows.
    await api.savePlaybackChoice(
        movie(0), const PlaybackChoice(audioLanguage: 'ja'));
    await api.savePlaybackChoice(
        movie(200), const PlaybackChoice(audioLanguage: 'en'));

    expect(api.loadPlaybackChoice(movie(0)).audioLanguage, 'ja');
    expect(api.loadPlaybackChoice(movie(1)).audioLanguage, isNull);
    expect(api.loadPlaybackChoice(movie(200)).audioLanguage, 'en');
  });
}
