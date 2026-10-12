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
  final Map<String, dynamic> Function(RequestOptions) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(respond(options)), 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

const session = PlexSession(
    accountToken: 'account',
    serverToken: 'server',
    serverName: 'Test',
    serverId: 'machine',
    baseUrl: 'https://example.test');

Map<String, dynamic> episodeJson(String key, int index,
        {bool exists = true, int duration = 1500000}) =>
    {
      'ratingKey': key,
      'key': '/library/metadata/$key',
      'type': 'episode',
      'title': 'Episode $index',
      'grandparentRatingKey': 'show',
      'parentIndex': 1,
      'index': index,
      'duration': 1440000,
      'Media': [
        {
          'duration': duration,
          'videoResolution': '1080',
          'Part': [
            {
              'id': 'p$key',
              'key': '/library/parts/$key/file.mkv',
              'exists': exists ? 1 : 0
            }
          ],
        }
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(diagnosticsChannelName);

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'gkui.playNextCountdownSeconds': 0,
      'gkui.skipMode': 'off',
    });
    messenger.setMockMethodCallHandler(channel, (_) async => null);
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<(GkuiController, FakePlex, BuildContext)> setUpPlayer(
      WidgetTester tester,
      Map<String, dynamic> Function(RequestOptions) respond) async {
    final adapter = FakePlex(respond);
    final controller = GkuiController();
    controller.api =
        await PlexApi.create(controller.logs, serverAdapter: adapter);
    controller.api!.session = session;
    controller.settings = controller.api!.loadSettings();
    late BuildContext context;
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    }))));
    return (controller, adapter, context);
  }

  Map<String, dynamic> plexResponses(RequestOptions request) {
    final path = request.uri.path;
    if (path.endsWith('/allLeaves')) {
      return {
        'MediaContainer': {
          'Metadata': [episodeJson('1', 1), episodeJson('2', 2)]
        }
      };
    }
    if (path.endsWith('/library/metadata/1')) {
      return {
        'MediaContainer': {
          'Metadata': [episodeJson('1', 1)]
        }
      };
    }
    if (path.endsWith('/library/metadata/2')) {
      return {
        'MediaContainer': {
          'Metadata': [episodeJson('2', 2)]
        }
      };
    }
    return {'MediaContainer': {}};
  }

  testWidgets('autoplay keeps the mode that worked and the title remembers it',
      (tester) async {
    final (controller, _, context) = await setUpPlayer(tester, plexResponses);
    final opened = <Map<dynamic, dynamic>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'playVideo') return null;
      final arguments = Map<dynamic, dynamic>.from(call.arguments as Map);
      opened.add(arguments);
      // The first episode ends normally; the second is closed part way.
      return opened.length == 1
          ? {'renderedFrame': true, 'positionMs': 1500000, 'ended': true}
          : {'renderedFrame': true, 'positionMs': 60000, 'ended': false};
    });
    const first = PlexMedia(
        ratingKey: '1',
        key: '/library/metadata/1',
        type: 'episode',
        title: 'Episode 1',
        grandparentRatingKey: 'show',
        parentIndex: 1,
        index: 1);
    await tester.runAsync(() async {
      final playing =
          controller.play(context, first, PlaybackMode.transcode720);
      for (var i = 0; i < 100 && opened.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
      await playing;
    });
    expect(opened, hasLength(2));
    expect(opened[1]['ratingKey'], '2');
    // A transcode URL, not the direct file, for the autoplayed episode.
    expect(opened[1]['url'], contains('/video/:/transcode/'));
    // Show-level memory: the next play of any episode starts in 720p.
    expect(
        controller.api!.loadPlaybackChoice(first).playbackMode, 'transcode720');
    // The player is told the file's own length, not the title's.
    expect(opened[0]['durationMs'], 1500000);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('one request loads the title and checks its file',
      (tester) async {
    final (controller, adapter, context) =
        await setUpPlayer(tester, plexResponses);
    messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'playVideo'
            ? {'renderedFrame': true, 'positionMs': 1000, 'ended': false}
            : null);
    const bare = PlexMedia(
        ratingKey: '1',
        key: '/library/metadata/1',
        type: 'episode',
        title: 'Episode 1');
    await tester
        .runAsync(() => controller.play(context, bare, PlaybackMode.direct));
    final metadataRequests = adapter.requests
        .where((request) => request.uri.path.endsWith('/library/metadata/1'))
        .toList();
    expect(metadataRequests, hasLength(1));
    expect(metadataRequests.single.queryParameters['checkFiles'], 1);
    // Direct play that showed video leaves no compatibility mode behind.
    expect(controller.api!.loadPlaybackChoice(bare).playbackMode, isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
      'a file reported missing by the combined request never opens the player',
      (tester) async {
    final (controller, _, context) = await setUpPlayer(tester, (request) {
      if (request.uri.path.endsWith('/library/metadata/1')) {
        return {
          'MediaContainer': {
            'Metadata': [episodeJson('1', 1, exists: false)]
          }
        };
      }
      return {'MediaContainer': {}};
    });
    var opened = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'playVideo') opened = true;
      return null;
    });
    const bare = PlexMedia(
        ratingKey: '1',
        key: '/library/metadata/1',
        type: 'episode',
        title: 'Episode 1');
    late Future<void> playing;
    await tester.runAsync(() async {
      playing = controller.play(context, bare, PlaybackMode.direct);
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find.text('Video file missing').evaluate().isNotEmpty) break;
      }
    });
    expect(find.text('Video file missing'), findsOneWidget);
    expect(opened, isFalse);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => playing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  test('stored modes map back to playback modes', () {
    expect(rememberedPlaybackMode(PlaybackMode.direct), isNull);
    expect(rememberedPlaybackMode(PlaybackMode.transcode480), 'transcode480');
    expect(playbackModeFrom('transcode720'), PlaybackMode.transcode720);
    expect(playbackModeFrom(null), PlaybackMode.direct);
    expect(playbackModeFrom('unknown'), PlaybackMode.direct);
  });

  test('resume points survive a restart until Plex records a later view',
      () async {
    final logs = RedactingLogStore();
    final api = await PlexApi.create(logs);
    api.session = session;
    await api.saveLocalProgress(
        '7',
        const LocalProgress(
            positionMs: 90000, savedAtSec: 2000, watched: true));

    final reopened = await PlexApi.create(logs);
    reopened.session = session;
    final local = reopened.loadLocalProgress()['7']!;
    expect(local.positionMs, 90000);
    expect(local.watched, isTrue);

    const before = PlexMedia(
        ratingKey: '7',
        key: 'k',
        type: 'movie',
        title: 'T',
        lastViewedAtSec: 1500);
    const after = PlexMedia(
        ratingKey: '7',
        key: 'k',
        type: 'movie',
        title: 'T',
        lastViewedAtSec: 2500);
    expect(local.supersedes(before), isTrue);
    expect(local.supersedes(after), isFalse);

    // Another account on the same server never sees them.
    reopened.session = const PlexSession(
        accountToken: 'other',
        serverToken: 'other',
        serverName: 'Test',
        serverId: 'machine',
        baseUrl: 'https://example.test');
    expect(reopened.loadLocalProgress(), isEmpty);

    reopened.session = session;
    await reopened.clearContentCache();
    expect(reopened.loadLocalProgress(), isEmpty);
    logs.dispose();
  });
}
