import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/subtitle_style.dart';

final subtitleStyleServiceProvider =
    Provider<SubtitleStyleService>((ref) => const SubtitleStyleService());

/// Holds the user's customizable [SubtitleStyle] in memory and persists
/// changes to [SubtitleStyleService]. The initial value is the default style;
/// the saved value is loaded asynchronously in [build].
class SubtitleStyleNotifier extends Notifier<SubtitleStyle> {
  late final SubtitleStyleService _service;

  /// Debounces SharedPreferences writes: slider drags emit a stream of
  /// [update] calls and persisting every tick would hammer the disk.
  Timer? _saveTimer;

  @override
  SubtitleStyle build() {
    _service = ref.read(subtitleStyleServiceProvider);
    unawaited(_load());
    ref.onDispose(() => _saveTimer?.cancel());
    return const SubtitleStyle();
  }

  Future<void> _load() async {
    final style = await _service.load();
    if (ref.mounted) state = style;
  }

  /// Applies [style] immediately (live preview in the editor and player)
  /// but debounces the persist write; the returned future completes right
  /// away since callers don't depend on the write landing.
  Future<void> update(SubtitleStyle style) {
    state = style;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_service.save(style));
    });
    return Future.value();
  }

  /// Resets to the default style and persists it immediately.
  Future<void> reset() async {
    const style = SubtitleStyle();
    state = style;
    _saveTimer?.cancel();
    await _service.save(style);
  }
}

final subtitleStyleProvider =
    NotifierProvider<SubtitleStyleNotifier, SubtitleStyle>(
        SubtitleStyleNotifier.new);