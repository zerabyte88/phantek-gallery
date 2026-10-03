import 'dart:async';
import 'package:photo_manager/photo_manager.dart';
import '../models/media_item.dart';

/// Supported video MIME types / extensions (H.265, VP9, etc.).
const _kSupportedVideoMimes = {
  'video/mp4',
  'video/x-matroska',  // MKV
  'video/quicktime',   // MOV
  'video/webm',
  'video/3gpp',
  'video/avi',
};

/// Scans the device's local media store for photos and videos.
///
/// Uses [photo_manager] so it respects MediaStore indexing on Android and
/// never touches the network.
class MediaScannerService {
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

    for (var i = 0; i < total; i++) {
      final entity = assets[i];
      final item = await _toMediaItem(entity, excludedFolders);
      if (item != null) results.add(item);
      onProgress?.call(i + 1, total);
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

    final isVideo = entity.type == AssetType.video;

    // For video, filter unsupported MIME types.
    if (isVideo) {
      final mime = entity.mimeType ?? '';
      if (!_kSupportedVideoMimes.contains(mime)) return null;
    }

    int size = 0;
    try {
      size = await file.length();
    } catch (_) {}

    return MediaItem(
      id: entity.id,
      path: path,
      name: entity.title ?? path.split('/').last,
      date: entity.createDateTime,
      dateAdded: entity.modifiedDateTime,
      size: size,
      isVideo: isVideo,
      duration: isVideo
          ? Duration(seconds: entity.duration)
          : null,
      width: entity.width,
      height: entity.height,
      mimeType: entity.mimeType,
    );
  }

  /// Watch for new/deleted media by polling (simple approach).
  /// Returns a stream that emits whenever the library should be refreshed.
  ///
  /// ponytail: polling every 30 s is simpler than ContentObserver bridge;
  ///           upgrade to native observer if battery becomes an issue.
  Stream<void> watchChanges({Duration interval = const Duration(seconds: 30)}) {
    return Stream.periodic(interval).asyncMap((_) async {});
  }
}
