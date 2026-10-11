import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/gkui/diagnostics.dart';
import 'package:plezy/gkui/plex_api.dart';
import 'package:plezy/main_gkui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePlex implements HttpClientAdapter {
  FakePlex(this.respond);
  final FutureOr<Map<String, dynamic>> Function(RequestOptions) respond;
  final List<RequestOptions> requests = [];
  final Set<String> cancelled = {};

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    cancelFuture?.then((_) => cancelled.add(options.uri.path));
    final data = await respond(options);
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

const reviewSession = PlexSession(
    accountToken: 'fake-account',
    serverToken: 'old-profile',
    serverName: 'Test',
    serverId: 'server',
    baseUrl: 'https://example.test');

Map<String, dynamic> homeData(String title) => {
      'MediaContainer': {
        'Hub': [
          {
            'title': title,
            'Metadata': [
              {
                'ratingKey': '7',
                'key': '/library/metadata/7',
                'type': 'movie',
                'title': title
              }
            ]
          }
        ]
      }
    };

const audio = [
  PlexTrack(id: '11', type: 'audio', languageCode: 'en', selected: true),
  PlexTrack(id: '12', type: 'audio', languageCode: 'ja'),
];
const subtitles = [
  PlexTrack(id: '21', type: 'subtitle', languageCode: 'en', selected: true),
  PlexTrack(id: '22', type: 'subtitle', languageCode: 'zh'),
];
const version = PlexMediaVersion(
    index: 0,
    partKey: '/library/parts/7/file.mp4',
    audioTracks: audio,
    subtitleTracks: subtitles);
