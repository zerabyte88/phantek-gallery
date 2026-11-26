import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'media_scanner_service.dart';
import 'psd_service.dart';

/// Itemized disk cache breakdown across thumbnails, screen previews, and PSD previews.
class CacheSizeBreakdown {
  const CacheSizeBreakdown({
    required this.thumbnailBytes,
    required this.previewBytes,
    required this.psdBytes,
  });

  final int thumbnailBytes;
  final int previewBytes;
  final int psdBytes;

  int get totalBytes => thumbnailBytes + previewBytes + psdBytes;
}

/// Queued thumbnail fetch request for uncached items.
class _ThumbnailRequest {
  _ThumbnailRequest(
    this.id,
    this.completer, {
    this.filePath,
    this.isVideo = false,
    bool Function()? isCancelled,
  }) {
    cancelPredicates.add(isCancelled);
  }

  final String id;
  final String? filePath;
  final bool isVideo;
  final Completer<Uint8List?> completer;
  final List<bool Function()?> cancelPredicates = [];

  bool get isAllCancelled =>
      cancelPredicates.isNotEmpty &&
      cancelPredicates.every((fn) => fn != null && fn());
}

class _GridHiResRequest {
  _GridHiResRequest({
    required this.assetId,
    required this.filePath,
    required this.size,
    required this.isVideo,
    required this.isCancelled,
    required this.completer,
  });

  final String assetId;
  final String filePath;
  final int size;
  final bool isVideo;
  final bool Function()? isCancelled;
  final Completer<Uint8List?> completer;
}

/// Asynchronous thumbnail cache with persistent disk storage, background worker pool, and in-memory layer.
class ThumbnailService {
  ThumbnailService._();
  static final ThumbnailService instance = ThumbnailService._();

  static const int _thumbnailSize = 512;
  static const int _videoThumbnailSize = 720;
  static const int _thumbnailQuality = 90;
  static const int _maxMemoryEntries = 500;
  static const int _maxConcurrent = 6;
  static const int _maxGridHiResConcurrent = 2;
  static const int defaultPreviewMaxDim = 1440;
  static const int _maxPreviewMemoryEntries = 40;
  static const MethodChannel _nativeChannel =
      MethodChannel('com.phantek.gallery/thumbnail');

  final Map<String, Uint8List> _memoryCache = {};
  final Map<String, Uint8List> _highResVideoCache = {};
  final Map<String, Uint8List> _previewMemoryCache = {};
  final Map<String, String> _previewFileNameByPathKey = {};
  final Map<String, double> _thumbnailAspectRatioCache = {};
  final Map<String, Uint8List> _videoFrameCache = {};
  final Map<String, Completer<Uint8List?>> _inFlight = {};
  final Map<String, _ThumbnailRequest> _queuedOrInFlightRequests = {};
  final Map<String, Completer<Uint8List?>> _highResInFlight = {};
  final Map<String, Completer<Uint8List?>> _previewInFlight = {};
  final Map<String, AssetEntity> _entityCache = {};
  final Queue<_ThumbnailRequest> _queue = Queue();
  final Queue<_GridHiResRequest> _gridHiResQueue = Queue();
  final Set<String> _diskCachedFileNames = {};
  int _activeWorkers = 0;
  int _activeGridHiResWorkers = 0;
  bool _diskIndexReady = false;
  int _diskIndexGeneration = 0;
  Directory? _cacheDir;
  String? _cacheDirPath;
  Future<Directory>? _cacheDirFuture;

  @visibleForTesting
  bool get debugIsDiskIndexReady => _diskIndexReady;

  @visibleForTesting
  void debugSetDiskIndexReady(bool ready) {
    _diskIndexGeneration++;
    _diskIndexReady = ready;
  }

  /// Pre-initializes the persistent cache directory at application launch.
  /// Disk cache indexing runs in the background so startup is never blocked.
  static Future<void> init() async {
    if (instance._cacheDir == null) {
      // Clear any uncompleted future captured by an earlier disposed test zone.
      instance._cacheDirFuture = null;
    }
    final dir = await instance._getCacheDirectory();
    instance._diskIndexReady = false;
    unawaited(instance._populateDiskCacheIndex(dir));
  }

