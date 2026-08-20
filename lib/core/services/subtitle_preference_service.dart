import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists the last chosen subtitle (by choice id) per video, so re-opening
/// a video automatically restores its subtitle selection.
///
/// Stored as a JSON map under a single SharedPreferences string key:
/// `{ videoId: choiceId }`. Choice ids are stable by design: `off`, `auto`
/// and `external:<driveItemId>` survive restarts. `embedded:<trackId>` ids
/// may not (libmpv re-enumerates track ids on every open); a stale embedded
/// id is simply ignored when the player tries to restore it.
class SubtitlePreferenceService {
  const SubtitlePreferenceService();

  static const _kKey = 'odvp_subtitle_preferences';

  /// Serializes mutating operations. Every mutation is an async read-modify-
  /// write of the whole map (same pattern as [PlaybackProgressService]); the
  /// queue keeps concurrent saves from interleaving.
  static Future<void> _queue = Future.value();

  static Future<void> _enqueue(Future<void> Function() mutation) {
    final result = _queue.then((_) => mutation());
    // Errors propagate to the caller via [result]; the queue itself must keep
    // running, so swallow them on the queue branch.
    _queue = result.catchError((Object _) {});
    return result;
  }

  /// The subtitle choice id saved for [itemId], or `null` when the user never
  /// picked one (or it was never saved).
  Future<String?> get(String itemId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded[itemId] as String?;
    } catch (_) {
      // Corrupt payload: treat as "no preference" rather than crash.
      return null;
    }
  }

  Future<void> save(String itemId, String choiceId) async {
    return _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      // Corrupt payload: treat as an empty map. The new save overwrites the
      // bad blob, so the corruption self-heals rather than blocking saves.
      final map = <String, String>{};
      if (raw != null && raw.isNotEmpty) {
        try {
          map.addAll((jsonDecode(raw) as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, v as String)));
        } catch (_) {
          // Fall through with an empty map.
        }
      }
      map[itemId] = choiceId;
      await prefs.setString(_kKey, jsonEncode(map));
    });
  }

  Future<void> clear(String itemId) async {
    return _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw == null || raw.isEmpty) return;
      try {
        final map = (jsonDecode(raw) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as String));
        if (map.remove(itemId) != null) {
          await prefs.setString(_kKey, jsonEncode(map));
        }
      } catch (_) {
        // Corrupt payload — leave it alone rather than crash.
      }
    });
  }

  Future<void> clearAll() async {
    return _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kKey);
    });
  }
}
