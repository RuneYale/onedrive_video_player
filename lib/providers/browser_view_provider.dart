import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BrowserViewMode { list, grid }

class BrowserViewState {
  const BrowserViewState({
    this.mode = BrowserViewMode.list,
    this.folderMode = BrowserViewMode.list,
  });

  final BrowserViewMode mode;
  final BrowserViewMode folderMode;
}

class BrowserViewNotifier extends Notifier<BrowserViewState> {
  static const _key = 'odvp_browser_view_mode';

  @override
  BrowserViewState build() {
    _load();
    return const BrowserViewState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved == 'grid') {
      state = const BrowserViewState(mode: BrowserViewMode.grid);
    }
  }

  Future<void> toggle() async {
    final newMode = state.mode == BrowserViewMode.list
        ? BrowserViewMode.grid
        : BrowserViewMode.list;
    state = BrowserViewState(mode: newMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, newMode.name);
  }
}

final browserViewProvider =
    NotifierProvider<BrowserViewNotifier, BrowserViewState>(
        BrowserViewNotifier.new);