  Future<void> _populateDiskCacheIndex(Directory dir) async {
    final gen = ++_diskIndexGeneration;
    try {
      if (await dir.exists()) {
        await for (final entity
            in dir.list(recursive: false, followLinks: false)) {
          if (gen != _diskIndexGeneration) return;
          if (entity is File) {
            final name = p.basename(entity.path);
            if (name.endsWith('.bin') &&
                (name.startsWith('thumb_') ||
                    name.startsWith('hr_') ||
                    name.startsWith('prev_') ||
                    name.startsWith('psd_prev_'))) {
              _diskCachedFileNames.add(name);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ThumbnailService] Error indexing disk cache: $e');
    } finally {
      if (gen == _diskIndexGeneration) {
        _diskIndexReady = true;
      }
    }
  }

  /// Returns true if the thumbnail for [assetId] is known to exist on disk.
  bool hasDiskCache(String assetId) =>
      _diskCachedFileNames.contains(_cacheFileName(assetId));

  /// Returns true if the high-res thumbnail for [assetId] is known to exist on disk.
  bool hasDiskHighResCache(String assetId) =>
      _diskCachedFileNames.contains(_highResCacheFileName(assetId));

  /// Synchronously returns the indexed cache [File] on disk without performing
  /// a blocking `existsSync()` call on the UI thread.
  File? getIndexedDiskFile(String assetId) {
    if (!hasDiskCache(assetId)) return null;
    final dirPath = _cacheDirPath ?? _cacheDir?.path;
    if (dirPath == null) return null;
    return File(p.join(dirPath, _cacheFileName(assetId)));
  }

  /// Removes [assetId] from the in-memory disk cache index (e.g., if evicted on disk).
  void evictDiskCacheIndex(String assetId) =>
      _diskCachedFileNames.remove(_cacheFileName(assetId));

  @visibleForTesting
  String debugCacheFileName(String assetId) => _cacheFileName(assetId);

  /// Synchronously returns the cached File on disk if it already exists, or null.
  File? getCachedFile(String assetId) {
    final file = getIndexedDiskFile(assetId);
    if (file == null) return null;
    return file.existsSync() ? file : null;
  }

  String _highResCacheFileName(String assetId) {
    final safe = assetId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return 'hr_${assetId.hashCode.abs()}_$safe.bin';
  }

  /// Synchronously returns the cached high-res video thumbnail File on disk if it exists.
  File? getCachedHighResFile(String assetId) {
    if (!hasDiskHighResCache(assetId)) return null;
    final dirPath = _cacheDirPath ?? _cacheDir?.path;
    if (dirPath == null) return null;
    final file = File(p.join(dirPath, _highResCacheFileName(assetId)));
    return file.existsSync() ? file : null;
  }

  /// Register pre-discovered AssetEntities to avoid IPC lookups.
  void registerEntities(Iterable<AssetEntity> entities) {
    for (final e in entities) {
      _entityCache[e.id] = e;
    }
  }

  String? get cacheDirPathSync => _cacheDirPath ?? _cacheDir?.path;

  Future<Directory> getCacheDirectory() => _getCacheDirectory();

  void registerDiskCacheFileName(String fileName) =>
      _diskCachedFileNames.add(fileName);

  void unregisterDiskCacheFileNamesByPrefix(String prefix) =>
      _diskCachedFileNames.removeWhere((name) => name.startsWith(prefix));

  bool hasDiskCacheFileName(String fileName) =>
      _diskCachedFileNames.contains(fileName);

  String _previewPathKey(String filePath, int maxDimension) =>
      '$filePath|$maxDimension';

  Future<String?> _computePreviewCacheFileNameAsync(
    String filePath, {
    int maxDimension = defaultPreviewMaxDim,
  }) async {
    if (filePath.isEmpty) return null;
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final stat = await file.stat();
      final sig =
          '${filePath}_${stat.size}_${stat.modified.millisecondsSinceEpoch}_$maxDimension';
      final safe = p
          .basenameWithoutExtension(filePath)
          .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      return 'prev_${sig.hashCode.abs()}_${maxDimension}_$safe.bin';
    } catch (_) {
      return null;
    }
  }

  /// Fast synchronous lookup in the in-memory screen-fit preview cache (0ms, zero disk I/O).
  Uint8List? getMemoryPreview(
    String filePath, {
    int maxDimension = defaultPreviewMaxDim,
  }) {
    if (filePath.isEmpty) return null;
    final fileName =
        _previewFileNameByPathKey[_previewPathKey(filePath, maxDimension)];
    if (fileName == null) return null;
    final bytes = _previewMemoryCache.remove(fileName);
    if (bytes == null) return null;
    _previewMemoryCache[fileName] = bytes;
    return bytes;
  }

  /// Synchronously returns the cached screen-fit preview File on disk without
  /// performing blocking `existsSync()` / `statSync()` on the UI thread.
  File? getCachedPreviewFile(
    String filePath, {
    int maxDimension = defaultPreviewMaxDim,
  }) {
    if (filePath.isEmpty) return null;
    final fileName =
        _previewFileNameByPathKey[_previewPathKey(filePath, maxDimension)];
    final dirPath = cacheDirPathSync;
    if (fileName == null || dirPath == null) return null;
    if (!_diskCachedFileNames.contains(fileName)) return null;
    return File(p.join(dirPath, fileName));
  }

  void _putPreviewInMemory(String fileName, Uint8List bytes) {
    _previewMemoryCache.remove(fileName);
    while (_previewMemoryCache.length >= _maxPreviewMemoryEntries) {
      _previewMemoryCache.remove(_previewMemoryCache.keys.first);
    }
    _previewMemoryCache[fileName] = bytes;
  }

  /// Pre-decodes and persists a screen-fit JPEG preview for a photo file.
  Future<Uint8List?> prewarmPhotoPreview(
    String filePath, {
    String? assetId,
    int maxDimension = defaultPreviewMaxDim,
  }) async {
    if (filePath.isEmpty ||
        PsdService.isPsd(filePath) ||
        MediaScannerService.isSupportedVideo(filePath)) {
      return null;
    }
    final fileName = await _computePreviewCacheFileNameAsync(
      filePath,
      maxDimension: maxDimension,
    );
    if (fileName == null) return null;
    _previewFileNameByPathKey[_previewPathKey(filePath, maxDimension)] =
        fileName;

    final mem = getMemoryPreview(filePath, maxDimension: maxDimension);
    if (mem != null) return mem;

    final inFlight = _previewInFlight[fileName];
    if (inFlight != null) return inFlight.future;

    final completer = Completer<Uint8List?>();
    _previewInFlight[fileName] = completer;

    try {
      final dir = await _getCacheDirectory();
      final diskFile = File(p.join(dir.path, fileName));
      if (await diskFile.exists()) {
        try {
          final diskBytes = await diskFile.readAsBytes();
          if (diskBytes.isNotEmpty) {
            _putPreviewInMemory(fileName, diskBytes);
            _diskCachedFileNames.add(fileName);
            completer.complete(diskBytes);
            return diskBytes;
          }
        } catch (_) {}
      }

      Uint8List? bytes;
      try {
        bytes = await _nativeChannel.invokeMethod<Uint8List>(
          'getImageThumbnail',
          {'path': filePath, 'assetId': assetId, 'size': maxDimension},
        );
      } catch (_) {}

      if (bytes == null || bytes.isEmpty) {
        bytes = await compute(
          _isolateDecodePhotoPreview,
          _PhotoPreviewParams(filePath, maxDimension),
        );
      }

      if (bytes != null && bytes.isNotEmpty) {
        _putPreviewInMemory(fileName, bytes);
        await _writeBytesAtomic(dir, fileName, bytes);
        _diskCachedFileNames.add(fileName);
        if (!completer.isCompleted) {
          completer.complete(bytes);
        }
        return bytes;
      }

      if (!completer.isCompleted) {
        completer.complete(null);
      }
      return null;
    } catch (e) {
      debugPrint(
          '[ThumbnailService] prewarmPhotoPreview error for $filePath: $e');
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      return null;
    } finally {
      _previewInFlight.remove(fileName);
    }
  }

  /// Fast synchronous lookup in the in-memory cache (0ms).
  Uint8List? getMemoryThumbnail(String assetId) => _memoryCache[assetId];

  /// Fast synchronous lookup for high-res video thumbnail (0ms).
  Uint8List? getMemoryHighResThumbnail(String assetId) =>
      _highResVideoCache[assetId];

  /// Returns the visual aspect ratio (width / height) of the cached thumbnail.
  double? getThumbnailAspectRatio(String assetId) {
    if (_thumbnailAspectRatioCache.containsKey(assetId)) {
      return _thumbnailAspectRatioCache[assetId];
    }
    final bytes = _highResVideoCache[assetId] ?? _memoryCache[assetId];
    if (bytes != null && bytes.length >= 9) {
      final size = parseJpegDimensions(bytes);
      if (size != null && size.height > 0) {
        final ratio = size.width / size.height;
        _thumbnailAspectRatioCache[assetId] = ratio;
        return ratio;
      }
    }
    final file = getCachedHighResFile(assetId) ?? getCachedFile(assetId);
    if (file != null) {
      try {
        final raf = file.openSync();
        try {
          final header = raf.readSync(4096);
          final size = parseJpegDimensions(header);
          if (size != null && size.height > 0) {
            final ratio = size.width / size.height;
            _thumbnailAspectRatioCache[assetId] = ratio;
            return ratio;
          }
        } finally {
          raf.closeSync();
        }
      } catch (_) {}
    }
    return null;
  }

  /// Sets or updates the visual aspect ratio cache (e.g. from video player probe).
  void setThumbnailAspectRatio(String assetId, double ratio) {
    if (ratio > 0) {
      _thumbnailAspectRatioCache[assetId] = ratio;
    }
  }

  /// Extracts a high-resolution video thumbnail.
  Future<Uint8List?> getHighResVideoThumbnail(
    String assetId, {
    required String filePath,
    int size = 1920,
  }) async {
    final cached = _highResVideoCache[assetId];
    if (cached != null) return cached;

    final diskFile = getCachedHighResFile(assetId);
    if (diskFile != null) {
      try {
        final diskBytes = await diskFile.readAsBytes();
        if (diskBytes.isNotEmpty) {
          while (_highResVideoCache.length >= 25) {
            _highResVideoCache.remove(_highResVideoCache.keys.first);
          }
          _highResVideoCache[assetId] = diskBytes;
          final dims = parseJpegDimensions(diskBytes);
          if (dims != null && dims.height > 0) {
            _thumbnailAspectRatioCache[assetId] = dims.width / dims.height;
          }
          return diskBytes;
        }
      } catch (_) {}
    }

    final inFlight = _highResInFlight[assetId];
    if (inFlight != null) return inFlight.future;

    final completer = Completer<Uint8List?>();
    _highResInFlight[assetId] = completer;

    try {
      Uint8List? bytes;

      try {
        bytes = await _nativeChannel.invokeMethod<Uint8List>(
          'getVideoThumbnail',
          {'path': filePath, 'assetId': assetId, 'size': size},
        );
      } catch (e) {
        debugPrint(
            '[ThumbnailService] Native getHighResVideoThumbnail failed for $filePath: $e');
      }

      if (bytes == null || bytes.isEmpty) {
        final entity =
            _entityCache[assetId] ?? await AssetEntity.fromId(assetId);
        if (entity != null) {
          try {
            final w = entity.orientatedWidth > 0
                ? entity.orientatedWidth
                : entity.width;
            final h = entity.orientatedHeight > 0
                ? entity.orientatedHeight
                : entity.height;
            final maxDim = (w > 0 && h > 0) ? (w > h ? w : h) : size;
            final scale = maxDim > size ? size / maxDim : 1.0;
            final targetW = (w > 0) ? (w * scale).toInt().clamp(2, size) : size;
            final targetH = (h > 0) ? (h * scale).toInt().clamp(2, size) : size;
            bytes = await entity.thumbnailDataWithSize(
              ThumbnailSize(targetW, targetH),
              quality: 95,
            );
          } catch (_) {}
        }
      }

      if (bytes != null && bytes.isNotEmpty) {
        while (_highResVideoCache.length >= 25) {
          _highResVideoCache.remove(_highResVideoCache.keys.first);
        }
        _highResVideoCache[assetId] = bytes;
        _saveHighResToDisk(assetId, bytes);
        final dims = parseJpegDimensions(bytes);
        if (dims != null && dims.height > 0) {
          _thumbnailAspectRatioCache[assetId] = dims.width / dims.height;
        }
        completer.complete(bytes);
        return bytes;
      }
    } catch (e) {
      debugPrint(
          '[ThumbnailService] getHighResVideoThumbnail overall error: $e');
    } finally {
      _highResInFlight.remove(assetId);
    }

    completer.complete(null);
    return null;
  }

  void _pruneCancelledGridHiResQueue() {
    if (_gridHiResQueue.isEmpty) return;
    final retained = <_GridHiResRequest>[];
    while (_gridHiResQueue.isNotEmpty) {
      final req = _gridHiResQueue.removeFirst();
      if (req.isCancelled?.call() == true) {
        if (!req.completer.isCompleted) {
          req.completer.complete(null);
        }
      } else {
        retained.add(req);
      }
    }
    _gridHiResQueue.addAll(retained);
  }

  /// Extracts an ephemeral high-resolution thumbnail for a visible photo tile
  /// without persisting to disk or retaining it in [_memoryCache].
  Future<Uint8List?> getGridHiResPhotoThumbnail(
    String assetId, {
    required String filePath,
    int size = 1024,
    bool Function()? isCancelled,
  }) {
    if (isCancelled?.call() == true || filePath.isEmpty) {
      return Future.value(null);
    }
    _pruneCancelledGridHiResQueue();
    final completer = Completer<Uint8List?>();
    _gridHiResQueue.add(
      _GridHiResRequest(
        assetId: assetId,
        filePath: filePath,
        size: size,
        isVideo: false,
        isCancelled: isCancelled,
        completer: completer,
      ),
    );
    _processGridHiResQueue();
    return completer.future;
  }

  /// Extracts an ephemeral high-resolution frame for a visible video tile
  /// without persisting to disk or retaining it in [_highResVideoCache].
  Future<Uint8List?> getGridHiResVideoThumbnail(
    String assetId, {
    required String filePath,
    int size = 960,
    bool Function()? isCancelled,
  }) {
    if (isCancelled?.call() == true) {
      return Future.value(null);
    }
    final cached = _highResVideoCache[assetId];
    if (cached != null && cached.isNotEmpty) {
      return Future.value(cached);
    }
    _pruneCancelledGridHiResQueue();
    final completer = Completer<Uint8List?>();
    _gridHiResQueue.add(
      _GridHiResRequest(
        assetId: assetId,
        filePath: filePath,
        size: size,
        isVideo: true,
        isCancelled: isCancelled,
        completer: completer,
      ),
    );
    _processGridHiResQueue();
    return completer.future;
  }

  void _processGridHiResQueue() {
    if (_activeWorkers > 0 || _queue.isNotEmpty) return;
    while (_activeGridHiResWorkers < _maxGridHiResConcurrent &&
        _gridHiResQueue.isNotEmpty) {
      _activeGridHiResWorkers++;
      _runGridHiResWorker();
    }
  }

  Future<void> _runGridHiResWorker() async {
    try {
      while (_gridHiResQueue.isNotEmpty) {
        if (_activeWorkers > 0 || _queue.isNotEmpty) break;
        final req = _gridHiResQueue.removeFirst();
        if (req.completer.isCompleted) continue;
        if (req.isCancelled?.call() == true) {
          req.completer.complete(null);
          continue;
        }
        Uint8List? bytes;
        try {
          if (!req.isVideo) {
            try {
              bytes = await _nativeChannel
                  .invokeMethod<Uint8List>(
                    'getImageThumbnail',
                    {
                      'path': req.filePath,
                      'assetId': req.assetId,
                      'size': req.size,
                      'lowPriority': true,
                    },
                  )
                  .timeout(const Duration(seconds: 4), onTimeout: () => null);
            } catch (_) {}
          } else {
            try {
              bytes = await _nativeChannel
                  .invokeMethod<Uint8List>(
                    'getVideoThumbnail',
                    {
                      'path': req.filePath,
                      'assetId': req.assetId,
                      'size': req.size,
                      'lowPriority': true,
                    },
                  )
                  .timeout(const Duration(seconds: 4), onTimeout: () => null);
            } catch (_) {}

            if ((bytes == null || bytes.isEmpty) &&
                req.isCancelled?.call() != true) {
              final entity = _entityCache[req.assetId] ??
                  await AssetEntity.fromId(req.assetId);
              if (entity != null && req.isCancelled?.call() != true) {
                try {
                  final w = entity.orientatedWidth > 0
                      ? entity.orientatedWidth
                      : entity.width;
                  final h = entity.orientatedHeight > 0
                      ? entity.orientatedHeight
                      : entity.height;
                  final maxDim = (w > 0 && h > 0) ? (w > h ? w : h) : req.size;
                  final scale = maxDim > req.size ? req.size / maxDim : 1.0;
                  final targetW = (w > 0)
                      ? (w * scale).toInt().clamp(2, req.size)
                      : req.size;
                  final targetH = (h > 0)
                      ? (h * scale).toInt().clamp(2, req.size)
                      : req.size;
                  bytes = await entity
                      .thumbnailDataWithSize(
                        ThumbnailSize(targetW, targetH),
                        quality: 92,
                      )
                      .timeout(
                        const Duration(seconds: 4),
                        onTimeout: () => null,
                      );
                } catch (_) {}
              }
            }
          }
        } catch (e) {
          debugPrint('[ThumbnailService] getGridHiRes error: $e');
        }

        if (!req.completer.isCompleted) {
          if (req.isCancelled?.call() == true ||
              bytes == null ||
              bytes.isEmpty) {
            req.completer.complete(null);
          } else {
            req.completer.complete(bytes);
          }
        }
      }
    } finally {
      _activeGridHiResWorkers--;
      if (_gridHiResQueue.isNotEmpty &&
          _activeWorkers == 0 &&
          _queue.isEmpty) {
        _processGridHiResQueue();
      }
    }
  }

  /// Parses physical pixel dimensions directly from JPEG markers (SOF0/SOF2).
  static ui.Size? parseJpegDimensions(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
    var i = 2;
    while (i + 8 < bytes.length) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = bytes[i + 1];
      if (marker == 0xC0 || marker == 0xC2) {
        final h = (bytes[i + 5] << 8) | bytes[i + 6];
        final w = (bytes[i + 7] << 8) | bytes[i + 8];
        return ui.Size(w.toDouble(), h.toDouble());
      }
      if (marker == 0xD9 || marker == 0xDA) break;
      final len = (bytes[i + 2] << 8) | bytes[i + 3];
      if (len < 2) break;
      i += 2 + len;
    }
    return null;
  }

  Future<Uint8List?> _extractNativeVideoThumbnail(String filePath,
      {String? assetId}) async {
    try {
      final bytes = await _nativeChannel.invokeMethod<Uint8List>(
        'getVideoThumbnail',
        {'path': filePath, 'assetId': assetId, 'size': _videoThumbnailSize},
      );
      return bytes;
    } catch (e) {
      debugPrint(
          '[ThumbnailService] Native video thumbnail extraction failed for $filePath: $e');
      return null;
    }
  }

  Future<Uint8List?> _extractNativeImageThumbnail(String filePath,
      {String? assetId}) async {
    try {
      final bytes = await _nativeChannel.invokeMethod<Uint8List>(
        'getImageThumbnail',
        {'path': filePath, 'assetId': assetId, 'size': _thumbnailSize},
      );
      return bytes;
    } catch (e) {
      debugPrint(
          '[ThumbnailService] Native image thumbnail extraction failed for $filePath: $e');
      return null;
    }
  }

  /// Extracts a video frame at a specific timestamp for seekbar preview.
  Future<Uint8List?> getVideoFrame({
    required String filePath,
    required Duration time,
    int width = 256,
    int height = 256,
    bool exact = false,
  }) async {
    final bucket =
        exact ? (time.inMilliseconds ~/ 50) : (time.inMilliseconds ~/ 250);
    final cacheKey = exact
        ? '$filePath:exact:$bucket:${width}x$height'
        : '$filePath:$bucket:${width}x$height';
    final cached = _videoFrameCache[cacheKey];
    if (cached != null) return cached;

    Uint8List? result;
    try {
      final bytes = await _nativeChannel.invokeMethod<Uint8List>(
        'getVideoFrame',
        {
          'path': filePath,
          'timeUs': time.inMicroseconds,
          'width': width,
          'height': height,
          'exact': exact,
        },
      );
      if (bytes != null && bytes.isNotEmpty) {
        result = bytes;
      }
    } catch (e) {
      debugPrint(
          '[ThumbnailService] Native getVideoFrame failed for $filePath: $e');
    }

    if (result != null && result.isNotEmpty) {
      if (_videoFrameCache.length >= 80) {
        _videoFrameCache.remove(_videoFrameCache.keys.first);
      }
      _videoFrameCache[cacheKey] = result;
      return result;
    }
    return null;
  }

  /// Releases the cached native video frame retriever used during scrubbing.
  Future<void> releaseVideoFrameRetriever() async {
    try {
      await _nativeChannel.invokeMethod<void>('releaseVideoFrameRetriever');
    } catch (_) {}
  }

  Future<Directory> _getCacheDirectory() {
    if (_cacheDir != null) return Future.value(_cacheDir!);
    return _cacheDirFuture ??= _initCacheDirectory().whenComplete(() {
      _cacheDirFuture = null;
    });
  }

  Future<Directory> _initCacheDirectory() async {
    if (_cacheDir != null && await _cacheDir!.exists()) return _cacheDir!;
    String? basePath;

    try {
      final extDirs = await getExternalCacheDirectories();
      if (extDirs != null && extDirs.isNotEmpty) {
        final extPath = extDirs.first.path;
        final testDir = Directory(p.join(extPath, 'thumbnails_v3'));
        if (!await testDir.exists()) {
          await testDir.create(recursive: true);
        }
        basePath = extPath;
      }
    } catch (_) {}

    if (basePath == null) {
      try {
        final appCache = await getApplicationCacheDirectory();
        basePath = appCache.path;
      } catch (_) {
        try {
          basePath = (await getApplicationSupportDirectory()).path;
        } catch (_) {
          try {
            basePath = (await getTemporaryDirectory()).path;
          } catch (_) {
            basePath = Directory.systemTemp.path;
          }
        }
      }
    }

    final dir = Directory(p.join(basePath, 'thumbnails_v3'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      try {
        final oldDir = Directory(p.join(basePath, 'thumbnails'));
        if (await oldDir.exists()) {
          await oldDir.delete(recursive: true);
        }
      } catch (_) {}
    }
    _cacheDir = dir;
    _cacheDirPath = dir.path;

    _migrateLegacyThumbnails(dir);

    return dir;
  }

  void _migrateLegacyThumbnails(Directory targetDir) async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final legacyDir = Directory(p.join(supportDir.path, 'thumbnails'));
      if (legacyDir.path != targetDir.path && await legacyDir.exists()) {
        final legacyFiles = legacyDir.listSync();
        for (final f in legacyFiles) {
          if (f is File) {
            final targetPath = p.join(targetDir.path, p.basename(f.path));
            if (!File(targetPath).existsSync()) {
              await f.copy(targetPath);
            }
            await f.delete();
          }
        }
        await legacyDir.delete(recursive: true);
      }
    } catch (_) {}
  }

