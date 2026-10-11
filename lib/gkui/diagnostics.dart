import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const String diagnosticsChannelName = 'com.jialim.plezygkui/diagnostics';

class DeviceDiagnostics {
  const DeviceDiagnostics(this.values);

  final Map<String, String> values;

  static const MethodChannel _channel = MethodChannel(diagnosticsChannelName);

  static Future<DeviceDiagnostics> load() async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'getDiagnostics',
    );
    final values = <String, String>{};
    for (final entry in (raw ?? const <String, Object?>{}).entries) {
      values[entry.key] = entry.value?.toString() ?? 'unknown';
    }
    return DeviceDiagnostics(Map.unmodifiable(values));
  }
}

@immutable
class DiagnosticLogEntry {
  const DiagnosticLogEntry({
    required this.timestamp,
    required this.message,
  });

  final DateTime timestamp;
  final String message;

  String get line => '${timestamp.toIso8601String()}  $message';
}

class RedactingLogStore extends ChangeNotifier {
  RedactingLogStore({this.capacity = 120}) : assert(capacity > 0);

  final int capacity;
  final List<DiagnosticLogEntry> _entries = <DiagnosticLogEntry>[];
  bool _disposed = false;

  UnmodifiableListView<DiagnosticLogEntry> get entries =>
      UnmodifiableListView<DiagnosticLogEntry>(_entries);

  void add(String message, {DateTime? at}) {
    if (_disposed) return;
    _entries.add(
      DiagnosticLogEntry(
        timestamp: at ?? DateTime.now(),
        message: redactSecrets(message),
      ),
    );
    if (_entries.length > capacity) {
      _entries.removeRange(0, _entries.length - capacity);
    }
    notifyListeners();
  }

  String exportText() => _entries.map((entry) => entry.line).join('\n');

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String redactSecrets(String input) {
  var output = input;
  const keys =
      r'(?:X-Plex-Token|authToken|accessToken|Authorization|Cookie|pin)';
  // URL credentials: https://user:password@host
  output = output.replaceAllMapped(
    RegExp(r'(https?://)[^/\s:@]+:[^/\s@]+@', caseSensitive: false),
    (match) => '${match.group(1)}<redacted>@',
  );
  output = output.replaceAllMapped(
    RegExp('([?&]$keys=)[^&\\s]+', caseSensitive: false),
    (match) => '${match.group(1)}<redacted>',
  );
  // JSON: "authToken": "value"
  output = output.replaceAllMapped(
    RegExp('("$keys"\\s*:\\s*)"[^"]*"', caseSensitive: false),
    (match) => '${match.group(1)}"<redacted>"',
  );
  // Headers and maps: Authorization: Bearer value, X-Plex-Token=value
  output = output.replaceAllMapped(
    RegExp('($keys\\s*[:=]\\s*)(?:(?:Bearer|Basic)\\s+)?[^,;\\s}]+',
        caseSensitive: false),
    (match) => '${match.group(1)}<redacted>',
  );
  return output;
}

/// Diagnostics for a QR code a phone can scan: the [header] lines, then as
/// much of the newest [log] as fits in [limit] characters, all redacted. A
/// head unit has no other easy way to hand text to someone helping.
String qrDiagnostics(String header, String log, {int limit = 1200}) {
  final head = redactSecrets(header.trim());
  final room = limit - head.length - 2;
  var tail = redactSecrets(log.trim());
  if (room <= 0) return head.substring(0, limit.clamp(0, head.length));
  if (tail.length > room) {
    tail = tail.substring(tail.length - room);
    final newline = tail.indexOf('\n');
    if (newline >= 0 && newline < tail.length - 1) {
      tail = tail.substring(newline + 1);
    }
  }
  return tail.isEmpty ? head : '$head\n\n$tail';
}
