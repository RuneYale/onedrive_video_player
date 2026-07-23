import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onedrive_video_player/core/services/playback_progress_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late PlaybackProgressService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = const PlaybackProgressService();
  });

  group('PlaybackProgress', () {
    test('fraction is 0 when duration is unknown', () {
      final p = PlaybackProgress(
        positionSeconds: 30,
        durationSeconds: 0,
        updatedAt: DateTime(2026, 7, 9),
      );
      expect(p.fraction, 0);
    });

    test('fraction clamps to [0, 1]', () {
      expect(
        PlaybackProgress(
          positionSeconds: 150,
          durationSeconds: 100,
          updatedAt: DateTime(2026, 7, 9),
        ).fraction,
        1,
      );
      expect(
        PlaybackProgress(
          positionSeconds: -10,
          durationSeconds: 100,
          updatedAt: DateTime(2026, 7, 9),
        ).fraction,
        0,
      );
    });

    test('isFinished is true at >= 95%', () {
      expect(
        PlaybackProgress(
          positionSeconds: 95,
          durationSeconds: 100,
          updatedAt: DateTime(2026, 7, 9),
        ).isFinished,
        isTrue,
      );
      expect(
        PlaybackProgress(
          positionSeconds: 94,
          durationSeconds: 100,
          updatedAt: DateTime(2026, 7, 9),
        ).isFinished,
        isFalse,
      );
    });

    test('isFinished is false when duration is unknown', () {
      expect(
        PlaybackProgress(
          positionSeconds: 9999,
          durationSeconds: 0,
          updatedAt: DateTime(2026, 7, 9),
        ).isFinished,
        isFalse,
      );
    });

    test('toMap/fromMap round-trips', () {
      final original = PlaybackProgress(
        positionSeconds: 42.5,
        durationSeconds: 120,
        updatedAt: DateTime(2026, 7, 9, 12, 30),
      );
      final restored = PlaybackProgress.fromMap(original.toMap());
      expect(restored.positionSeconds, 42.5);
      expect(restored.durationSeconds, 120);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('toMap/fromMap round-trips parentId', () {
      final original = PlaybackProgress(
        positionSeconds: 42.5,
        durationSeconds: 120,
        updatedAt: DateTime(2026, 7, 9, 12, 30),
        name: 'Movie.mp4',
        parentId: 'folderABC',
      );
      final restored = PlaybackProgress.fromMap(original.toMap());
      expect(restored.parentId, 'folderABC');
      expect(restored.name, 'Movie.mp4');
    });

    test('fromMap without parentId yields null (backward compat)', () {
      final restored = PlaybackProgress.fromMap(<String, dynamic>{
        'position': 10,
        'duration': 100,
        'updatedAt': DateTime(2026, 7, 9).toIso8601String(),
      });
      expect(restored.parentId, isNull);
      expect(restored.name, isNull);
    });
  });

  group('PlaybackProgressService', () {
    test('get returns null when nothing is saved', () async {
      expect(await service.get('item1'), isNull);
    });

    test('save then get returns the progress', () async {
      await service.save(
        'item1',
        const Duration(seconds: 42),
        const Duration(minutes: 2),
      );
      final p = await service.get('item1');
      expect(p, isNotNull);
      expect(p!.positionSeconds, closeTo(42, 0.01));
      expect(p.durationSeconds, closeTo(120, 0.01));
    });

    test('save is a no-op for a non-positive position', () async {
      await service.save(
        'item1',
        Duration.zero,
        const Duration(minutes: 2),
      );
      expect(await service.get('item1'), isNull);
    });

    test('save updates an existing entry', () async {
      await service.save(
        'item1',
        const Duration(seconds: 10),
        const Duration(minutes: 2),
      );
      await service.save(
        'item1',
        const Duration(seconds: 50),
        const Duration(minutes: 2),
      );
      final p = await service.get('item1');
      expect(p!.positionSeconds, closeTo(50, 0.01));
    });

    test('save preserves other entries', () async {
      await service.save(
        'a',
        const Duration(seconds: 5),
        const Duration(minutes: 1),
      );
      await service.save(
        'b',
        const Duration(seconds: 15),
        const Duration(minutes: 1),
      );
      final all = await service.all();
      expect(all.length, 2);
      expect(all['a']!.positionSeconds, closeTo(5, 0.01));
      expect(all['b']!.positionSeconds, closeTo(15, 0.01));
    });

    test('clear removes an entry', () async {
      await service.save(
        'item1',
        const Duration(seconds: 30),
        const Duration(minutes: 2),
      );
      await service.clear('item1');
      expect(await service.get('item1'), isNull);
    });

    test('clear on a non-existent entry is a no-op', () async {
      await service.clear('nope');
      expect(await service.all(), isEmpty);
    });

    test('clearAll empties everything', () async {
      await service.save(
        'a',
        const Duration(seconds: 5),
        const Duration(minutes: 1),
      );
      await service.save(
        'b',
        const Duration(seconds: 10),
        const Duration(minutes: 1),
      );
      await service.clearAll();
      expect(await service.all(), isEmpty);
    });

    test('a corrupt payload is recovered as empty', () async {
      SharedPreferences.setMockInitialValues({
        'odvp_playback_progress': '{not valid json',
      });
      expect(await service.all(), isEmpty);
    });

    test('progress persists across service instances', () async {
      await service.save(
        'item1',
        const Duration(seconds: 30),
        const Duration(minutes: 2),
      );
      // A fresh service instance reads the same SharedPreferences backing.
      const other = PlaybackProgressService();
      final p = await other.get('item1');
      expect(p, isNotNull);
      expect(p!.positionSeconds, closeTo(30, 0.01));
    });

    test('save stores parentId and get returns it', () async {
      await service.save(
        'item1',
        const Duration(seconds: 30),
        const Duration(minutes: 2),
        name: 'Movie.mp4',
        parentId: 'folderABC',
      );
      final p = await service.get('item1');
      expect(p, isNotNull);
      expect(p!.parentId, 'folderABC');
    });

    test('save preserves an existing parentId when not passed', () async {
      await service.save(
        'item1',
        const Duration(seconds: 10),
        const Duration(minutes: 2),
        parentId: 'folderABC',
      );
      // A subsequent save without parentId should keep the previously stored
      // value, mirroring the name/thumbnailUrl/size preserve-on-update logic.
      await service.save(
        'item1',
        const Duration(seconds: 20),
        const Duration(minutes: 2),
      );
      final p = await service.get('item1');
      expect(p, isNotNull);
      expect(p!.parentId, 'folderABC');
      expect(p.positionSeconds, closeTo(20, 0.01));
    });

    test('clear wins over a concurrent in-flight save (no resurrection)',
        () async {
      // Seed an entry that will be cleared while another save is in flight.
      await service.save(
        'item1',
        const Duration(seconds: 30),
        const Duration(minutes: 2),
      );
      // Start a save for another item and clear item1 immediately after.
      // Mutations are serialized, so the clear must land after the save and
      // item1 must stay gone once both complete.
      final saveFuture = service.save(
        'item2',
        const Duration(seconds: 10),
        const Duration(minutes: 2),
      );
      await service.clear('item1');
      await saveFuture;
      expect(await service.get('item1'), isNull);
      expect(await service.get('item2'), isNotNull);
    });

    test('save keeps at most 200 entries, dropping the oldest by updatedAt',
        () async {
      // Seed 210 entries with strictly increasing, deterministic updatedAt
      // values so the eviction order is unambiguous.
      final seeded = <String, dynamic>{};
      for (var i = 0; i < 210; i++) {
        seeded['v${i.toString().padLeft(3, '0')}'] = <String, dynamic>{
          'position': 10,
          'duration': 100,
          'updatedAt':
              DateTime(2026, 1, 1).add(Duration(seconds: i)).toIso8601String(),
        };
      }
      SharedPreferences.setMockInitialValues({
        'odvp_playback_progress': jsonEncode(seeded),
      });
      await service.save(
        'new',
        const Duration(seconds: 5),
        const Duration(minutes: 1),
      );
      final all = await service.all();
      expect(all.length, 200);
      // The freshly saved entry and the newest seeded entries survive...
      expect(all.containsKey('new'), isTrue);
      expect(all.containsKey('v209'), isTrue);
      expect(all.containsKey('v011'), isTrue);
      // ...while the 11 oldest (v000..v010) are evicted.
      expect(all.containsKey('v000'), isFalse);
      expect(all.containsKey('v010'), isFalse);
    });

    test('saving a finished progress does not store a finished entry',
        () async {
      // 99 of 100 seconds is >= 95%, i.e. finished.
      await service.save(
        'item1',
        const Duration(seconds: 99),
        const Duration(seconds: 100),
      );
      expect(await service.get('item1'), isNull);
    });

    test('saving a finished progress removes an existing partial entry',
        () async {
      await service.save(
        'item1',
        const Duration(seconds: 50),
        const Duration(seconds: 100),
      );
      expect(await service.get('item1'), isNotNull);
      await service.save(
        'item1',
        const Duration(seconds: 97),
        const Duration(seconds: 100),
      );
      expect(await service.get('item1'), isNull);
    });
  });
}