  String _cacheFileName(String assetId) {
    final safe = assetId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return 'thumb_${assetId.hashCode.abs()}_$safe.bin';
  }

  Future<File> _fileForAsset(String assetId) async {
    final dir = await _getCacheDirectory();
    return File(p.join(dir.path, _cacheFileName(assetId)));
  }

  void _pruneCancelledThumbnailQueue() {
    if (_queue.length <= 64) return;
    final retained = <_ThumbnailRequest>[];
    while (_queue.isNotEmpty) {
      final req = _queue.removeFirst();
      if (req.isAllCancelled) {
        _inFlight.remove(req.id);
        _queuedOrInFlightRequests.remove(req.id);
        if (!req.completer.isCompleted) {
          req.completer.complete(null);
        }
      } else {
        retained.add(req);
      }
    }
    _queue.addAll(retained);
  }

  /// Returns cached thumbnail bytes from memory or disk, or fetches
  /// from PhotoManager / native video frame extractor and persists to disk.
  Future<Uint8List?> getThumbnail(
    String assetId, {
    String? filePath,
    bool isVideo = false,
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() == true) return null;

    final cached = _memoryCache[assetId];
    if (cached != null) return cached;

    final inFlight = _inFlight[assetId];
    if (inFlight != null) {
      _queuedOrInFlightRequests[assetId]?.cancelPredicates.add(isCancelled);
      return inFlight.future;
    }

    final diskFile = getIndexedDiskFile(assetId);
    if (diskFile != null) {
      final completer = Completer<Uint8List?>();
      _inFlight[assetId] = completer;
      _readDiskCacheFile(
        diskFile,
        assetId,
        completer,
        filePath: filePath,
        isVideo: isVideo,
        isCancelled: isCancelled,
      );
      return completer.future;
    }

    if (!_diskIndexReady) {
      final dirPath = _cacheDirPath ?? _cacheDir?.path;
      if (dirPath != null) {
        final candidateFile = File(p.join(dirPath, _cacheFileName(assetId)));
        final completer = Completer<Uint8List?>();
        _inFlight[assetId] = completer;
        _readDiskCacheFile(
          candidateFile,
          assetId,
          completer,
          filePath: filePath,
          isVideo: isVideo,
          isCancelled: isCancelled,
          isIndexed: false,
        );
        return completer.future;
      }
    }

    _pruneCancelledThumbnailQueue();
    final completer = Completer<Uint8List?>();
    final req = _ThumbnailRequest(
      assetId,
      completer,
      filePath: filePath,
      isVideo: isVideo,
      isCancelled: isCancelled,
    );
    _inFlight[assetId] = completer;
    _queuedOrInFlightRequests[assetId] = req;
    _queue.add(req);
    _processQueue();
    return completer.future;
  }

