import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/gkui/diagnostics.dart';
import 'package:plezy/gkui/plex_api.dart';
import 'package:plezy/main_gkui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IdentityPlex implements HttpClientAdapter {
  final List<String> paths = [];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    paths.add(options.uri.path);
    return ResponseBody.fromString(
        jsonEncode({
          'MediaContainer': {'machineIdentifier': 'machine'}
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(diagnosticsChannelName);

  setUp(() {
    SharedPreferences.setMockInitialValues({'gkui.route': 'remote'});
    messenger.setMockMethodCallHandler(channel, (_) async => null);
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('the QR text keeps the header and the newest whole log lines', () {
    final log =
        List<String>.generate(200, (i) => 'line $i of the log').join('\n');
    final text =
        qrDiagnostics('Plezy GKUI 1.2.12\nabi: armeabi-v7a', log, limit: 300);
    expect(text.length, lessThanOrEqualTo(300));
    expect(text, startsWith('Plezy GKUI 1.2.12\nabi: armeabi-v7a\n\n'));
    expect(text, endsWith('line 199 of the log'));
    // No partial first line after the cut.
    expect(text.split('\n\n').last.split('\n').first, startsWith('line '));
  });

  test('the QR text never carries a Plex token', () {
    final text = qrDiagnostics(
        'header', 'GET https://example.test/x?X-Plex-Token=secret123');
    expect(text, isNot(contains('secret123')));
  });

  test('reconnect attempts are read from the player diagnostics', () {
    expect(
        reconnectAttemptsFrom(<String>[
          'Player: connection lost; reconnect 1 of 3',
          'Player: connection lost; reconnect 3 of 3',
          'Player failed: network',
        ]),
        3);
    expect(reconnectAttemptsFrom(<String>['Player state: ready']), 0);
  });

  test('the connection test times the saved address and names its route',
      () async {
    final adapter = IdentityPlex();
    final logs = RedactingLogStore();
    final api = await PlexApi.create(logs, serverAdapter: adapter);
    api.session = const PlexSession(
        accountToken: 'a',
        serverToken: 's',
        serverName: 'Home PMS',
        serverId: 'machine',
        baseUrl: 'https://192-168-1-2.abc.plex.direct:32400');
    final check = await api.checkConnection();
    expect(adapter.paths, <String>['/identity']);
    expect(check.switched, isFalse);
    expect(check.latencyMs, isNotNull);
    expect(check.describe(), startsWith('Remote route • '));
    expect(check.describe(), endsWith('https://….plex.direct:32400'));
    logs.dispose();
  });

  testWidgets(
      'the PIN pad tries a complete PIN and stays open when it is wrong',
      (tester) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tried = <String>[];
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showDialog<bool>(
                context: context,
                builder: (_) => PinPadDialog(
                  title: 'PIN for Owner',
                  onSubmit: (pin) async {
                    tried.add(pin);
                    return pin == '1234' ? null : 'Wrong PIN. Try again.';
                  },
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    for (final digit in '9999'.split('')) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(tried, <String>['9999']);
    expect(find.text('Wrong PIN. Try again.'), findsOneWidget);
    expect(find.text('PIN for Owner'), findsOneWidget);

    for (final digit in '1234'.split('')) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(tried.last, '1234');
    expect(find.text('PIN for Owner'), findsNothing);
    expect(result, isTrue);
    expect(tester.takeException(), isNull);
  });

  test('a rejected PIN reads as a wrong PIN', () {
    final rejected = DioException(
        requestOptions: RequestOptions(path: '/switch'),
        response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/switch'), statusCode: 401),
        type: DioExceptionType.badResponse);
    expect(profileSwitchError(rejected, 'fallback'), 'Wrong PIN. Try again.');
    expect(profileSwitchError(StateError('x'), 'fallback'), 'fallback');
  });
}
