import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../media/media_item.dart';
import '../mpv/mpv.dart';
import '../profiles/profile.dart';
import '../utils/app_logger.dart';
import 'subtitle_preference.dart';

enum ProjectorUiSize { normal, large, extraLarge }

/// Compile-time defaults for the lightweight family/projector distribution.
///
/// This is intentionally a generic profile rather than an XGIMI device-name
/// check, so the same build can serve other low-memory Android TV hardware.
/// Every setting seeded by the profile remains user-overridable.
abstract final class FamilyProjectorProfile {
  static const bool enabled = bool.fromEnvironment('FAMILY_PROJECTOR_MODE');

  /// A 1080p Android TV surface otherwise renders phone/desktop-sized 40 px
  /// controls. The dedicated projector build uses a 1.2x logical scale so
  /// those controls reach a 48 px visual target at a typical 3 m distance.
  static const double uiScale = 1.2;

  static double scaleFor(ProjectorUiSize size) => switch (size) {
    ProjectorUiSize.normal => uiScale,
    ProjectorUiSize.large => 1.4,
    ProjectorUiSize.extraLarge => 1.6,
  };

  static const double unfocusedActionOpacity = 0.85;

  static const double focusScale = 1.06;
  static const double fullCardFocusScale = 1.07;
  static const double playerControlFocusScale = 1.18;
  static const double focusBorderWidth = 4;

  static const String buildName = String.fromEnvironment('FAMILY_PROJECTOR_NAME', defaultValue: 'Plezy XGIMI Lite');

  /// The explicit start-over action is useful only when ordinary Play would
  /// resume meaningful progress. Keep it out of standard Plezy builds.
  static bool shouldOfferPlayFromBeginning(int? viewOffsetMs) => enabled && (viewOffsetMs ?? 0) > 0;
}

/// The subtitle a viewer chose for a title: a show (all its episodes) or a
/// movie. Kept on the device so the choice sticks across episodes and
/// restarts until someone changes it. Plex itself remembers only per episode
/// file, and stores Off the same way as "never chosen".
abstract final class FamilyProjectorSubtitleMemory {
  static const String _key = 'family_projector_subtitle_choices';
  static const int _limit = 500;

  static SharedPreferencesWithCache? _prefs;
  // Insertion order is recency: the oldest title is dropped first.
  static final LinkedHashMap<String, Map<String, Object?>> _choices = LinkedHashMap();

  /// One key per show for episodes and seasons, otherwise per item.
  static String keyFor(MediaItem item, {String? profileId}) =>
      jsonEncode([profileUserScope(profileId ?? ''), item.seriesGlobalKey ?? item.globalKey]);

  static void load(SharedPreferencesWithCache prefs) {
    _prefs = prefs;
    _choices.clear();
    try {
      final stored = prefs.get(_key);
      if (stored is! String) return;
      final raw = jsonDecode(stored);
      if (raw is! Map) return;
      for (final entry in raw.entries) {
        // Old unscoped entries cannot be attributed to a viewer safely.
        // They never override the new per-viewer choices.
        if (entry.key is! String || _scopeOf(entry.key as String) == null) continue;
        final value = entry.value;
        if (value is! Map || value.keys.any((key) => key is! String)) continue;
        final decoded = Map<String, Object?>.from(value);
        if (_decode(decoded) != null) _choices[entry.key as String] = decoded;
        if (_choices.length > _limit) _choices.remove(_choices.keys.first);
      }
    } on FormatException {
      // A damaged value only loses remembered choices.
    }
  }

  /// The remembered Off decision or item-independent subtitle intent.
  /// Null means this viewer has not chosen for this title yet.
  static SubtitlePreference? choiceFor(String key) {
    final value = _choices[key];
    return value == null ? null : _decode(value);
  }

  static SubtitlePreference? _decode(Map<String, Object?> value) {
    if (value['off'] == true) return const SubtitlePreference.off();
    for (final field in ['language', 'title', 'codec']) {
      if (value[field] != null && value[field] is! String) return null;
    }
    for (final field in ['forced', 'external']) {
      if (value[field] != null && value[field] is! bool) return null;
    }
    final language = value['language'] as String?;
    final title = value['title'] as String?;
    if ((language?.trim().isEmpty ?? true) && (title?.trim().isEmpty ?? true)) return null;
    return SubtitlePreference.intent(
      SubtitleIntent(
        language: language,
        title: title,
        codec: value['codec'] as String?,
        forced: value['forced'] == true,
        isExternal: value['external'] == true,
      ),
    );
  }

  static String? _scopeOf(String key) {
    try {
      final value = jsonDecode(key);
      if (value is List && value.length == 2 && value[0] is String && value[1] is String) {
        return value[0] as String;
      }
    } on FormatException {
      // Pre-profile keys and damaged entries are not part of any viewer.
    }
    return null;
  }

  static Future<void> clearForProfile(String profileId) async {
    final scope = profileUserScope(profileId);
    _choices.removeWhere((key, _) => _scopeOf(key) == scope);
    await _save();
  }

  static Future<void> _save() async {
    try {
      await _prefs?.setString(_key, jsonEncode(_choices));
    } catch (error, stackTrace) {
      // A cache write must never interrupt the actual subtitle selection.
      appLogger.w('Could not save projector subtitle choices', error: error, stackTrace: stackTrace);
    }
  }

  /// Remembers [track] for the title; [SubtitleTrack.off] (id `no`) is Off.
  static Future<void> record(String key, SubtitleTrack track) async {
    if (!FamilyProjectorProfile.enabled) return;
    _choices.remove(key);
    final intent = SubtitleIntent.fromTrack(track);
    if (track.id != SubtitleTrack.off.id && intent == null) return;
    _choices[key] = track.id == SubtitleTrack.off.id
        ? const {'off': true}
        : {
            'language': intent!.language,
            'title': intent.title,
            'codec': intent.codec,
            'forced': intent.forced,
            'external': intent.isExternal,
          };
    while (_choices.length > _limit) {
      _choices.remove(_choices.keys.first);
    }
    await _save();
  }

  @visibleForTesting
  static void resetForTest() {
    _prefs = null;
    _choices.clear();
  }
}
