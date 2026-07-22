import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/subtitle_style.dart';

final subtitleStyleServiceProvider =
    Provider<SubtitleStyleService>((ref) => const SubtitleStyleService());

/// Holds the user's customizable [SubtitleStyle] in memory and persists
/// changes to [SubtitleStyleService]. The initial value is the default style;
/// the saved value is loaded asynchronously in [build].
class SubtitleStyleNotifier extends Notifier<SubtitleStyle> {
  late final SubtitleStyleService _service;

  @override
  SubtitleStyle build() {
    _service = ref.read(subtitleStyleServiceProvider);
    _load();
    return const SubtitleStyle();
  }

  Future<void> _load() async {
    final style = await _service.load();
    if (ref.mounted) state = style;
  }

  /// Replaces the current style and persists it.
  Future<void> update(SubtitleStyle style) async {
    state = style;
    await _service.save(style);
  }

  /// Resets to the default style and persists it.
  Future<void> reset() async {
    const style = SubtitleStyle();
    state = style;
    await _service.save(style);
  }
}

final subtitleStyleProvider =
    NotifierProvider<SubtitleStyleNotifier, SubtitleStyle>(
        SubtitleStyleNotifier.new);