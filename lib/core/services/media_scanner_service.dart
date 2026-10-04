import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import '../models/media_item.dart';

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
  /// Checks if a file path or extension belongs to a supported video format.
  static bool isSupportedVideo(String pathOrExt) {
    final ext = p.extension(pathOrExt).isNotEmpty
        ? p.extension(pathOrExt).toLowerCase()
        : (pathOrExt.startsWith('.') ? pathOrExt.toLowerCase() : '.$pathOrExt'.toLowerCase());
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
        : (pathOrExt.startsWith('.') ? pathOrExt.toLowerCase() : '.$pathOrExt'.toLowerCase());
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
    // photo_manager handles permission prompting upstream (via PermissionService).
    // Here we only fetch – caller must ensure permission is granted.
    try {
      await PhotoManager.clearFileCache();
    } catch (_) {}

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common, // both image + video
      hasAll: true,
    );

    // Collect asset IDs across all albums (dedup by id).
    final seen = <String>{};
    final assets = <AssetEntity>[];

    for (final album in albums) {
      final albumAssets =
          await album.getAssetListRange(start: 0, end: await album.assetCountAsync);
      for (final a in albumAssets) {
        if (seen.add(a.id)) {
          assets.add(a);
        }
      }
    }

    final total = assets.length;
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

  /// Converts an [AssetEntity] to [MediaItem], returning null if:
  /// - the file is in an excluded folder, or
  /// - the file is in trash, or
  /// - the file no longer exists on disk.
  Future<MediaItem?> _toMediaItem(
    AssetEntity entity,
    List<String> excludedFolders,
  ) async {
    final file = await entity.originFile;
    if (file == null || !await file.exists()) return null;

    final path = file.path;

    // Check trash folder and exclusion list.
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
    final isVideo =
        entity.type == AssetType.video || _kSupportedVideoExtensions.contains(ext);

    // For video, filter unsupported video formats.
    if (isVideo) {
      final mime = entity.mimeType?.toLowerCase() ?? '';
      final hasSupportedMime = mime.isNotEmpty && _kSupportedVideoMimes.contains(mime);
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

    return MediaItem(
      id: entity.id,
      path: path,
      name: entity.title ?? path.split('/').last,
      date: entity.createDateTime,
      dateAdded: entity.modifiedDateTime,
      size: size,
      isVideo: isVideo,
      duration: isVideo ? Duration(seconds: entity.duration) : null,
      width: entity.width,
      height: entity.height,
      mimeType: mimeType,
    );
  }
}
