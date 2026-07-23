import 'package:dio/dio.dart';

import '../../config/auth_config.dart';
// AuthTokens type is not referenced directly here (inferred from ensureTokens).
import '../models/drive_item.dart';
import 'auth_service.dart';

/// Wraps the Microsoft Graph API calls used by the app:
/// - listing a folder's children
/// - resolving a pre-authenticated streaming URL for a file
class GraphService {
  GraphService(this._dio, this._auth);

  final Dio _dio;
  final AuthService _auth;

  /// Lists the children of [itemId]. Use `'root'` for the OneDrive root.
  Future<List<DriveItem>> listChildren(String itemId) async {
    final t = await _auth.ensureTokens();
    final path = itemId == 'root'
        ? '/me/drive/root/children'
        : '/me/drive/items/$itemId/children';
    final options =
        Options(headers: {'Authorization': 'Bearer ${t.accessToken}'});
    // First page carries $expand=thumbnails; @odata.nextLink already encodes
    // the continuation parameters for subsequent pages.
    var res = await _dio.get<dynamic>(
      '${AuthConfig.graphBase}$path',
      queryParameters: {'\$expand': 'thumbnails'},
      options: options,
    );
    final value = <dynamic>[];
    // Graph paginates at 200 items per page by default; follow
    // @odata.nextLink (a full absolute URL) until the listing is exhausted.
    while (true) {
      final data = res.data as Map<String, dynamic>;
      value.addAll(data['value'] as List<dynamic>);
      final nextLink = data['@odata.nextLink'] as String?;
      if (nextLink == null || nextLink.isEmpty) break;
      res = await _dio.getUri<dynamic>(Uri.parse(nextLink), options: options);
    }
    final items = value
        .map((e) => DriveItem.fromJson(e as Map<String, dynamic>))
        .toList();
    // Folders first, then files, both alphabetical (case-insensitive).
    items.sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return items;
  }

  /// Resolves a short-lived, pre-authenticated download URL for [itemId]
  /// by following the `/content` redirect. This URL can be handed directly to
  /// the video player; libmpv issues its own HTTP Range requests for seeking.
  Future<String> getDownloadUrl(String itemId) async {
    final t = await _auth.ensureTokens();
    final res = await _dio.get<dynamic>(
      '${AuthConfig.graphBase}/me/drive/items/$itemId/content',
      options: Options(
        headers: {'Authorization': 'Bearer ${t.accessToken}'},
        followRedirects: false,
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    final location = res.headers.value('location');
    if (location == null || location.isEmpty) {
      throw StateError('No download URL returned for item $itemId');
    }
    return location;
  }
}
