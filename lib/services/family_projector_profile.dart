import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../media/media_item.dart';
import '../mpv/mpv.dart';

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

  /// TV rails calculate their own height-relative scale. After [uiScale]
  /// rewrites 1080 logical pixels to 900, this baseline keeps their effective
  /// physical size enlarged instead of cancelling the root scale back out.
  static const double tvDesignHeight = 900;

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
  static String keyFor(MediaItem item) => item.seriesGlobalKey ?? item.globalKey;

  static void load(SharedPreferencesWithCache prefs) {
    _prefs = prefs;
    _choices.clear();
    try {
      final raw = jsonDecode(prefs.getString(_key) ?? '{}') as Map<String, dynamic>;
      for (final entry in raw.entries) {
        if (entry.value is Map) _choices[entry.key] = Map<String, Object?>.from(entry.value as Map);
      }
    } on FormatException {
      // A damaged value only loses remembered choices.
    }
  }

  /// The remembered choice: [SubtitleTrack.off], a track template to match by
  /// language/title, or null when nobody has chosen for this title yet.
  static SubtitleTrack? choiceFor(String key) {
    final value = _choices[key];
    if (value == null) return null;
    if (value['off'] == true) return SubtitleTrack.off;
    return SubtitleTrack(
      id: value['id'] as String? ?? '',
      language: value['language'] as String?,
      title: value['title'] as String?,
      codec: value['codec'] as String?,
      isForced: value['forced'] == true,
    );
  }

  /// Remembers [track] for the title; [SubtitleTrack.off] (id `no`) is Off.
  static Future<void> record(String key, SubtitleTrack track) async {
    if (!FamilyProjectorProfile.enabled) return;
    _choices.remove(key);
    _choices[key] = track.id == SubtitleTrack.off.id
        ? const {'off': true}
        : {
            'id': track.id,
            'language': track.language,
            'title': track.title,
            'codec': track.codec,
            'forced': track.isForced,
          };
    while (_choices.length > _limit) {
      _choices.remove(_choices.keys.first);
    }
    await _prefs?.setString(_key, jsonEncode(_choices));
  }

  @visibleForTesting
  static void resetForTest() {
    _prefs = null;
    _choices.clear();
  }
}
