import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists the last chosen subtitle (by choice id) per video, so re-opening
/// a video automatically restores its subtitle selection.
///
/// Stored as a versioned JSON map under a single SharedPreferences key:
/// `{ videoId: {id, at} }`. Choice ids are stable by design: `off`, `auto` and
/// `external:<driveItemId>` survive restarts. `embedded:<trackId>` ids may not
/// (libmpv re-enumerates track ids on every open); a stale embedded id is
/// simply ignored when the player tries to restore it.
///
/// Damaged rows are skipped instead of discarding the whole map, and the map is
/// capped so a long-lived install can't grow it forever.
class SubtitlePreferenceService {
  const SubtitlePreferenceService();

  static const _kKey = 'odvp_subtitle_preferences';

  /// Schema version of the stored envelope.
  static const _kSchemaVersion = 1;

  /// Upper bound on remembered choices (oldest first out).
  static const _kMaxEntries = 500;

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
    final map = await _readAll();
    return _choiceIdOf(map[itemId]);
  }

  Future<void> save(String itemId, String choiceId) async {
    return _enqueue(() async {
      final map = await _readAll();
      map[itemId] = <String, dynamic>{
        'id': choiceId,
        'at': DateTime.now().toIso8601String(),
      };
      _prune(map);
      await _writeAll(map);
    });
  }

  Future<void> clear(String itemId) async {
    return _enqueue(() async {
      final map = await _readAll();
      if (map.remove(itemId) != null) await _writeAll(map);
    });
  }

  Future<void> clearAll() async {
    return _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kKey);
    });
  }

  // --- storage ------------------------------------------------------------

  Future<Map<String, dynamic>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return <String, dynamic>{};
    }
    if (decoded is! Map<String, dynamic>) return <String, dynamic>{};
    if (decoded['v'] is int && decoded['entries'] is Map) {
      return Map<String, dynamic>.from(
        decoded['entries'] as Map<String, dynamic>,
      );
    }
    // Pre-versioning layout: a flat `{ videoId: choiceId }` map.
    return decoded;
  }

  Future<void> _writeAll(Map<String, dynamic> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kKey,
      jsonEncode(<String, dynamic>{'v': _kSchemaVersion, 'entries': entries}),
    );
  }

  /// Accepts the v1 record and the legacy bare string.
  static String? _choiceIdOf(Object? value) {
    if (value is String) return value;
    if (value is Map) {
      final id = value['id'];
      if (id is String) return id;
    }
    return null;
  }

  static DateTime _savedAtOf(Object? value) {
    if (value is Map) {
      final at = value['at'];
      if (at is String) {
        final parsed = DateTime.tryParse(at);
        if (parsed != null) return parsed;
      }
    }
    // Legacy rows carry no timestamp; they are the first to go.
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static void _prune(Map<String, dynamic> entries) {
    if (entries.length <= _kMaxEntries) return;
    final byAge = entries.entries
        .map((e) => (key: e.key, at: _savedAtOf(e.value)))
        .toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    final excess = entries.length - _kMaxEntries;
    for (var i = 0; i < excess; i++) {
      entries.remove(byAge[i].key);
    }
  }
}
