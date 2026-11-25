import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import '../models/media_item.dart';
import 'permission_service.dart';
import 'thumbnail_service.dart';

/// Supported video file extensions (MKV, MOV, WebM, MP4, H.265/HEVC, VP9, etc.).
const _kSupportedVideoExtensions = {
  '.mp4',
  '.mkv',
  '.mov',
  '.webm',
  '.3gp',
  '.3gpp',
  '.avi',
  '.m4v',
  '.flv',
  '.ts',
  '.wmv',
  '.asf',
  '.vob',
  '.ogv',
};

/// Supported video MIME types.
const _kSupportedVideoMimes = {
  'video/mp4',
  'video/x-matroska',
  'video/mkv',
  'video/matroska',
  'application/x-matroska',
  'video/quicktime',
  'video/mov',
  'video/webm',
  'audio/webm',
  'video/3gpp',
  'video/3gpp2',
  'video/avi',
  'video/x-msvideo',
  'video/x-flv',
  'video/x-m4v',
  'video/mp2t',
  'video/x-ms-wmv',
  'video/ogg',
};

/// Scans the device's local media store for photos and videos.
///
/// Uses [photo_manager] so it respects MediaStore indexing on Android and
/// never touches the network.
class MediaScannerService {
  static const MethodChannel _nativeChannel =
      MethodChannel('com.phantek.gallery/media_scanner');

  /// Checks if a file path or extension belongs to a supported video format.
  static bool isSupportedVideo(String pathOrExt) {
    final ext = p.extension(pathOrExt).isNotEmpty
        ? p.extension(pathOrExt).toLowerCase()
        : (pathOrExt.startsWith('.')
            ? pathOrExt.toLowerCase()
            : '.$pathOrExt'.toLowerCase());
    return _kSupportedVideoExtensions.contains(ext);
  }

  /// Checks if a MIME type is a supported video MIME type.
  static bool isSupportedVideoMime(String mime) {
    return _kSupportedVideoMimes.contains(mime.toLowerCase());
  }

  /// Infers a standardized video MIME type based on file extension.
  static String? inferMimeType(String pathOrExt, {bool isVideo = false}) {
    final ext = p.extension(pathOrExt).isNotEmpty
        ? p.extension(pathOrExt).toLowerCase()
        : (pathOrExt.startsWith('.')
            ? pathOrExt.toLowerCase()
            : '.$pathOrExt'.toLowerCase());
    return switch (ext) {
      '.mkv' => 'video/x-matroska',
      '.webm' => 'video/webm',
      '.mov' => 'video/quicktime',
      '.mp4' => 'video/mp4',
      '.3gp' || '.3gpp' => 'video/3gpp',
      '.avi' => 'video/avi',
      '.flv' => 'video/x-flv',
      '.ts' => 'video/mp2t',
      '.wmv' => 'video/x-ms-wmv',
      '.psd' => 'image/vnd.adobe.photoshop',
      _ => isVideo ? 'video/${ext.replaceFirst('.', '')}' : null,
    };
  }

  /// Fetch all [MediaItem]s from the local store.
  ///
  /// [excludedFolders] – absolute paths that should be skipped.
  /// [onProgress] – optional callback with (loadedCount, totalCount).
  Future<List<MediaItem>> scanAll({
    List<String> excludedFolders = const [],
    void Function(int loaded, int total)? onProgress,
  }) async {
    // Ensure permission is granted before querying MediaStore.
    final hasPermission = await PermissionService.instance.hasMediaPermission();
    if (!hasPermission) {
      final granted =
          await PermissionService.instance.requestMediaPermissions();
      if (!granted) return [];
    }

    // Fast path on Android: single native bulk MediaStore query.
    if (Platform.isAndroid) {
      final nativeItems = await _scanAllNative(
        excludedFolders: excludedFolders,
        onProgress: onProgress,
      );
      if (nativeItems != null) {
        return nativeItems;
      }
    }

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common, // both image + video
      hasAll: true,
    );

    // Avoid double-fetching assets when the synthetic "All" album is present.
    final allAlbums = albums.where((a) => a.isAll).toList();
    final albumsToScan = allAlbums.isNotEmpty ? [allAlbums.first] : albums;

    // Collect unique asset IDs across target albums.
    final seen = <String>{};
    final assets = <AssetEntity>[];

    for (final album in albumsToScan) {
      final count = await album.assetCountAsync;
      if (count <= 0) continue;
      final albumAssets = await album.getAssetListRange(start: 0, end: count);
      for (final a in albumAssets) {
        if (seen.add(a.id)) {
          assets.add(a);
        }
      }
    }

    final total = assets.length;
    // Pre-register entities in ThumbnailService to accelerate thumbnail generation.
    ThumbnailService.instance.registerEntities(assets);

    final results = <MediaItem>[];
    const chunkSize = 30;

    for (var i = 0; i < total; i += chunkSize) {
      final end = (i + chunkSize < total) ? i + chunkSize : total;
      final chunk = assets.sublist(i, end);
      final chunkResults = await Future.wait(
        chunk.map((entity) => _toMediaItem(entity, excludedFolders)),
      );
      for (final item in chunkResults) {
        if (item != null) results.add(item);
      }
      onProgress?.call(end, total);
    }

