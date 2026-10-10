import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/gkui/content_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gkui-cache-test');
  });

  tearDown(() => directory.delete(recursive: true));

  test('moves a 1.2.9 preferences cache into files once', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'gkui.cache.home': '{"hubs":1}',
      'gkui.serverName': 'kept',
    });
    final prefs = await SharedPreferences.getInstance();

    final cache = await ContentCache.openIn(directory, prefs);

    expect(cache.read('home'), '{"hubs":1}');
    expect(prefs.getString('gkui.cache.home'), isNull);
    expect(prefs.getString('gkui.serverName'), 'kept');
    expect(
        File('${directory.path}/home.json').readAsStringSync(), '{"hubs":1}');
  });

  test('a later write wins on disk and survives reopening', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final cache = await ContentCache.openIn(directory, prefs);

    final first = cache.write('library', 'old');
    final second = cache.write('library', 'new');
    await Future.wait(<Future<void>>[first, second]);

    final reopened = await ContentCache.openIn(directory, prefs);
    expect(reopened.read('library'), 'new');
    expect(File('${directory.path}/library.json.tmp').existsSync(), isFalse);
  });

  test('clear removes every cached document', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final cache = await ContentCache.openIn(directory, prefs);
    await cache.write('home', 'a');
    await cache.write('sections', 'b');

    await cache.clear();

    expect(cache.read('home'), isNull);
    expect(directory.listSync(), isEmpty);
  });

  test('works in memory when no directory is available', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final cache =
        await ContentCache.openIn(null, await SharedPreferences.getInstance());
    await cache.write('home', 'x');
    expect(cache.read('home'), 'x');
  });
}