  void _readDiskCacheFile(
    File file,
    String assetId,
    Completer<Uint8List?> completer, {
    String? filePath,
    bool isVideo = false,
    bool Function()? isCancelled,
    bool isIndexed = true,
  }) async {
    final gen = _diskIndexGeneration;
    try {
      if (isIndexed || await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          if (!isIndexed && gen == _diskIndexGeneration) {
            _diskCachedFileNames.add(_cacheFileName(assetId));
          }
          _putInMemory(assetId, bytes);
          _inFlight.remove(assetId);
          _queuedOrInFlightRequests.remove(assetId);
          if (!completer.isCompleted) {
            completer.complete(bytes);
          }
          return;
        }
      }
    } catch (_) {
      if (isIndexed) {
        evictDiskCacheIndex(assetId);
      }
    }
    _inFlight.remove(assetId);
    _queuedOrInFlightRequests.remove(assetId);
    if (isCancelled?.call() == true) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      return;
    }
    _pruneCancelledThumbnailQueue();
    final fallbackCompleter = Completer<Uint8List?>();
    final req = _ThumbnailRequest(
      assetId,
      fallbackCompleter,
      filePath: filePath,
      isVideo: isVideo,
      isCancelled: isCancelled,
    );
    _inFlight[assetId] = fallbackCompleter;
    _queuedOrInFlightRequests[assetId] = req;
    _queue.add(req);
    _processQueue();
    final fallbackResult = await fallbackCompleter.future;
    if (!completer.isCompleted) {
      completer.complete(fallbackResult);
    }
  }

  void _processQueue() {
    while (_activeWorkers < _maxConcurrent && _queue.isNotEmpty) {
      _activeWorkers++;
      _runWorker();
    }
  }

  Future<void> _runWorker() async {
    try {
      while (_queue.isNotEmpty) {
        // FIFO order decodes top visible tiles before lower cacheExtent tiles,
        // while scrolled-past unmounted tiles are skipped immediately via isAllCancelled.
        final req = _queue.removeFirst();
        if (req.completer.isCompleted) {
          _inFlight.remove(req.id);
          _queuedOrInFlightRequests.remove(req.id);
          continue;
        }
        if (req.isAllCancelled) {
          _inFlight.remove(req.id);
          _queuedOrInFlightRequests.remove(req.id);
          req.completer.complete(null);
          continue;
        }
        try {
          await _processRequest(req);
        } catch (e) {
          debugPrint(
              '[ThumbnailService] Error processing request ${req.id}: $e');
          if (!req.completer.isCompleted) {
            req.completer.complete(null);
          }
          _inFlight.remove(req.id);
          _queuedOrInFlightRequests.remove(req.id);
        }
      }
    } finally {
      _activeWorkers--;
      if (_queue.isNotEmpty && _activeWorkers < _maxConcurrent) {
        _processQueue();
      } else if (_activeWorkers == 0 && _queue.isEmpty) {
        _processGridHiResQueue();
      }
    }
  }

  Future<void> _processRequest(_ThumbnailRequest req) async {
    try {
      final diskFile = await _fileForAsset(req.id);
      if (await diskFile.exists()) {
        final diskBytes = await diskFile.readAsBytes();
        if (diskBytes.isNotEmpty) {
          _diskCachedFileNames.add(_cacheFileName(req.id));
          _putInMemory(req.id, diskBytes);
          _inFlight.remove(req.id);
          _queuedOrInFlightRequests.remove(req.id);
          req.completer.complete(diskBytes);
          return;
        }
      }
    } catch (e) {
      debugPrint(
          '[ThumbnailService] Error reading disk cache for ${req.id}: $e');
    }

    Uint8List? bytes;

    final isVideo = req.isVideo ||
        (req.filePath != null &&
            (MediaScannerService.isSupportedVideo(req.filePath!) ||
                req.filePath!.toLowerCase().endsWith('.webm') ||
                req.filePath!.toLowerCase().endsWith('.mkv') ||
                req.filePath!.toLowerCase().endsWith('.mov') ||
                req.filePath!.toLowerCase().endsWith('.mp4')));

    try {
      if (req.filePath != null && PsdService.isPsd(req.filePath!)) {
        try {
          bytes = await PsdService.instance.decodeThumbnail(
            req.filePath!,
            maxDimension: _thumbnailSize,
          );
          unawaited(PsdService.instance.prewarmPsdDocument(req.filePath!));
        } catch (e) {
          debugPrint(
              '[ThumbnailService] Error decoding PSD thumbnail for ${req.filePath}: $e');
        }
      } else if (isVideo) {
        String? targetPath = req.filePath;
        if (targetPath == null || targetPath.isEmpty) {
          final entity =
              _entityCache[req.id] ?? await AssetEntity.fromId(req.id);
          if (entity != null) {
            final f = await entity.file ?? await entity.originFile;
            targetPath = f?.path;
          }
        }

        if (targetPath != null && targetPath.isNotEmpty) {
          try {
            bytes =
                await _extractNativeVideoThumbnail(targetPath, assetId: req.id)
                    .timeout(const Duration(seconds: 4), onTimeout: () => null);
          } catch (_) {}
        }

        if (bytes == null || bytes.isEmpty) {
          final entity =
              _entityCache[req.id] ?? await AssetEntity.fromId(req.id);
          if (entity != null) {
            try {
              final w = entity.orientatedWidth > 0
                  ? entity.orientatedWidth
                  : entity.width;
              final h = entity.orientatedHeight > 0
                  ? entity.orientatedHeight
                  : entity.height;
              final maxDim =
                  (w > 0 && h > 0) ? (w > h ? w : h) : _thumbnailSize;
              final scale =
                  maxDim > _thumbnailSize ? _thumbnailSize / maxDim : 1.0;
              final targetW = (w > 0)
                  ? (w * scale).toInt().clamp(2, _thumbnailSize)
                  : _thumbnailSize;
              final targetH = (h > 0)
                  ? (h * scale).toInt().clamp(2, _thumbnailSize)
                  : _thumbnailSize;
              bytes = await entity
                  .thumbnailDataWithSize(
                    ThumbnailSize(targetW, targetH),
                    quality: _thumbnailQuality,
                  )
                  .timeout(const Duration(seconds: 3), onTimeout: () => null);
            } catch (_) {}
          }
        }
      } else {
        // Subsample large images natively before falling back to Dart decoding.
        if (req.filePath != null && req.filePath!.isNotEmpty) {
          try {
            bytes = await _extractNativeImageThumbnail(req.filePath!,
                    assetId: req.id)
                .timeout(const Duration(seconds: 4), onTimeout: () => null);
          } catch (_) {}
        }

        if (bytes == null || bytes.isEmpty) {
          final entity =
              _entityCache[req.id] ?? await AssetEntity.fromId(req.id);
          if (entity != null) {
            try {
              bytes = await entity
                  .thumbnailDataWithSize(
                    const ThumbnailSize.square(_thumbnailSize),
                    quality: _thumbnailQuality,
                  )
                  .timeout(const Duration(seconds: 4), onTimeout: () => null);
            } catch (_) {}
          }
        }

        if ((bytes == null || bytes.isEmpty) && req.filePath != null) {
          try {
            final file = File(req.filePath!);
            if (await file.exists()) {
              final raw = await file.readAsBytes();
              if (raw.isNotEmpty) {
                final codec = await ui.instantiateImageCodec(
                  raw,
                  targetWidth: _thumbnailSize,
                );
                final frame = await codec.getNextFrame();
                final byteData = await frame.image
                    .toByteData(format: ui.ImageByteFormat.png);
                if (byteData != null) {
                  bytes = byteData.buffer.asUint8List();
                }
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint(
          '[ThumbnailService] Error processing thumbnail for ${req.id}: $e');
      bytes = null;
    }

    if (bytes != null && bytes.isNotEmpty) {
      _putInMemory(req.id, bytes);
      _saveToDisk(req.id, bytes);
    }
    _inFlight.remove(req.id);
    _queuedOrInFlightRequests.remove(req.id);
    if (!req.completer.isCompleted) {
      req.completer.complete(bytes);
    }
  }

  Future<void> _writeBytesAtomic(
      Directory dir, String fileName, Uint8List bytes) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final targetPath = p.join(dir.path, fileName);
    final targetFile = File(targetPath);
    final tmpFile =
        File('$targetPath.${DateTime.now().microsecondsSinceEpoch}.tmp');
    await tmpFile.writeAsBytes(bytes, flush: false);
    try {
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tmpFile.rename(targetPath);
    } catch (_) {
      // Fallback if atomic rename encounters filesystem locking.
      await targetFile.writeAsBytes(bytes, flush: false);
      try {
        if (await tmpFile.exists()) await tmpFile.delete();
      } catch (_) {}
    }
  }

  Future<void> writeDiskCacheBytes(String fileName, Uint8List bytes) async {
    final dir = await _getCacheDirectory();
    await _writeBytesAtomic(dir, fileName, bytes);
    registerDiskCacheFileName(fileName);
  }

  void _saveToDisk(String assetId, Uint8List bytes) async {
    final fileName = _cacheFileName(assetId);
    _diskCachedFileNames.add(fileName);
    try {
      final dir = await _getCacheDirectory();
      await _writeBytesAtomic(dir, fileName, bytes);
    } catch (e) {
      debugPrint('[ThumbnailService] Failed to persist thumbnail $assetId: $e');
    }
  }

  void _saveHighResToDisk(String assetId, Uint8List bytes) async {
    final fileName = _highResCacheFileName(assetId);
    _diskCachedFileNames.add(fileName);
    try {
      final dir = await _getCacheDirectory();
      await _writeBytesAtomic(dir, fileName, bytes);
    } catch (e) {
      debugPrint(
          '[ThumbnailService] Failed to persist high-res thumbnail $assetId: $e');
    }
  }

  void _putInMemory(String id, Uint8List bytes) {
    while (_memoryCache.length >= _maxMemoryEntries) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[id] = bytes;
    final size = parseJpegDimensions(bytes);
    if (size != null && size.height > 0) {
      _thumbnailAspectRatioCache[id] = size.width / size.height;
    }
  }

  /// Remove a single entry from memory and disk (e.g., after deletion).
  Future<void> invalidate(String assetId) async {
    _diskCachedFileNames.remove(_cacheFileName(assetId));
    _diskCachedFileNames.remove(_highResCacheFileName(assetId));
    _memoryCache.remove(assetId);
    _highResVideoCache.remove(assetId);
    _thumbnailAspectRatioCache.remove(assetId);
    _inFlight.remove(assetId);
    _queuedOrInFlightRequests.remove(assetId);
    _highResInFlight.remove(assetId);
    _entityCache.remove(assetId);
    try {
      final file = await _fileForAsset(assetId);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    try {
      final hrFile = getCachedHighResFile(assetId);
      if (hrFile != null && await hrFile.exists()) {
        await hrFile.delete();
      }
    } catch (_) {}
  }

  /// Trims in-memory cache to free up RAM when the application is minimized or backgrounded.
  void trimMemory() {
    _memoryCache.clear();
    _highResVideoCache.clear();
    _previewMemoryCache.clear();
    _thumbnailAspectRatioCache.clear();
    _videoFrameCache.clear();
    PsdService.instance.clearMemoryCache();
  }

  /// Wipes both in-memory cache and persistent disk cache.
  Future<void> clearAll() async {
    _diskIndexGeneration++;
    _diskIndexReady = false;
    _diskCachedFileNames.clear();
    _memoryCache.clear();
    _highResVideoCache.clear();
    _previewMemoryCache.clear();
    _previewFileNameByPathKey.clear();
    _thumbnailAspectRatioCache.clear();
    _videoFrameCache.clear();
    while (_queue.isNotEmpty) {
      final req = _queue.removeFirst();
      if (!req.completer.isCompleted) {
        req.completer.complete(null);
      }
    }
    _inFlight.clear();
    _queuedOrInFlightRequests.clear();
    _previewInFlight.clear();
    while (_gridHiResQueue.isNotEmpty) {
      final req = _gridHiResQueue.removeFirst();
      if (!req.completer.isCompleted) {
        req.completer.complete(null);
      }
    }
    _entityCache.clear();
    await PsdService.instance.clearCache();
    try {
      final dir = await _getCacheDirectory();
      if (await dir.exists()) {
        final files = dir.listSync();
        for (final entity in files) {
          if (entity is File) {
            try {
              await entity.delete();
            } on PathNotFoundException {
              // Concurrent atomic rename/cleanup removed this file already.
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ThumbnailService] Error clearing disk cache: $e');
    }
  }

  /// Calculates an itemized size breakdown of the persistent disk cache.
  Future<CacheSizeBreakdown> getCacheSizeBreakdown() async {
    int thumbBytes = 0;
    int previewBytes = 0;
    int psdBytes = 0;
    try {
      final dir = await _getCacheDirectory();
      if (await dir.exists()) {
        await for (final entity
            in dir.list(recursive: false, followLinks: false)) {
          if (entity is File) {
            final len = await entity.length();
            final name = p.basename(entity.path);
            if (name.startsWith('psd_prev_')) {
              psdBytes += len;
            } else if (name.startsWith('prev_')) {
              previewBytes += len;
            } else {
              thumbBytes += len;
            }
          }
        }
      }
    } catch (_) {}
    return CacheSizeBreakdown(
      thumbnailBytes: thumbBytes,
      previewBytes: previewBytes,
      psdBytes: psdBytes,
    );
  }

  /// Calculates total size of persistent thumbnail and preview cache on disk in bytes.
  Future<int> getCacheSizeBytes() async {
    final breakdown = await getCacheSizeBreakdown();
    return breakdown.totalBytes;
  }

  /// Formats a byte count into a human-readable cache size string.
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Returns a human-readable cache size string (e.g. "14.2 MB", "850 KB", "0 B").
  Future<String> getFormattedCacheSize() async {
    final bytes = await getCacheSizeBytes();
    return formatBytes(bytes);
  }
}

class _PhotoPreviewParams {
  const _PhotoPreviewParams(this.filePath, this.maxDimension);
  final String filePath;
  final int maxDimension;
}

Uint8List? _isolateDecodePhotoPreview(_PhotoPreviewParams params) {
  try {
    final file = File(params.filePath);
    if (!file.existsSync()) return null;
    final raw = file.readAsBytesSync();
    if (raw.isEmpty) return null;

    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;

    final baked = img.bakeOrientation(decoded);
    final maxEdge = math.max(baked.width, baked.height);
    final resized = (params.maxDimension > 0 && maxEdge > params.maxDimension)
        ? img.copyResize(
            baked,
            width: baked.width >= baked.height ? params.maxDimension : null,
            height: baked.height > baked.width ? params.maxDimension : null,
            maintainAspect: true,
            interpolation: img.Interpolation.linear,
          )
        : baked;

    return Uint8List.fromList(img.encodeJpg(resized, quality: 90));
  } catch (_) {
    return null;
  }
}
