import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';
import '../core/models/drive_item.dart';
import '../core/services/graph_service.dart';
import 'auth_provider.dart';

final graphServiceProvider = Provider<GraphService>((ref) {
  // Reading the auth service installs its bearer-token interceptor on the
  // shared Dio instance used by the graph service below.
  ref.watch(authServiceProvider);
  return GraphService(ref.watch(dioProvider));
});

/// A folder in the navigation stack. The root uses whatever id the user
/// selected (or 'root' for the OneDrive root).
class DriveFolder {
  const DriveFolder(this.id, this.name);
  final String id;
  final String name;
}

/// One level of the navigation stack: the folder *and* the listing that was
/// shown for it.
///
/// Keeping the items in the stack is what makes "back" instant and keeps the
/// list's scroll position: the ListView is updated in place instead of being
/// replaced by a full-page spinner.
class DriveSnapshot {
  const DriveSnapshot(this.folder, {this.items = const []});

  final DriveFolder folder;
  final List<DriveItem> items;

  DriveSnapshot withItems(List<DriveItem> next) =>
      DriveSnapshot(folder, items: next);
}

class DriveState {
  const DriveState({this.stack = const [], this.loading = false, this.error});

  final List<DriveSnapshot> stack;
  final bool loading;
  final AppFailure? error;

  DriveSnapshot? get currentSnapshot => stack.isEmpty ? null : stack.last;
  DriveFolder? get current => currentSnapshot?.folder;
  List<DriveItem> get items => currentSnapshot?.items ?? const [];
  bool get canGoBack => stack.length > 1;
  bool get isReady => stack.isNotEmpty;

  /// A refresh over a folder that already has content: the list stays on
  /// screen and the UI shows a thin progress line instead of a spinner.
  bool get refreshing => loading && items.isNotEmpty;

  /// Nothing to show yet (first load of a cold folder).
  bool get coldLoading => loading && items.isEmpty;
}

class DriveNotifier extends Notifier<DriveState> {
  /// Listings kept for instant paint when a folder is re-entered (e.g.
  /// A → back → A). Bounded so a long browsing session can't grow forever.
  static const _maxCachedListings = 30;

  late final GraphService _graph;
  final Map<String, List<DriveItem>> _listings = {};
  int _loadGen = 0;

  @override
  DriveState build() {
    _graph = ref.read(graphServiceProvider);
    _loadGen = 0;
    ref.onDispose(() => _loadGen++);
    return const DriveState();
  }

  /// Sets the root folder and loads it, discarding any previous session state.
  Future<void> setRoot(DriveFolder root) async {
    _listings.clear();
    await _enter([DriveSnapshot(root)]);
  }

  /// Re-lists the current folder, keeping its rows on screen meanwhile.
  Future<void> refresh() async {
    if (state.stack.isEmpty) return;
    await _enter(state.stack);
  }

  /// Opens [item] as a folder. The cached listing (if any) paints immediately
  /// while the request revalidates it.
  Future<void> openFolder(DriveItem item) async {
    final folder = DriveFolder(item.id, item.name);
    final cached = _listings[folder.id];
    final snapshot = DriveSnapshot(folder, items: cached ?? const []);
    await _enter([...state.stack, snapshot]);
  }

  /// Goes up one folder. The parent's listing is already in the stack, so the
  /// rows reappear instantly at the same scroll position.
  Future<void> goBack() async {
    if (!state.canGoBack) return;
    final next = [...state.stack]..removeLast();
    await _enter(next);
  }

  /// Pushes [stack] and loads its last entry. Items already present in the
  /// stack stay visible (and the list keeps its scroll offset) while loading.
  Future<void> _enter(List<DriveSnapshot> stack) async {
    final target = stack.last;
    final gen = ++_loadGen;
    state = DriveState(stack: stack, loading: true);
    try {
      final items = await _graph.listChildren(target.folder.id);
      if (!ref.mounted || gen != _loadGen) return;
      _remember(target.folder.id, items);
      state = DriveState(stack: _replaceLast(stack, items));
    } catch (e) {
      if (!ref.mounted || gen != _loadGen) return;
      // Keep whatever was on screen: a failed refresh should not blank the
      // folder the user is looking at.
      state = DriveState(stack: stack, error: AppFailure.from(e));
    }
  }

  List<DriveSnapshot> _replaceLast(
    List<DriveSnapshot> stack,
    List<DriveItem> items,
  ) => [...stack.sublist(0, stack.length - 1), stack.last.withItems(items)];

  void _remember(String folderId, List<DriveItem> items) {
    _listings.remove(folderId);
    _listings[folderId] = items;
    if (_listings.length <= _maxCachedListings) return;
    final oldest = _listings.keys.first;
    _listings.remove(oldest);
  }
}

final driveProvider =
    NotifierProvider<DriveNotifier, DriveState>(DriveNotifier.new);