const episode = PlexMedia(
    ratingKey: '7',
    key: '/library/metadata/7',
    type: 'episode',
    title: 'Next',
    grandparentRatingKey: 'show',
    durationMs: 900000,
    viewOffsetMs: 120000,
    versions: [version]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(diagnosticsChannelName);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(channel, (_) async => null);
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
      'late old-profile Home, section and page responses cannot poison the cache',
      () async {
    final started = Completer<void>();
    final late = Completer<Map<String, dynamic>>();
    var oldRequests = 0;
    final adapter = FakePlex((request) {
      final token = request.headers['X-Plex-Token'];
      if (request.uri.path == '/library/onDeck')
        return {
          'MediaContainer': {'Metadata': []}
        };
      if (token == 'old-profile') {
        oldRequests++;
        if (oldRequests == 3) started.complete();
        return late.future;
      }
      return homeData('Child Home');
    });
    final api =
        await PlexApi.create(RedactingLogStore(), serverAdapter: adapter);
    api.session = reviewSession;
    final requests = Future.wait(
        [api.loadHome(), api.loadSections(), api.loadSectionPage('1')]);
    await started.future;
    api.session = const PlexSession(
        accountToken: 'fake-account',
        serverToken: 'child-profile',
        serverName: 'Test',
        serverId: 'server',
        baseUrl: 'https://example.test');
    await api.saveCurrentHomeUser(const PlexHomeUser(
        uuid: 'child',
        displayName: 'Child',
        thumb: '',
        protected: false,
        admin: false,
        guest: false));
    await api.clearContentCache();
    await api.loadHome();
    late.complete(homeData('Old Home'));
    await requests;
    expect(api.loadCachedHome().first.title, 'Child Home');
    expect(api.loadCachedSections(), isEmpty);
    expect(api.loadCachedSectionPage('1'), isNull);
    await api.saveCurrentHomeUser(const PlexHomeUser(
        uuid: 'other',
        displayName: 'Other',
        thumb: '',
        protected: false,
        admin: false,
        guest: false));
    expect(api.loadCachedHome(), isEmpty);
  });

  test('accounts sharing a server cannot restore each other\'s cached lists',
      () async {
    final api = await PlexApi.create(RedactingLogStore(),
        serverAdapter: FakePlex((request) => request.uri.path == '/hubs'
            ? homeData('Account Home')
            : {
                'MediaContainer': {'Metadata': []}
              }));
    api.session = reviewSession;
    await api.loadHome();
    expect(api.loadCachedHome(), isNotEmpty);
    api.session = const PlexSession(
        accountToken: 'different-account',
        serverToken: 'different-profile',
        serverName: 'Test',
        serverId: 'server',
        baseUrl: 'https://example.test');
    expect(api.loadCachedHome(), isEmpty);
  });

  test('background telemetry can finish after its diagnostic view is disposed',
      () {
    final logs = RedactingLogStore()..dispose();
    expect(() => logs.add('Late timeout'), returnsNormally);
    expect(logs.entries, isEmpty);
  });

  test('sign-out prevents in-flight content from recreating cached data',
      () async {
    final entered = Completer<void>();
    final late = Completer<Map<String, dynamic>>();
    final api = await PlexApi.create(RedactingLogStore(),
        serverAdapter: FakePlex((request) {
      if (request.uri.path == '/hubs') {
        entered.complete();
        return late.future;
      }
      return {
        'MediaContainer': {'Metadata': []}
      };
    }));
    api.session = reviewSession;
    final loading = api.loadHome();
    await entered.future;
    await api.signOut();
    late.complete(homeData('Old Home'));
    await loading;
    api.session = reviewSession;
    expect(api.loadCachedHome(), isEmpty);
  });

  test('cached startup preserves the next page and Load more', () async {
    final adapter = FakePlex((request) {
      switch (request.uri.path) {
        case '/library/sections':
          return {
            'MediaContainer': {
              'Directory': [
                {'key': '1', 'title': 'Movies', 'type': 'movie'}
              ]
            }
          };
        case '/library/sections/1/all':
          final start =
              int.parse('${request.queryParameters['X-Plex-Container-Start']}');
          return {
            'MediaContainer': {
              'totalSize': 4,
              'size': 2,
              'Metadata': [
                for (var key = start; key < start + 2; key++)
                  {
                    'ratingKey': '$key',
                    'key': '/library/metadata/$key',
                    'type': 'movie',
                    'title': 'Movie $key'
                  }
              ]
            }
          };
        case '/hubs':
          return homeData('Home');
        default:
          return {
            'MediaContainer': {'Metadata': []}
          };
      }
    });
    final controller = GkuiController();
    controller.api = await PlexApi.create(controller.logs,
        serverAdapter: adapter, accountAdapter: FakePlex((_) => {'users': []}));
    controller.api!.session = reviewSession;
    await controller.api!.loadSections();
    await controller.api!.loadSectionPage('1', size: 2);
    await controller.initialize();
    expect(controller.libraryNextStart, 2);
    expect(controller.libraryHasMore, isTrue);
    await controller.loadMoreLibrary();
    expect(controller.libraryItems.map((item) => item.ratingKey),
        ['0', '1', '2', '3']);
    expect(controller.libraryHasMore, isFalse);
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
  });

  test(
      'preferences override Plex defaults, while explicit and remembered choices win',
      () {
    const settings = GkuiSettings(audioLanguage: 'ja', subtitleLanguage: 'zh');
    var result = resolvePlaybackTracks(version,
        remembered: const PlaybackChoice(), settings: settings);
    expect(result.audio?.id, '12');
    expect(result.subtitleId, '22');
    result = resolvePlaybackTracks(version,
        remembered: const PlaybackChoice(),
        settings: settings,
        audioTrackId: '11',
        subtitleTrackId: '21');
    expect(result.audio?.id, '11');
    expect(result.subtitleId, '21');
    result = resolvePlaybackTracks(version,
        remembered:
            const PlaybackChoice(audioLanguage: 'en', subtitleLanguage: 'en'),
        settings: settings);
    expect(result.audio?.id, '11');
    expect(result.subtitleId, '21');
    result = resolvePlaybackTracks(version,
        remembered: const PlaybackChoice(subtitleTrackId: 'off'),
        settings: settings);
    expect(result.subtitleId, 'off');
    result = resolvePlaybackTracks(version,
        remembered: const PlaybackChoice(),
        settings: const GkuiSettings(subtitleLanguage: 'off'));
    expect(result.subtitleId, 'off');
  });

  test('old episode IDs fall back to remembered language and track order', () {
    final result = resolvePlaybackTracks(version,
        settings: const GkuiSettings(),
        remembered: const PlaybackChoice(
            audioTrackId: 'old-ja',
            audioLanguage: 'ja',
            audioOrdinal: 1,
            subtitleTrackId: 'old-zh',
            subtitleLanguage: 'zh',
            subtitleOrdinal: 1),
        audioTrackId: 'old-ja',
        subtitleTrackId: 'old-zh');
    expect(result.audio?.id, '12');
    expect(result.subtitleId, '22');
  });

  test('subtitle paths cannot change origin or embed user credentials',
      () async {
    final api = await PlexApi.create(RedactingLogStore());
    api.session = reviewSession;
    for (final path in [
      '//other.test/subtitle.srt',
      '//example.test:444/subtitle.srt',
      '//user:password@example.test/subtitle.srt',
      'https://other.test/subtitle.srt'
    ]) {
      expect(api.streamUrl(path), isNull, reason: path);
    }
    expect(api.streamUrl('/library/streams/42'),
        'https://example.test/library/streams/42');
  });

  test(
      'slow optional file check and telemetry respect a total budget and cancel requests',
      () async {
    final never = Completer<Map<String, dynamic>>();
    final adapter = FakePlex((_) => never.future);
    final api =
        await PlexApi.create(RedactingLogStore(), serverAdapter: adapter);
    api.session = reviewSession;
    final elapsed = Stopwatch()..start();
    expect(
        await api.missingFileReason('7', 0,
            budget: const Duration(milliseconds: 30)),
        isNull);
    await Future.wait([
      api.reportProgress(episode, 0, 'playing',
          budget: const Duration(milliseconds: 30)),
      api.stopPlaybackSession(api.playback(episode, transcode: true),
          budget: const Duration(milliseconds: 30)),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(elapsed.elapsedMilliseconds, lessThan(1000));
    expect(
        adapter.cancelled,
        containsAll([
          '/library/metadata/7',
          '/:/timeline',
          '/video/:/transcode/universal/stop'
        ]));
    never.complete({'MediaContainer': {}});
  });

  testWidgets(
      'start-over reaches the native player and Plex at zero, with preferred tracks',
      (tester) async {
    late BuildContext context;
    Map<dynamic, dynamic>? payload;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'playVideo') {
        payload = Map<dynamic, dynamic>.from(call.arguments as Map);
        return {'renderedFrame': true, 'positionMs': 0, 'ended': false};
      }
      return null;
    });
    final adapter = FakePlex((_) => {
          'MediaContainer': {'Metadata': []}
        });
    final controller = GkuiController();
    controller.api =
        await PlexApi.create(controller.logs, serverAdapter: adapter);
    controller.api!.session = reviewSession;
    controller.settings = const GkuiSettings(
        audioLanguage: 'ja', subtitleLanguage: 'zh', skipMode: SkipMode.off);
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    }))));
    await tester.runAsync(() async {
      await controller.play(context, episode, PlaybackMode.direct, startMs: 0);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(payload?['startMs'], 0);
    expect(payload?['audioTrackId'], '12');
    expect(payload?['subtitleTrackId'], '22');
    final timeline =
        adapter.requests.where((request) => request.uri.path == '/:/timeline');
    expect(timeline.first.queryParameters['time'], 0);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('late skip markers reach the current native playback session',
      (tester) async {
    late Completer<Map<String, dynamic>> markerResponse;
    late Completer<Map<String, dynamic>> playerDone;
    late Completer<void> playerOpened;
    late Completer<Map<dynamic, dynamic>> markersDelivered;
    String? sessionId;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'playVideo') {
        final arguments = call.arguments as Map;
        expect(arguments['markers'], isEmpty);
        sessionId = arguments['sessionId'] as String;
        playerOpened.complete();
        return playerDone.future;
      }
      if (call.method == 'updatePlaybackMarkers') {
        markersDelivered
            .complete(Map<dynamic, dynamic>.from(call.arguments as Map));
        return true;
      }
      return null;
    });
    final adapter = FakePlex((request) {
      if (request.queryParameters['includeMarkers'] == 1)
        return markerResponse.future;
      return {
        'MediaContainer': {'Metadata': []}
      };
    });
    final controller = GkuiController();
    controller.api =
        await PlexApi.create(controller.logs, serverAdapter: adapter);
    controller.api!.session = reviewSession;
    late BuildContext context;
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    }))));
    await tester.runAsync(() async {
      markerResponse = Completer<Map<String, dynamic>>();
      playerDone = Completer<Map<String, dynamic>>();
      playerOpened = Completer<void>();
      markersDelivered = Completer<Map<dynamic, dynamic>>();
      final playing = controller.play(context, episode, PlaybackMode.direct);
      await playerOpened.future.timeout(const Duration(seconds: 3),
          onTimeout: () => throw StateError(
              'Player never opened: ${controller.logs.exportText()} / ${adapter.requests.map((r) => r.queryParameters).toList()}'));
      markerResponse.complete({
        'MediaContainer': {
          'Metadata': [
            {
              'Marker': [
                {'type': 'intro', 'startTimeOffset': 0, 'endTimeOffset': 30000}
              ]
            }
          ]
        }
      });
      final delivery = await markersDelivered.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () => throw StateError(
              'No marker delivery: ${controller.logs.exportText()} / ${adapter.requests.map((r) => r.queryParameters).toList()}'));
      expect(delivery['sessionId'], sessionId);
      expect((delivery['markers'] as List).first['endMs'], 30000);
      playerDone
          .complete({'renderedFrame': false, 'positionMs': 0, 'ended': false});
      await playing;
    });
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
      'slow progress and transcode cleanup do not delay returning from the player',
      (tester) async {
    late Completer<Map<String, dynamic>> delayed;
    messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'playVideo'
            ? {'renderedFrame': true, 'positionMs': 5000, 'ended': false}
            : null);
    final adapter = FakePlex((request) {
      if (request.uri.path == '/:/timeline' ||
          request.uri.path.endsWith('/stop')) {
        return delayed.future;
      }
      return {
        'MediaContainer': {'Metadata': []}
      };
    });
    final controller = GkuiController();
    controller.api =
        await PlexApi.create(controller.logs, serverAdapter: adapter);
    controller.api!.session = reviewSession;
    controller.settings = const GkuiSettings(skipMode: SkipMode.off);
    late BuildContext context;
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    }))));
    await tester.runAsync(() async {
      delayed = Completer<Map<String, dynamic>>();
      final elapsed = Stopwatch()..start();
      await controller
          .play(context, episode, PlaybackMode.transcode720)
          .timeout(const Duration(seconds: 1));
      expect(elapsed.elapsedMilliseconds, lessThan(1000));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
          adapter.requests.any((request) => request.uri.path.endsWith('/stop')),
          isTrue);
      delayed.complete({'MediaContainer': {}});
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
