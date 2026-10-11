import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/update_service.dart';

import '../test_helpers/prefs.dart';

void main() {
  const lastCheckKey = 'update_last_check_time';

  setUp(resetSharedPreferencesForTest);
  PackageInfo.setMockInitialValues(
    appName: 'Plezy',
    packageName: 'com.plezy.test',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );

  group('verified cancellable APK downloads', () {
    late Directory directory;
    var installerCalls = 0;
    final bytes = utf8.encode('test APK bytes');
    Map<String, dynamic> info({String? digest}) => {
      'installUrl': 'https://github.com/jialim/plezy-gkui/releases/download/test/update.apk',
      'installFileName': 'plezy-xgimi-lite-test-armeabi-v7a.apk',
      'installSha256': digest ?? sha256.convert(bytes).toString(),
    };
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('xgimi-download');
      installerCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.plezy/xgimi_update'),
        (call) async {
          installerCalls++;
          final path = (call.arguments as Map)['path'] as String;
          expect(await File(path).readAsBytes(), bytes);
          return 'installer_started';
        },
      );
    });
    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.plezy/xgimi_update'),
        null,
      );
      await directory.delete(recursive: true);
    });
    test('only a complete checksum-matching download reaches the installer', () async {
      final client = MockClient((_) async => http.Response.bytes(bytes, 200));
      addTearDown(client.close);
      expect(
        await UpdateService.debugDownloadAndInstallXgimiUpdate(info(), client: client, directory: directory),
        'installer_started',
      );
      expect(installerCalls, 1);
    });
    test('checksum mismatch removes the partial and does not install', () async {
      final client = MockClient((_) async => http.Response.bytes(bytes, 200));
      addTearDown(client.close);
      await expectLater(
        UpdateService.debugDownloadAndInstallXgimiUpdate(
          info(digest: List.filled(64, '0').join()),
          client: client,
          directory: directory,
        ),
        throwsA(isA<XgimiUpdateException>().having((e) => e.failure, 'failure', XgimiUpdateFailure.verification)),
      );
      expect(installerCalls, 0);
      expect(await directory.list().toList(), isEmpty);
    });
    test('a dropped connection resumes with a range request', () async {
      final ranges = <String?>[];
      final client = MockClient.streaming((request, _) async {
        ranges.add(request.headers['Range']);
        if (ranges.length == 1) {
          // The first response stops after five bytes of the full file.
          final stream = StreamController<List<int>>();
          stream.add(bytes.sublist(0, 5));
          stream.close().ignore();
          return http.StreamedResponse(stream.stream, 200, contentLength: bytes.length);
        }
        return http.StreamedResponse(
          Stream.value(bytes.sublist(5)),
          206,
          contentLength: bytes.length - 5,
          headers: {'content-range': 'bytes 5-${bytes.length - 1}/${bytes.length}'},
        );
      });
      addTearDown(client.close);
      expect(
        await UpdateService.debugDownloadAndInstallXgimiUpdate(info(), client: client, directory: directory),
        'installer_started',
      );
      expect(ranges, [null, 'bytes=5-']);
      expect(installerCalls, 1);
    });
    test('a server that ignores the range restarts the file cleanly', () async {
      var calls = 0;
      final client = MockClient.streaming((request, _) async {
        calls++;
        if (calls == 1) {
          final stream = StreamController<List<int>>();
          stream.add(bytes.sublist(0, 5));
          stream.close().ignore();
          return http.StreamedResponse(stream.stream, 200, contentLength: bytes.length);
        }
        return http.StreamedResponse(Stream.value(bytes), 200, contentLength: bytes.length);
      });
      addTearDown(client.close);
      expect(
        await UpdateService.debugDownloadAndInstallXgimiUpdate(info(), client: client, directory: directory),
        'installer_started',
      );
      expect(calls, 2);
    });
    test('only network failures are resumable', () {
      expect(UpdateService.isResumableDownloadError(TimeoutException('stall')), isTrue);
      expect(UpdateService.isResumableDownloadError(const SocketException('reset')), isTrue);
      expect(UpdateService.isResumableDownloadError(http.ClientException('closed')), isTrue);
      expect(UpdateService.isResumableDownloadError(http.RequestAbortedException()), isFalse);
      expect(UpdateService.isResumableDownloadError(StateError('too large')), isFalse);
    });
    test('cancellation aborts a live response and leaves no APK', () async {
      final token = XgimiUpdateCancellation();
      final stream = StreamController<List<int>>();
      final client = MockClient.streaming((request, _) async {
        expect(request, isA<http.AbortableRequest>());
        (request as http.AbortableRequest).abortTrigger!.then((_) {
          if (!stream.isClosed) {
            stream.addError(http.RequestAbortedException(request.url));
            stream.close().ignore();
          }
        }).ignore();
        stream.add(bytes.sublist(0, 3));
        return http.StreamedResponse(stream.stream, 200, contentLength: bytes.length);
      });
      addTearDown(client.close);
      await expectLater(
        UpdateService.debugDownloadAndInstallXgimiUpdate(
          info(),
          client: client,
          directory: directory,
          cancellation: token,
          onProgress: (_) => token.cancel(),
        ),
        throwsA(isA<XgimiUpdateCancelled>()),
      );
      expect(installerCalls, 0);
      expect(await directory.list().toList(), isEmpty);
    });
  });

  test('malformed cooldown state fails open and removes the invalid value', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(lastCheckKey, 'not-an-instant');

    expect(await UpdateService.shouldCheckForUpdates(), isTrue);
    expect(prefs.getString(lastCheckKey), isNull);
  });

  test('future cooldown state fails open and removes the invalid value', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(lastCheckKey, DateTime.now().add(const Duration(days: 30)).toIso8601String());

    expect(await UpdateService.shouldCheckForUpdates(), isTrue);
    expect(prefs.getString(lastCheckKey), isNull);
  });

  test('recent valid cooldown state suppresses a duplicate check and remains stored', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final recent = DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String();
    await prefs.setString(lastCheckKey, recent);

    expect(await UpdateService.shouldCheckForUpdates(), isFalse);
    expect(prefs.getString(lastCheckKey), recent);
  });

  test('old valid cooldown state permits a new check', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final old = DateTime.now().subtract(const Duration(days: 2)).toIso8601String();
    await prefs.setString(lastCheckKey, old);

    expect(await UpdateService.shouldCheckForUpdates(), isTrue);
    expect(prefs.getString(lastCheckKey), old);
  });

  final failedResponses = <String, Future<http.Response> Function()>{
    'timeout': () async => throw TimeoutException('request timed out'),
    'non-200 response': () async => http.Response('unavailable', 503),
    'parse failure': () async => http.Response('not-json', 200, headers: {'content-type': 'application/json'}),
  };

  for (final failure in failedResponses.entries) {
    test('a manual check reports a ${failure.key} as a failure, not as the latest version', () async {
      final client = MediaServerHttpClient(client: MockClient((_) => failure.value()));
      addTearDown(client.close);

      await expectLater(
        UpdateService.debugPerformUpdateCheck(respectCooldown: false, client: client, throwOnFailure: true),
        throwsA(anything),
      );
    });
  }

  test('a manual check that finds no newer release returns null', () async {
    final client = MediaServerHttpClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'tag_name': 'v1.0.0', 'html_url': 'https://example.com', 'published_at': '2026-01-01'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(client.close);

    expect(
      await UpdateService.debugPerformUpdateCheck(respectCooldown: false, client: client, throwOnFailure: true),
      isNull,
    );
  });

  test('XGIMI release selection chooses the newest valid APK for the process ABI', () {
    final digest = List.filled(64, 'a').join();

    Map<String, Object?> release(int number, {bool draft = false, bool includeDigest = true}) => {
      'tag_name': 'xgimi-lite-v2.22.0-test$number',
      'name': 'Test $number',
      'draft': draft,
      'target_commitish': 'commit-$number',
      'html_url': 'https://example.com/test$number',
      'published_at': '2026-10-0$number',
      'body': '- armv7 APK version code: 1155\n- arm64 APK version code: 2155\n',
      'assets': [
        for (final abi in ['arm64-v8a', 'armeabi-v7a'])
          {
            'name': 'plezy-xgimi-lite-2.22.0-test$number-$abi.apk',
            'browser_download_url': 'https://example.com/test$number-$abi.apk',
            if (includeDigest) 'digest': 'sha256:$digest',
          },
      ],
    };

    final releases = [release(9, draft: true), release(8, includeDigest: false), release(6), release(7)];

    final arm64 = UpdateService.selectXgimiRelease(releases, is64Bit: true);
    expect(arm64?['testNumber'], 7);
    expect(arm64?['installFileName'], endsWith('-arm64-v8a.apk'));
    expect(arm64?['installSha256'], digest);
    expect(arm64?['installVersionCode'], 2155);

    final armv7 = UpdateService.selectXgimiRelease(releases, is64Bit: false);
    expect(armv7?['testNumber'], 7);
    expect(armv7?['installFileName'], endsWith('-armeabi-v7a.apk'));
    expect(armv7?['installVersionCode'], 1155);
  });

  test('update check requires a strictly newer code and never downgrades the version', () {
    bool newer(String version, int? code) => UpdateService.isNewerXgimiRelease(
      {'version': version, 'installVersionCode': code},
      currentVersion: '2.22.0',
      currentBuild: '1155',
    );
    expect(newer('2.22.0', 1156), isTrue);
    expect(newer('2.23.0', 1156), isTrue);
    expect(newer('2.22.0', 1155), isFalse);
    expect(newer('2.22.0', 1154), isFalse);
    expect(newer('2.21.0', 1156), isFalse);
    expect(newer('2.22.0', null), isFalse);
  });

  test('XGIMI release selection follows version bumps and prefers stable builds', () {
    final digest = List.filled(64, 'b').join();
    Map<String, Object?> release(String tag) => {
      'tag_name': tag,
      'draft': false,
      'target_commitish': 'commit-$tag',
      'html_url': 'https://example.com/$tag',
      'assets': [
        {
          'name': 'plezy-$tag-arm64-v8a.apk',
          'browser_download_url': 'https://example.com/$tag.apk',
          'digest': 'sha256:$digest',
        },
      ],
    };

    // Installed apps used to look only for 2.22.0 test tags and would never
    // have seen the 2.23.0 build.
    final bumped = UpdateService.selectXgimiRelease([
      release('xgimi-lite-v2.22.0-test9'),
      release('xgimi-lite-v2.23.0-test1'),
      release('gkui-v1.2.10'),
    ], is64Bit: true);
    expect(bumped?['tag'], 'xgimi-lite-v2.23.0-test1');
    expect(bumped?['versionLabel'], '2.23.0 Test 1');

    final stable = UpdateService.selectXgimiRelease([
      release('xgimi-lite-v2.23.0-test4'),
      release('xgimi-lite-v2.23.0'),
      release('xgimi-lite-v2.23.0-beta'),
    ], is64Bit: true);
    expect(stable?['tag'], 'xgimi-lite-v2.23.0');
    expect(stable?['versionLabel'], '2.23.0');
  });

  test('old XGIMI update downloads are removed before a new one', () async {
    final directory = await Directory.systemTemp.createTemp('xgimi-update-test');
    addTearDown(() => directory.delete(recursive: true));
    final oldApk = File('${directory.path}/plezy-xgimi-lite-2.22.0-test5-arm64-v8a.apk')..writeAsStringSync('old');
    final partial = File('${directory.path}/plezy-xgimi-lite-2.22.0-test6-arm64-v8a.apk.partial')
      ..writeAsStringSync('partial');
    final unrelated = File('${directory.path}/poster.jpg')..writeAsStringSync('keep');

    final resuming = File('${directory.path}/plezy-xgimi-lite-2.22.0-test7-arm64-v8a.apk.0123456789abcdef.partial')
      ..writeAsStringSync('resume me');

    await UpdateService.removeStaleXgimiDownloads(directory, keep: p.basename(resuming.path));

    expect(resuming.existsSync(), isTrue);
    expect(oldApk.existsSync(), isFalse);
    expect(partial.existsSync(), isFalse);
    expect(unrelated.existsSync(), isTrue);
  });

  for (final failure in failedResponses.entries) {
    test('startup ${failure.key} records cooldown before request and manual check bypasses it', () async {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      final cooldownAtRequest = <String?>[];
      var requestCount = 0;
      final client = MediaServerHttpClient(
        client: MockClient((_) async {
          requestCount++;
          cooldownAtRequest.add(prefs.getString(lastCheckKey));
          return failure.value();
        }),
      );
      addTearDown(client.close);

      expect(await UpdateService.debugPerformUpdateCheck(respectCooldown: true, client: client), isNull);
      expect(requestCount, 1);
      expect(cooldownAtRequest.single, isNotNull);
      final recordedCooldown = prefs.getString(lastCheckKey);
      expect(recordedCooldown, cooldownAtRequest.single);
      expect(DateTime.now().difference(DateTime.parse(recordedCooldown!)), lessThan(const Duration(minutes: 1)));

      expect(await UpdateService.debugPerformUpdateCheck(respectCooldown: true, client: client), isNull);
      expect(requestCount, 1, reason: 'a simulated next launch must honor the failed attempt cooldown');

      expect(await UpdateService.debugPerformUpdateCheck(respectCooldown: false, client: client), isNull);
      expect(requestCount, 2, reason: 'an explicit manual check must bypass a recent startup cooldown');
      expect(
        prefs.getString(lastCheckKey),
        recordedCooldown,
        reason: 'manual checks must not rewrite startup cooldown',
      );
    });
  }
}
