import 'dart:convert';

import 'package:dio/dio.dart';
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
}
