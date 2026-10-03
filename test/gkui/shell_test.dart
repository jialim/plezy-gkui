import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/gkui/diagnostics.dart';
import 'package:plezy/gkui/plex_api.dart';
import 'package:plezy/main_gkui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(diagnosticsChannelName),
      (call) async {
        if (call.method == 'checkForAppUpdate') {
          return <String, Object>{
            'available': false,
            'currentVersion': '1.2.9',
            'latestVersion': '1.2.9',
            'assetSize': 14700000,
          };
        }
        return <String, Object>{
          'app': '1.2.9 (15)',
          'android': '4.4.4 / API 19',
          'abi': 'armeabi-v7a',
          'memory class': '256 MiB',
        };
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(diagnosticsChannelName),
      null,
    );
  });

  for (final size in <Size>[
    const Size(800, 480),
    const Size(1280, 720),
  ]) {
    testWidgets(
        'sign-in shell renders at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const PlezyGkuiApp());
      await tester.pumpAndSettle();
      expect(find.text('Plezy GKUI'), findsOneWidget);
      expect(find.text('Sign in to Plex'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('diagnostics render player and device evidence', (tester) async {
    final controller = GkuiController();
    await tester.pumpWidget(MaterialApp(
      home: DiagnosticsPane(logs: controller.logs, controller: controller),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Device status'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('4.4.4 / API 19'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('4.4.4 / API 19'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('QR sign-in fits the 800x480 head unit', (tester) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = GkuiController();
    controller.api = await PlexApi.create(controller.logs);
    controller.pin = const PlexPin(id: 42, code: 'ABCD');
    await tester
        .pumpWidget(MaterialApp(home: PinScreen(controller: controller)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Code: ABCD'), findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('authenticated navigation fits the 800x480 head unit',
      (tester) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = GkuiController();
    controller.api = await PlexApi.create(controller.logs);
    controller.api!.session = const PlexSession(
      accountToken: 'account',
      serverToken: 'server',
      serverName: 'Test PMS',
      serverId: 'machine',
      baseUrl: 'https://example.test',
    );
    controller.sections = const <PlexSection>[
      PlexSection(key: '1', title: 'Movies', type: 'movie'),
    ];
    controller.selectedSection = controller.sections.first;
    controller.libraryItems = const <PlexMedia>[
      PlexMedia(
          ratingKey: '1',
          key: '/library/metadata/1',
          type: 'movie',
          title: 'Test Movie'),
    ];
    await tester
        .pumpWidget(MaterialApp(home: GkuiShell(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.text('Test PMS'), findsOneWidget);
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(find.text('Movies'), findsWidgets);
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.text('Find movies, shows and episodes'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Playback settings'), findsOneWidget);
    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();
    expect(find.text('Device status'), findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('details offer resume and start-over at 800x480', (tester) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = GkuiController();
    controller.api = await PlexApi.create(controller.logs);
    controller.api!.session = const PlexSession(
      accountToken: 'account',
      serverToken: 'server',
      serverName: 'Test PMS',
      serverId: 'machine',
      baseUrl: 'https://example.test',
    );
    const episode = PlexMedia(
      ratingKey: '7',
      key: '/library/metadata/7',
      type: 'episode',
      title: 'Pilot',
      subtitle: 'Some Show',
      parentIndex: 1,
      index: 3,
      durationMs: 45 * 60000,
      viewOffsetMs: 754000,
    );
    await tester.pumpWidget(MaterialApp(
        home: DetailsScreen(media: episode, controller: controller)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Resume from 12:34'), findsOneWidget);
    expect(find.text('Play from beginning'), findsOneWidget);
    expect(find.textContaining('S1 E3'), findsWidgets);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('settings expose USB-free signed app updates', (tester) async {
    final controller = GkuiController();
    controller.api = await PlexApi.create(controller.logs);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SettingsPane(controller: controller))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Check now'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('App updates'), findsOneWidget);
    expect(find.text('Check now'), findsOneWidget);
    expect(find.textContaining('no USB drive'), findsOneWidget);
    controller.dispose();
  });
}
