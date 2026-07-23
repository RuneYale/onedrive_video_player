import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/playback_progress_service.dart';

final playbackProgressServiceProvider =
    Provider<PlaybackProgressService>((ref) => const PlaybackProgressService());

/// Holds the full `{ itemId: PlaybackProgress }` map in memory so the browser
/// can show resume indicators without an async lookup per row. Call [reload]
/// after returning from the player to pick up freshly saved positions.
class PlaybackProgressNotifier
    extends Notifier<Map<String, PlaybackProgress>> {
  late final PlaybackProgressService _service;

  @override
  Map<String, PlaybackProgress> build() {
    _service = ref.read(playbackProgressServiceProvider);
    unawaited(_load());
    return const {};
  }

  Future<void> _load() async {
    state = await _service.all();
  }

  Future<void> reload() async => _load();

  Future<void> clear(String itemId) async {
    await _service.clear(itemId);
    await _load();
  }

  Future<void> clearAll() async {
    await _service.clearAll();
    state = const {};
  }
}

final playbackProgressProvider = NotifierProvider<
    PlaybackProgressNotifier, Map<String, PlaybackProgress>>(
    PlaybackProgressNotifier.new);
