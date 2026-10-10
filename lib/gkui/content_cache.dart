import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'diagnostics.dart';

/// Cached Plex responses (Home, libraries, the first library page), kept as
/// files instead of SharedPreferences. Android rewrites the whole preferences
/// file on every change and loads it into memory at startup, so storing
/// hundreds of KB of JSON there slowed every settings save and the 5-minute
/// Home refresh on the head unit.
///
/// Reads are synchronous from memory after [open]; writes update memory at
/// once and reach disk through a temporary file and rename, so a power cut
/// leaves either the old or the new copy, never half a file. Without a
/// directory (tests, or a failed lookup) the cache lives in memory only.
class ContentCache {
  ContentCache._(this._directory);

  /// Names of the cached documents; each was once a `gkui.cache.<name>` pref.
  static const List<String> names = <String>['home', 'sections', 'library'];

  final Directory? _directory;
  final Map<String, String> _memory = <String, String>{};
  final Map<String, Future<void>> _pendingWrites = <String, Future<void>>{};

  static Future<ContentCache> open(SharedPreferences prefs) async {
    Directory? directory;
    try {
      // An older native side answers with something else; then stay in memory.
      final path = await const MethodChannel(diagnosticsChannelName)
          .invokeMethod<Object?>('getContentCacheDirectory');
      if (path is String && path.isNotEmpty) {
        directory = Directory(path);
        await directory.create(recursive: true);
      }
    } on MissingPluginException {
      directory = null;
    } on PlatformException {
      directory = null;
    } on FileSystemException {
      directory = null;
    }
    return openIn(directory, prefs);
  }

  /// Opens the cache in [directory], moving any copy still held in
  /// SharedPreferences (Plezy GKUI 1.2.9 and earlier) into it.
  static Future<ContentCache> openIn(
      Directory? directory, SharedPreferences prefs) async {
    final cache = ContentCache._(directory);
    for (final name in names) {
      final file = cache._file(name);
      try {
        if (file != null && await file.exists()) {
          cache._memory[name] = await file.readAsString();
        }
      } on FileSystemException {
        // An unreadable copy is refreshed from Plex like a missing one.
      }
      final legacy = prefs.getString('gkui.cache.$name');
      if (legacy != null) {
        if (!cache._memory.containsKey(name)) await cache.write(name, legacy);
        await prefs.remove('gkui.cache.$name');
      }
    }
    return cache;
  }

  String? read(String name) => _memory[name];

  Future<void> write(String name, String value) {
    _memory[name] = value;
    return _queue(name, (file) async {
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(value, flush: true);
      await temporary.rename(file.path);
    });
  }

  Future<void> remove(String name) {
    _memory.remove(name);
    return _queue(name, (file) async {
      if (await file.exists()) await file.delete();
    });
  }

  Future<void> clear() => Future.wait(names.map(remove));

  File? _file(String name) =>
      _directory == null ? null : File('${_directory.path}/$name.json');

  /// Serialises disk work per document so an older write never lands last.
  Future<void> _queue(String name, Future<void> Function(File file) work) {
    final file = _file(name);
    if (file == null) return Future<void>.value();
    final previous = _pendingWrites[name] ?? Future<void>.value();
    final next = previous.then((_) => work(file)).catchError((Object _) {
      // The in-memory copy stays current; the next refresh rewrites the file.
    });
    _pendingWrites[name] = next;
    return next;
  }
}
