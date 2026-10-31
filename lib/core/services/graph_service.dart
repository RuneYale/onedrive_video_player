import 'package:dio/dio.dart';

import '../../config/auth_config.dart';
import '../errors/app_failure.dart';
import '../models/drive_item.dart';

/// Wraps the Microsoft Graph API calls used by the app:
/// - listing a folder's children (with pagination)
/// - resolving a pre-authenticated streaming URL for a file
///
/// Authentication is handled by the shared Dio instance's interceptor, so this
/// class never sees tokens. Every Dio failure is mapped to an [AppFailure] so
/// screens can show a sentence instead of an HTTP dump.
class GraphService {
  GraphService(this._dio);

  final Dio _dio;

  /// Only the fields [DriveItem.fromJson] reads. Asking for less keeps large
  /// folders (200 items per page) noticeably lighter.
  static const _select =
      'id,name,size,lastModifiedDateTime,parentReference,folder,file';

  /// Lists the children of [itemId]. Use `'root'` for the OneDrive root.
  Future<List<DriveItem>> listChildren(String itemId) async {
    final path = itemId == 'root'
        ? '/me/drive/root/children'
        : '/me/drive/items/$itemId/children';
    try {
      var res = await _firstPage(path);
      final value = <dynamic>[];
      // Graph paginates at 200 items per page by default; follow
      // @odata.nextLink (a full absolute URL) until the listing is exhausted.
      while (true) {
        final data = res.data as Map<String, dynamic>;
        value.addAll(data['value'] as List<dynamic>);
        final nextLink = data['@odata.nextLink'] as String?;
        if (nextLink == null || nextLink.isEmpty) break;
        res = await _dio.getUri<dynamic>(Uri.parse(nextLink));
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
    } on DioException catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// First page with the projected field list; some drives reject `$select`
  /// combined with `$expand`, so fall back to the full representation once
  /// instead of failing the whole screen.
  Future<Response<dynamic>> _firstPage(String path) async {
    final url = '${AuthConfig.graphBase}$path';
    try {
      return await _dio.get<dynamic>(
        url,
        queryParameters: {'\$select': _select, '\$expand': 'thumbnails'},
      );
    } on DioException catch (e) {
      if (e.response?.statusCode != 400) rethrow;
      return _dio.get<dynamic>(
        url,
        queryParameters: {'\$expand': 'thumbnails'},
      );
    }
  }

  /// Resolves a short-lived, pre-authenticated download URL for [itemId]
  /// by following the `/content` redirect. This URL can be handed directly to
  /// the video player; libmpv issues its own HTTP Range requests for seeking.
  Future<String> getDownloadUrl(String itemId) async {
    try {
      final res = await _dio.get<dynamic>(
        '${AuthConfig.graphBase}/me/drive/items/$itemId/content',
        options: Options(
          followRedirects: false,
          validateStatus: (s) => s != null && s < 400,
        ),
      );
      final location = res.headers.value('location');
      if (location == null || location.isEmpty) {
        throw UnknownFailure(
          message: 'OneDrive did not return a download link for this video.',
          detail: 'no location header for item $itemId',
        );
      }
      return location;
    } on DioException catch (e) {
      throw AppFailure.from(e);
    }
  }
}