    return results;
  }

  Future<List<MediaItem>?> _scanAllNative({
    required List<String> excludedFolders,
    void Function(int loaded, int total)? onProgress,
  }) async {
    try {
      final raw = await _nativeChannel.invokeListMethod<dynamic>(
        'scanAllMedia',
        {'excludedFolders': excludedFolders},
      );
      if (raw == null) return null;
      final items = parseNativeScanResults(
        raw,
        excludedFolders: excludedFolders,
      );
      onProgress?.call(items.length, items.length);
      return items;
    } catch (e) {
      debugPrint(
          '[MediaScannerService] Native scan failed, falling back to photo_manager: $e');
      return null;
    }
  }

  /// Parses raw maps returned by the Android native bulk MediaStore scanner.
  @visibleForTesting
  static List<MediaItem> parseNativeScanResults(
    List<dynamic> rawList, {
    List<String> excludedFolders = const [],
  }) {
    final results = <MediaItem>[];
    for (final entry in rawList) {
      if (entry is! Map) continue;
      final id = entry['id']?.toString();
      final path = entry['path'] as String?;
      if (id == null || id.isEmpty || path == null || path.isEmpty) continue;

      if (path.contains('/.trash/') ||
          path.contains(r'\.trash\') ||
          path.endsWith('/.trash') ||
          path.endsWith(r'\.trash')) {
        continue;
      }

      if (excludedFolders
          .any((excluded) => excluded.isNotEmpty && path.startsWith(excluded))) {
        continue;
      }

      final ext = p.extension(path).toLowerCase();
      final isVideo = (entry['isVideo'] as bool? ?? false) ||
          _kSupportedVideoExtensions.contains(ext);

      final rawMime = entry['mimeType'] as String?;
      if (isVideo) {
        final mime = rawMime?.toLowerCase() ?? '';
        final hasSupportedMime =
            mime.isNotEmpty && _kSupportedVideoMimes.contains(mime);
        final hasSupportedExt = _kSupportedVideoExtensions.contains(ext);
        if (!hasSupportedMime && !hasSupportedExt) continue;
      }

      final mimeType = (rawMime != null && rawMime.isNotEmpty)
          ? rawMime
          : inferMimeType(path, isVideo: isVideo);

      final rawName = entry['name'] as String?;
      final name = (rawName != null && rawName.isNotEmpty)
          ? rawName
          : path.split('/').last;

      final dateMs = (entry['dateMs'] as num?)?.toInt() ?? 0;
      final dateAddedMs = (entry['dateAddedMs'] as num?)?.toInt();
      final size = (entry['size'] as num?)?.toInt() ?? 0;
      final durationMs = (entry['durationMs'] as num?)?.toInt();
      final width = (entry['width'] as num?)?.toInt() ?? 0;
      final height = (entry['height'] as num?)?.toInt() ?? 0;

      results.add(MediaItem(
        id: id,
        path: path,
        name: name,
        date: DateTime.fromMillisecondsSinceEpoch(dateMs),
        dateAdded: dateAddedMs != null && dateAddedMs > 0
            ? DateTime.fromMillisecondsSinceEpoch(dateAddedMs)
            : null,
        size: size,
        isVideo: isVideo,
        duration: isVideo
            ? Duration(milliseconds: (durationMs ?? 0) < 0 ? 0 : (durationMs ?? 0))
            : null,
        width: width,
        height: height,
        mimeType: mimeType,
      ));
    }
    return results;
  }

  /// Converts an [AssetEntity] to [MediaItem], returning null if:
  /// - the file is in an excluded folder, or
  /// - the file is in trash, or
  /// - the file no longer exists on disk.
  Future<MediaItem?> _toMediaItem(
    AssetEntity entity,
    List<String> excludedFolders,
  ) async {
    final file = await entity.file ?? await entity.originFile;
    if (file == null || !await file.exists()) return null;

    final path = file.path;

    // Skip item if it resides in trash or excluded folders.
    if (path.contains('/.trash/') ||
        path.contains(r'\.trash\') ||
        path.endsWith('/.trash') ||
        path.endsWith(r'\.trash')) {
      return null;
    }

    if (excludedFolders.any((excluded) => path.startsWith(excluded))) {
      return null;
    }

    final ext = p.extension(path).toLowerCase();
    final isVideo = entity.type == AssetType.video ||
        _kSupportedVideoExtensions.contains(ext);

    // Filter out unsupported video formats.
    if (isVideo) {
      final mime = entity.mimeType?.toLowerCase() ?? '';
      final hasSupportedMime =
          mime.isNotEmpty && _kSupportedVideoMimes.contains(mime);
      final hasSupportedExt = _kSupportedVideoExtensions.contains(ext);
      if (!hasSupportedMime && !hasSupportedExt) return null;
    }

    int size = 0;
    try {
      size = await file.length();
    } catch (_) {}

    String? mimeType = entity.mimeType;
    if (mimeType == null || mimeType.isEmpty) {
      mimeType = inferMimeType(path, isVideo: isVideo);
    }

    final orientatedW = entity.orientatedWidth;
    final orientatedH = entity.orientatedHeight;
    final int w;
    final int h;
    if (orientatedW > 0 && orientatedH > 0) {
      w = orientatedW;
      h = orientatedH;
    } else {
      final isRotated = entity.orientation == 90 || entity.orientation == 270;
      w = isRotated ? entity.height : entity.width;
      h = isRotated ? entity.width : entity.height;
    }

    return MediaItem(
      id: entity.id,
      path: path,
      name: entity.title ?? path.split('/').last,
      date: entity.createDateTime,
      dateAdded: entity.modifiedDateTime,
      size: size,
      isVideo: isVideo,
      duration: isVideo ? Duration(seconds: entity.duration) : null,
      width: w,
      height: h,
      mimeType: mimeType,
    );
  }
}
