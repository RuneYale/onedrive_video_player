import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onedrive_video_player/core/errors/app_failure.dart';
import 'package:onedrive_video_player/core/models/drive_item.dart';
import 'package:onedrive_video_player/core/services/graph_service.dart';
import 'package:onedrive_video_player/providers/drive_provider.dart';

/// Listings are scripted per folder id; [gates] blocks a folder's load so tests
/// can observe the state while a request is in flight.
class _FakeGraph extends GraphService {
  _FakeGraph() : super(Dio());

  final Map<String, List<DriveItem>> listings = {};
  final Map<String, Completer<void>> gates = {};
  final List<String> calls = [];
  Object? failWith;

  @override
  Future<List<DriveItem>> listChildren(String itemId) async {
    calls.add(itemId);
    final gate = gates[itemId];
    if (gate != null) await gate.future;
    final failure = failWith;
    if (failure != null) throw failure;
    return listings[itemId] ?? const [];
  }
}

DriveItem _video(String id) =>
    DriveItem(id: id, name: '$id.mp4', isFolder: false);
DriveItem _folderItem(String id) =>
    DriveItem(id: id, name: id, isFolder: true);

void main() {
  late _FakeGraph graph;
  late ProviderContainer container;

  setUp(() {
    graph = _FakeGraph();
    container = ProviderContainer(
      overrides: [graphServiceProvider.overrideWithValue(graph)],
    );
    addTearDown(container.dispose);
  });

  DriveNotifier notifier() => container.read(driveProvider.notifier);

  test('setRoot loads the root listing', () async {
    graph.listings['root'] = [_video('a')];
    await notifier().setRoot(const DriveFolder('root', 'OneDrive'));

    final state = container.read(driveProvider);
    expect(state.items.single.name, 'a.mp4');
    expect(state.current?.name, 'OneDrive');
    expect(state.loading, isFalse);
  });

  test('openFolder pushes a level and lists it', () async {
    graph.listings['root'] = [_folderItem('movies')];
    graph.listings['movies'] = [_video('a')];
    await notifier().setRoot(const DriveFolder('root', 'OneDrive'));
    await notifier().openFolder(_folderItem('movies'));

    final state = container.read(driveProvider);
    expect(state.canGoBack, isTrue);
    expect(state.current?.id, 'movies');
    expect(state.items.single.name, 'a.mp4');
  });

  test('goBack shows the parent listing before the refresh completes',
      () async {
    graph.listings['root'] = [_folderItem('movies')];
    graph.listings['movies'] = [_video('a')];
    await notifier().setRoot(const DriveFolder('root', 'OneDrive'));
    await notifier().openFolder(_folderItem('movies'));

    graph.gates['root'] = Completer<void>();
    final pending = notifier().goBack();

    // The parent rows are already on screen: the list is never replaced by a
    // spinner while going back.
    final during = container.read(driveProvider);
    expect(during.items.map((e) => e.name), ['movies']);
    expect(during.refreshing, isTrue);
    expect(during.coldLoading, isFalse);

    graph.gates['root']!.complete();
    await pending;
    expect(container.read(driveProvider).refreshing, isFalse);
  });

  test('a re-entered folder paints its cached listing immediately', () async {
    graph.listings['root'] = [_folderItem('movies')];
    graph.listings['movies'] = [_video('a')];
    await notifier().setRoot(const DriveFolder('root', 'OneDrive'));
    await notifier().openFolder(_folderItem('movies'));
    await notifier().goBack();

    graph.gates['movies'] = Completer<void>();
    final pending = notifier().openFolder(_folderItem('movies'));

    expect(container.read(driveProvider).items.single.name, 'a.mp4');
    graph.gates['movies']!.complete();
    await pending;
  });

  test('a failed refresh keeps the rows and exposes the failure', () async {
    graph.listings['root'] = [_video('a')];
    await notifier().setRoot(const DriveFolder('root', 'OneDrive'));

    graph.failWith = const ServerFailure();
    await notifier().refresh();

    final state = container.read(driveProvider);
    expect(state.error, isA<ServerFailure>());
    expect(state.items.single.name, 'a.mp4');
  });

  test('a failed first load reports the failure with no rows', () async {
    graph.failWith = const NetworkFailure();
    await notifier().setRoot(const DriveFolder('root', 'OneDrive'));

    final state = container.read(driveProvider);
    expect(state.error, isA<NetworkFailure>());
    expect(state.items, isEmpty);
    expect(state.coldLoading, isFalse);
  });

  test('a late response from an abandoned folder is ignored', () async {
    graph.listings['root'] = [_folderItem('a'), _folderItem('b')];
    await notifier().setRoot(const DriveFolder('root', 'OneDrive'));

    graph.gates['a'] = Completer<void>();
    final slow = notifier().openFolder(_folderItem('a'));

    // Move on to another folder before "a" answers.
    graph.listings['b'] = [_video('bee')];
    await notifier().openFolder(_folderItem('b'));

    graph.listings['a'] = [_video('wrong')];
    graph.gates['a']!.complete();
    await slow;

    // The late listing for "a" must not overwrite the folder now shown.
    expect(container.read(driveProvider).current?.id, 'b');
    expect(container.read(driveProvider).items.single.name, 'bee.mp4');
  });
}
