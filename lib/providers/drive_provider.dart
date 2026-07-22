import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/drive_item.dart';
import '../core/services/graph_service.dart';
import 'auth_provider.dart';

final graphServiceProvider = Provider<GraphService>((ref) {
  return GraphService(ref.watch(dioProvider), ref.watch(authServiceProvider));
});

/// A folder in the navigation stack. The root uses whatever id the user
/// selected (or 'root' for the OneDrive root).
class DriveFolder {
  const DriveFolder(this.id, this.name);
  final String id;
  final String name;
}

class DriveState {
  const DriveState({
    this.stack = const [],
    this.items = const [],
    this.loading = false,
    this.error,
  });

  final List<DriveFolder> stack;
  final List<DriveItem> items;
  final bool loading;
  final String? error;

  DriveFolder? get current => stack.isEmpty ? null : stack.last;
  bool get canGoBack => stack.length > 1;
  bool get isReady => stack.isNotEmpty;
}

class DriveNotifier extends Notifier<DriveState> {
  late final GraphService _graph;

  @override
  DriveState build() {
    _graph = ref.read(graphServiceProvider);
    return const DriveState();
  }

  /// Sets the root folder and loads its contents. Called when the user
  /// selects a folder (or when a saved folder is restored on startup).
  Future<void> setRoot(DriveFolder root) async {
    state = DriveState(stack: [root], loading: true);
    try {
      final items = await _graph.listChildren(root.id);
      if (!ref.mounted) return;
      state = DriveState(stack: [root], items: items, loading: false);
    } catch (e) {
      if (!ref.mounted) return;
      state = DriveState(stack: [root], loading: false, error: e.toString());
    }
  }

  /// Loads the current folder (called when the browser first appears).
  Future<void> refresh() async {
    if (state.stack.isEmpty) return;
    state = DriveState(
        stack: state.stack, items: state.items, loading: true);
    try {
      final items = await _graph.listChildren(state.current!.id);
      state = DriveState(
          stack: state.stack, items: items, loading: false);
    } catch (e) {
      state = DriveState(
        stack: state.stack,
        loading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> openFolder(DriveItem item) async {
    final newStack = [...state.stack, DriveFolder(item.id, item.name)];
    state = DriveState(stack: newStack, loading: true);
    try {
      final items = await _graph.listChildren(item.id);
      state = DriveState(stack: newStack, items: items, loading: false);
    } catch (e) {
      state = DriveState(
        stack: newStack,
        loading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> goBack() async {
    if (!state.canGoBack) return;
    final newStack = [...state.stack]..removeLast();
    state = DriveState(stack: newStack, loading: true);
    try {
      final items = await _graph.listChildren(newStack.last.id);
      state = DriveState(stack: newStack, items: items, loading: false);
    } catch (e) {
      state = DriveState(
        stack: newStack,
        loading: false,
        error: e.toString(),
      );
    }
  }
}

final driveProvider =
    NotifierProvider<DriveNotifier, DriveState>(DriveNotifier.new);