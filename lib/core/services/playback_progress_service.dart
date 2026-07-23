import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One recorded playback position for a OneDrive drive item.
///
/// Positions are stored in seconds (as [double]) so sub-second precision is
/// preserved across save/restore cycles. [durationSeconds] may be `0` when the
/// media duration is not yet known.
///
/// Metadata fields ([name], [thumbnailUrl], [size], [parentId]) are optional
/// and were added after the initial release; older persisted entries will have
/// them as `null`.
class PlaybackProgress {
  const PlaybackProgress({
    required this.positionSeconds,
    required this.durationSeconds,
    required this.updatedAt,
    this.name,
    this.thumbnailUrl,
    this.size,
    this.parentId,
  });

  final double positionSeconds;
  final double durationSeconds;
  final DateTime updatedAt;
  final String? name;
  final String? thumbnailUrl;
  final int? size;

  /// The id of the OneDrive folder containing the video. Stored so that, when
  /// a video is relaunched from the "Recent" tab (where the sibling file list
  /// is not available), the player can re-list this folder to discover
  /// external subtitle files. `null` for entries saved before this field
  /// existed.
  final String? parentId;

  /// Fraction of the media already watched, clamped to `[0, 1]`.
  /// Returns `0` when the duration is unknown.
  double get fraction {
    if (durationSeconds <= 0) return 0;
    final f = positionSeconds / durationSeconds;
    if (f < 0) return 0;
    if (f > 1) return 1;
    return f;
  }

  /// Treat the video as finished when at least 95% has been watched and the
  /// duration is known. Finished entries are cleared so the next open starts
  /// from the beginning.
  bool get isFinished => durationSeconds > 0 && fraction >= 0.95;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'position': positionSeconds,
        'duration': durationSeconds,
        'updatedAt': updatedAt.toIso8601String(),
        if (name != null) 'name': name,
        if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
        if (size != null) 'size': size,
        if (parentId != null) 'parentId': parentId,
      };

  factory PlaybackProgress.fromMap(Map<String, dynamic> map) {
    return PlaybackProgress(
      positionSeconds: (map['position'] as num).toDouble(),
      durationSeconds: (map['duration'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      name: map['name'] as String?,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      size: (map['size'] as num?)?.toInt(),
      parentId: map['parentId'] as String?,
    );
  }

  PlaybackProgress copyWith({
    double? positionSeconds,
    double? durationSeconds,
    DateTime? updatedAt,
    String? name,
    String? thumbnailUrl,
    int? size,
    String? parentId,
  }) =>
      PlaybackProgress(
        positionSeconds: positionSeconds ?? this.positionSeconds,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        updatedAt: updatedAt ?? this.updatedAt,
        name: name ?? this.name,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        size: size ?? this.size,
        parentId: parentId ?? this.parentId,
      );

  @override
  String toString() =>
      'PlaybackProgress(${positionSeconds.toStringAsFixed(1)}s/'
      '${durationSeconds.toStringAsFixed(1)}s @ $updatedAt)';
}

/// Persists per-video playback positions locally so playback can resume where
/// the user left off across app restarts.
///
/// All entries are kept under a single SharedPreferences string key as a JSON
/// map keyed by drive item id: `{ itemId: {position, duration, updatedAt, ...} }`.
/// This keeps the storage footprint tiny and makes "recently played" listings
/// trivial to add later.
class PlaybackProgressService {
  const PlaybackProgressService();

  static const _kProgressMap = 'odvp_playback_progress';

  /// Maximum number of entries kept. When a save would exceed this, the
  /// oldest entries by `updatedAt` are dropped so the stored JSON blob (which
  /// is fully decoded/re-encoded on every save) stays small.
  static const _kMaxEntries = 200;

  /// Serializes all mutating operations (save/clear/clearAll). Every mutation
  /// is an async read-modify-write of the whole map; without a queue a
  /// periodic save in flight can overwrite a concurrent clear() and resurrect
  /// a finished entry. Static (not per-instance) so that multiple service
  /// instances sharing the same SharedPreferences backing stay serialized,
  /// which also keeps the constructor const.
  static Future<void> _queue = Future.value();

  /// Chains [mutation] onto [_queue] so mutations run one at a time, in call
  /// order, and returns a future that completes when this mutation is done.
  static Future<void> _enqueue(Future<void> Function() mutation) {
    final result = _queue.then((_) => mutation());
    // Errors propagate to the caller via [result]; the queue itself must keep
    // running, so swallow them on the queue branch.
    _queue = result.catchError((Object _) {});
    return result;
  }

  Future<Map<String, PlaybackProgress>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kProgressMap);
    if (raw == null || raw.isEmpty) return <String, PlaybackProgress>{};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      // Build a *modifiable* map: Map.map() returns an unmodifiable view and
      // save()/clear() mutate the result, so copy entries explicitly.
      final result = <String, PlaybackProgress>{};
      decoded.forEach((k, v) {
        result[k] = PlaybackProgress.fromMap(v as Map<String, dynamic>);
      });
      return result;
    } catch (_) {
      // Corrupt payload: start fresh rather than crash.
      return <String, PlaybackProgress>{};
    }
  }

  Future<PlaybackProgress?> get(String itemId) async {
    final entries = await all();
    return entries[itemId];
  }

  /// Records the current playback [position] (and [duration] when known) for
  /// [itemId]. A no-op when [position] is not positive.
  ///
  /// Optional metadata ([name], [thumbnailUrl], [size], [parentId]) is saved
  /// alongside the progress so the "Recent" tab can display entries without
  /// an extra Graph API round-trip, and so external subtitles can be looked
  /// up by re-listing the parent folder when relaunching from Recent.
  Future<void> save(
    String itemId,
    Duration position,
    Duration duration, {
    String? name,
    String? thumbnailUrl,
    int? size,
    String? parentId,
  }) async {
    if (position <= Duration.zero) return;
    return _enqueue(() async {
      final entries = await all();
      final existing = entries[itemId];
      final progress = PlaybackProgress(
        positionSeconds: position.inMilliseconds / 1000.0,
        durationSeconds: duration.inMilliseconds / 1000.0,
        updatedAt: DateTime.now(),
        name: name ?? existing?.name,
        thumbnailUrl: thumbnailUrl ?? existing?.thumbnailUrl,
        size: size ?? existing?.size,
        parentId: parentId ?? existing?.parentId,
      );
      if (progress.isFinished) {
        // Do not store ~100% resume points; a finished video restarts from
        // the beginning next time.
        entries.remove(itemId);
      } else {
        entries[itemId] = progress;
      }
      _evictOldest(entries);
      await _writeAll(entries);
    });
  }

  Future<void> clear(String itemId) async {
    return _enqueue(() async {
      final entries = await all();
      if (entries.remove(itemId) != null) await _writeAll(entries);
    });
  }

  Future<void> clearAll() async {
    return _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kProgressMap);
    });
  }

  /// Trims [entries] to at most [_kMaxEntries] by dropping the oldest
  /// `updatedAt` entries. Mutates the map in place.
  static void _evictOldest(Map<String, PlaybackProgress> entries) {
    if (entries.length <= _kMaxEntries) return;
    final keys = entries.keys.toList()
      ..sort((a, b) => entries[a]!.updatedAt.compareTo(entries[b]!.updatedAt));
    for (var i = 0; i < keys.length - _kMaxEntries; i++) {
      entries.remove(keys[i]);
    }
  }

  Future<void> _writeAll(Map<String, PlaybackProgress> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      entries.map((k, v) => MapEntry(k, v.toMap())),
    );
    await prefs.setString(_kProgressMap, encoded);
  }
}