import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user-chosen "video library" root folder on OneDrive.
/// When null, the user hasn't picked a folder yet and the Videos tab will
/// prompt them to select one.
class SelectedFolder {
  const SelectedFolder({required this.id, required this.name});
  final String id;
  final String name;

  Map<String, dynamic> toMap() => {'id': id, 'name': name};

  factory SelectedFolder.fromMap(Map<String, dynamic> map) => SelectedFolder(
        id: map['id'] as String,
        name: map['name'] as String,
      );
}

class FolderNotifier extends Notifier<SelectedFolder?> {
  static const _key = 'odvp_selected_folder';

  @override
  SelectedFolder? build() {
    unawaited(_load());
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (ref.mounted) state = SelectedFolder.fromMap(map);
    } catch (_) {}
  }

  Future<void> select(SelectedFolder folder) async {
    state = folder;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(folder.toMap()));
  }

  Future<void> clear() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

final folderProvider =
    NotifierProvider<FolderNotifier, SelectedFolder?>(FolderNotifier.new);