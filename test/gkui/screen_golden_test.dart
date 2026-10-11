// Screen images at the head unit's 800x480, so layout changes are reviewed
// as pictures. Regenerate after an intended change with:
//   flutter test --update-goldens test/gkui/screen_golden_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/gkui/diagnostics.dart';
import 'package:plezy/gkui/plex_api.dart';
import 'package:plezy/main_gkui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Allows a sliver of anti-aliasing difference between machines.
class TolerantComparator extends LocalFileComparator {
  TolerantComparator(super.testFile);

  static const double tolerance = 0.005;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
        imageBytes, await getGoldenBytes(golden));
    if (result.passed || result.diffPercent <= tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

Future<void> loadFont(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}

/// The SDK root, from the flutter_tester binary running this test.
String flutterRoot() {
  final fromEnvironment = Platform.environment['FLUTTER_ROOT'];
  if (fromEnvironment != null && fromEnvironment.isNotEmpty) {
    return fromEnvironment;
  }
  var directory = File(Platform.resolvedExecutable).parent;
  while (!File('${directory.path}/bin/flutter').existsSync() &&
      directory.parent.path != directory.path) {
    directory = directory.parent;
  }
  return directory.path;
}

const session = PlexSession(
    accountToken: 'account',
    serverToken: 'server',
    serverName: 'Home PMS',
    serverId: 'machine',
    baseUrl: 'https://example.test');

const movie = PlexMedia(
  ratingKey: '9',
  key: '/library/metadata/9',
  type: 'movie',
  title: 'The Grand Budapest Hotel',
  year: 2014,
  durationMs: 99 * 60000,
  viewOffsetMs: 1834000,
  summary: 'A writer encounters the owner of an aging high-class hotel, who '
      'tells him of his early years serving as a lobby boy in the hotel\'s '
      'glorious years under an exceptional concierge.',
  versions: <PlexMediaVersion>[
    PlexMediaVersion(
        index: 0,
        partKey: '/library/parts/1/file.mkv',
        resolution: '1080',
        codec: 'h264',
        container: 'mkv',
        durationMs: 99 * 60000,
        audioTracks: <PlexTrack>[
          PlexTrack(
              id: '1',
              type: 'audio',
              languageCode: 'eng',
              language: 'English',
              codec: 'ac3',
              channels: 6,
              selected: true),
        ],
        subtitleTracks: <PlexTrack>[
          PlexTrack(
              id: '3',
              type: 'subtitle',
              languageCode: 'chi',
              language: 'Chinese',
              title: 'Traditional',
              codec: 'srt'),
        ]),
    PlexMediaVersion(
        index: 1,
        partKey: '/library/parts/2/file.mkv',
        resolution: '4k',
        codec: 'hevc',
        container: 'mkv'),
  ],
);

const short = PlexMedia(
    ratingKey: '10',
    key: '/library/metadata/10',
    type: 'movie',
    title: 'A Short Film Without Tracks',
    year: 2020,
    durationMs: 12 * 60000);

const show = PlexMedia(
    ratingKey: '5',
    key: '/library/metadata/5/children',
    type: 'show',
    title: 'Some Show',
    children: true,
    summary: 'A long running show about the people of a small town.');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(diagnosticsChannelName);

  setUpAll(() async {
    goldenFileComparator = TolerantComparator(Uri.parse(
        '${Directory.current.path}/test/gkui/screen_golden_test.dart'));
    await loadFont('PlezySans', 'assets/droid-sans.ttf');
    await loadFont('MaterialIcons',
        '${flutterRoot()}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    messenger.setMockMethodCallHandler(channel, (_) async => null);
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<GkuiController> signedIn() async {
    final controller = GkuiController();
    controller.api = await PlexApi.create(controller.logs);
    controller.api!.session = session;
    return controller;
  }

  Future<void> shoot(WidgetTester tester, Widget home, String name) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false, theme: gkuiTheme(), home: home));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  }

  testWidgets('movie details with resume, tracks and a remembered mode',
      (tester) async {
    final controller = await signedIn();
    await controller.api!.savePlaybackMode(movie, 'transcode720');
    await shoot(tester, DetailsScreen(media: movie, controller: controller),
        'details_movie');
    controller.dispose();
  });

  testWidgets('details of a title without tracks or progress', (tester) async {
    final controller = await signedIn();
    await shoot(tester, DetailsScreen(media: short, controller: controller),
        'details_plain');
    controller.dispose();
  });

  testWidgets('show seasons header', (tester) async {
    final controller = await signedIn();
    await shoot(tester, DetailsScreen(media: show, controller: controller),
        'details_show');
    controller.dispose();
  });

  testWidgets('home shell', (tester) async {
    final controller = await signedIn();
    controller.shelves = const <PlexShelf>[
      PlexShelf(title: 'Continue Watching', items: <PlexMedia>[movie, short]),
    ];
    await shoot(tester, GkuiShell(controller: controller), 'home');
    controller.dispose();
  });
}
