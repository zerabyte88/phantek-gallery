import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'media_scanner_service.dart';

/// Queued thumbnail fetch request for uncached items.
class _ThumbnailRequest {
  _ThumbnailRequest(this.id, this.completer,
      {this.filePath, this.isVideo = false});
  final String id;
  final String? filePath;
  final bool isVideo;
  final Completer<Uint8List?> completer;
}

/// Asynchronous thumbnail cache with persistent disk storage, multi-worker pool,
/// and an in-memory layer.
///
/// Features:
/// - Fast in-memory lookup (0ms)
/// - Persistent disk caching
/// - 4 concurrent background worker pool (never stalls the UI or queue)
/// - Zero origin-file copy overhead: extracts video frames directly via native MediaMetadataRetriever
/// - Direct asset entity registration to avoid redundant IPC calls
class ThumbnailService {
  ThumbnailService._();
  static final ThumbnailService instance = ThumbnailService._();

  static const int _thumbnailSize = 256; // px — quality vs. memory trade-off
  static const int _maxMemoryEntries = 500;
  static const int _maxConcurrent = 4;
  static const MethodChannel _nativeChannel =
      MethodChannel('com.phantek.gallery/thumbnail');

  final Map<String, Uint8List> _memoryCache = {};
  final Map<String, Completer<Uint8List?>> _inFlight = {};
  final Map<String, AssetEntity> _entityCache = {};
  final Queue<_ThumbnailRequest> _queue = Queue();
  int _activeWorkers = 0;
  Directory? _cacheDir;
  String? _cacheDirPath;

  /// Pre-initializes the persistent cache directory at application launch.
  static Future<void> init() async {
    await instance._getCacheDirectory();
  }

  /// Synchronously returns the cached File on disk if it already exists, or null.
  File? getCachedFile(String assetId) {
    final dirPath = _cacheDirPath ?? _cacheDir?.path;
    if (dirPath == null) return null;
    final file = File(p.join(dirPath, _cacheFileName(assetId)));
    return file.existsSync() ? file : null;
  }

  /// Register pre-discovered AssetEntities to avoid IPC lookups.
  void registerEntities(Iterable<AssetEntity> entities) {
    for (final e in entities) {
      _entityCache[e.id] = e;
    }
  }

  /// Fast synchronous lookup in the in-memory cache (0ms).
  Uint8List? getMemoryThumbnail(String assetId) => _memoryCache[assetId];

  Future<Uint8List?> _extractNativeVideoThumbnail(String filePath) async {
    try {
      final bytes = await _nativeChannel.invokeMethod<Uint8List>(
        'getVideoThumbnail',
        {'path': filePath, 'size': _thumbnailSize},
      );
      return bytes;
    } catch (e) {
      debugPrint(
          '[ThumbnailService] Native video thumbnail extraction failed for $filePath: $e');
      return null;
    }
  }

  /// Extracts a single video frame via media_kit's MPV engine.
  /// Handles exotic codecs and containers (VP9, HEVC 10-bit, AV1, MKV, WebM, AVI, FLV, TS)
  /// that Android's native MediaMetadataRetriever cannot decode.
  Future<Uint8List?> _extractFrameViaMpv(String filePath) async {
    final player = Player();
    try {
      if (player.platform is NativePlayer) {
        final native = player.platform as NativePlayer;
        final dir = await _getCacheDirectory();
        final outDir =
            Directory(p.join(dir.path, 'mpv_tmp_${filePath.hashCode.abs()}'));
        if (!await outDir.exists()) {
          await outDir.create(recursive: true);
        }

        // Configure headless image extraction via MPV's image video-out driver
        await native.setProperty('ao', 'null');
        await native.setProperty('vo', 'image');
        await native.setProperty('vo-image-format', 'jpg');
        await native.setProperty('vo-image-jpeg-quality', '80');
        await native.setProperty('vo-image-outdir', outDir.path);
        await native.setProperty('frames', '1');
        await native.setProperty('vf',
            'scale=256:256:force_original_aspect_ratio=decrease:force_divisible_by=2');
        await native.setProperty('hwdec', 'auto-copy');

        await player.open(Media(filePath), play: true);

        // Wait up to 1.5 seconds for the single frame to be written
        File? generated;
        for (int i = 0; i < 15; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (!await outDir.exists()) break;
          final files = outDir.listSync();
          for (final f in files) {
            if (f is File &&
                (f.path.endsWith('.jpg') || f.path.endsWith('.jpeg'))) {
              generated = f;
              break;
            }
          }
          if (generated != null) break;
        }

        if (generated != null && await generated.exists()) {
          final bytes = await generated.readAsBytes();
          try {
            await outDir.delete(recursive: true);
          } catch (_) {}
          if (bytes.isNotEmpty) return bytes;
        }

        // Fallback: try player.screenshot
        try {
          final screenshotBytes =
              await player.screenshot(format: 'image/jpeg');
          if (screenshotBytes != null && screenshotBytes.isNotEmpty) {
            try {
              await outDir.delete(recursive: true);
            } catch (_) {}
            return screenshotBytes;
          }
        } catch (_) {}

        try {
          await outDir.delete(recursive: true);
        } catch (_) {}
      }
      return null;
    } catch (e) {
      debugPrint('[ThumbnailService] MPV frame extraction failed: $e');
      return null;
    } finally {
      await player.dispose();
    }
  }

  Future<Directory> _getCacheDirectory() async {
    if (_cacheDir != null) return _cacheDir!;
    String? basePath;
    try {
      basePath = (await getApplicationSupportDirectory()).path;
    } catch (_) {
      try {
        basePath = (await getTemporaryDirectory()).path;
      } catch (_) {
        basePath = Directory.systemTemp.path;
      }
    }
    final dir = Directory(p.join(basePath, 'thumbnails'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    _cacheDirPath = dir.path;
    return dir;
  }

  String _cacheFileName(String assetId) {
    final safe = assetId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return 'thumb_${assetId.hashCode.abs()}_$safe.bin';
  }

  Future<File> _fileForAsset(String assetId) async {
    final dir = await _getCacheDirectory();
    return File(p.join(dir.path, _cacheFileName(assetId)));
  }

  /// Returns cached thumbnail bytes from memory or disk, or fetches
  /// from PhotoManager / native video frame extractor and persists to disk.
  Future<Uint8List?> getThumbnail(
    String assetId, {
    String? filePath,
    bool isVideo = false,
  }) async {
    // 1. Fast in-memory lookup (0ms)
    final cached = _memoryCache[assetId];
    if (cached != null) return cached;

    // 2. Check if request is already in-flight
    final inFlight = _inFlight[assetId];
    if (inFlight != null) return inFlight.future;

    // 3. Fast persistent disk cache lookup (SKIPS the generator queue entirely!)
    final diskFile = getCachedFile(assetId);
    if (diskFile != null) {
      final completer = Completer<Uint8List?>();
      _inFlight[assetId] = completer;
      _readDiskCacheFile(diskFile, assetId, completer);
      return completer.future;
    }

    final completer = Completer<Uint8List?>();
    _inFlight[assetId] = completer;
    _queue.add(_ThumbnailRequest(
      assetId,
      completer,
      filePath: filePath,
      isVideo: isVideo,
    ));
    _processQueue();
    return completer.future;
  }

  void _readDiskCacheFile(
    File file,
    String assetId,
    Completer<Uint8List?> completer,
  ) async {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) {
        _putInMemory(assetId, bytes);
        _inFlight.remove(assetId);
        completer.complete(bytes);
        return;
      }
    } catch (_) {}
    _inFlight.remove(assetId);
    final fallbackCompleter = Completer<Uint8List?>();
    _inFlight[assetId] = fallbackCompleter;
    _queue.add(_ThumbnailRequest(assetId, fallbackCompleter));
    _processQueue();
    completer.complete(await fallbackCompleter.future);
  }

  void _processQueue() {
    while (_activeWorkers < _maxConcurrent && _queue.isNotEmpty) {
      _activeWorkers++;
      _runWorker();
    }
  }

  Future<void> _runWorker() async {
    while (_queue.isNotEmpty) {
      final req = _queue.removeFirst();
      if (req.completer.isCompleted) {
        _inFlight.remove(req.id);
        continue;
      }
      await _processRequest(req);
    }
    _activeWorkers--;
    if (_queue.isNotEmpty && _activeWorkers < _maxConcurrent) {
      _processQueue();
    }
  }

  Future<void> _processRequest(_ThumbnailRequest req) async {
    // Check persistent disk cache first (moved from getThumbnail hot path)
    try {
      final diskFile = await _fileForAsset(req.id);
      if (await diskFile.exists()) {
        final diskBytes = await diskFile.readAsBytes();
        if (diskBytes.isNotEmpty) {
          _putInMemory(req.id, diskBytes);
          _inFlight.remove(req.id);
          req.completer.complete(diskBytes);
          return;
        }
      }
    } catch (e) {
      debugPrint('[ThumbnailService] Error reading disk cache for ${req.id}: $e');
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
      if (isVideo) {
        String? targetPath = req.filePath;
        if (targetPath == null || targetPath.isEmpty) {
          final entity =
              _entityCache[req.id] ?? await AssetEntity.fromId(req.id);
          if (entity != null) {
            final f = await entity.file ?? await entity.originFile;
            targetPath = f?.path;
          }
        }

        // 1. Direct native extractor (fast MediaStore cache + MediaMetadataRetriever for 4K/2K/1080p, HEVC, VP9)
        if (targetPath != null && targetPath.isNotEmpty) {
          try {
            bytes = await _extractNativeVideoThumbnail(targetPath)
                .timeout(const Duration(seconds: 6), onTimeout: () => null);
          } catch (_) {}
        }

        // 2. If native extractor returned null, try photo_manager thumbnailDataWithSize
        if (bytes == null || bytes.isEmpty) {
          final entity =
              _entityCache[req.id] ?? await AssetEntity.fromId(req.id);
          if (entity != null) {
            try {
              bytes = await entity
                  .thumbnailDataWithSize(
                    const ThumbnailSize.square(_thumbnailSize),
                    quality: 80,
                  )
                  .timeout(const Duration(seconds: 3), onTimeout: () => null);
            } catch (_) {}
          }
        }

        // 3. Last resort: use media_kit (MPV/FFmpeg) to extract a single frame.
        //    Handles exotic formats/codecs (MKV, WebM, AVI, FLV, TS, VP9, AV1, HEVC 10-bit)
        if ((bytes == null || bytes.isEmpty) &&
            targetPath != null &&
            targetPath.isNotEmpty) {
          try {
            bytes = await _extractFrameViaMpv(targetPath)
                .timeout(const Duration(seconds: 5), onTimeout: () => null);
          } catch (_) {}
        }
      } else {
        // Photo / image:
        // 1. Try photo_manager thumbnailDataWithSize (Glide-backed)
        final entity = _entityCache[req.id] ?? await AssetEntity.fromId(req.id);
        if (entity != null) {
          try {
            bytes = await entity
                .thumbnailDataWithSize(
                  const ThumbnailSize.square(_thumbnailSize),
                  quality: 80,
                )
                .timeout(const Duration(seconds: 3), onTimeout: () => null);
          } catch (_) {}
        }

        // 2. Fallback: decode directly from local image file if photo_manager returned null
        if ((bytes == null || bytes.isEmpty) && req.filePath != null) {
          try {
            final file = File(req.filePath!);
            if (await file.exists()) {
              final raw = await file.readAsBytes();
              if (raw.isNotEmpty) {
                final codec = await ui.instantiateImageCodec(
                  raw,
                  targetWidth: _thumbnailSize,
                  // targetHeight intentionally omitted — preserves aspect ratio
                  // BoxFit.cover in the grid cell handles square cropping in the UI
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
    req.completer.complete(bytes);
  }

  void _saveToDisk(String assetId, Uint8List bytes) async {
    try {
      final dir = await _getCacheDirectory();
      final targetPath = p.join(dir.path, _cacheFileName(assetId));
      final targetFile = File(targetPath);
      final tmpFile = File('$targetPath.tmp');
      await tmpFile.writeAsBytes(bytes, flush: true);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tmpFile.rename(targetPath);
    } catch (e) {
      debugPrint('[ThumbnailService] Failed to persist thumbnail $assetId: $e');
    }
  }

  void _putInMemory(String id, Uint8List bytes) {
    while (_memoryCache.length >= _maxMemoryEntries) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[id] = bytes;
  }

  /// Remove a single entry from memory and disk (e.g., after deletion).
  Future<void> invalidate(String assetId) async {
    _memoryCache.remove(assetId);
    _inFlight.remove(assetId);
    _entityCache.remove(assetId);
    try {
      final file = await _fileForAsset(assetId);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Trims in-memory cache to free up RAM when the application is minimized or backgrounded.
  void trimMemory() {
    _memoryCache.clear();
  }

  /// Wipes both in-memory cache and persistent disk cache.
  Future<void> clearAll() async {
    _memoryCache.clear();
    _inFlight.clear();
    _entityCache.clear();
    try {
      final dir = await _getCacheDirectory();
      if (await dir.exists()) {
        final files = dir.listSync();
        for (final entity in files) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('[ThumbnailService] Error clearing disk cache: $e');
    }
  }

  /// Calculates total size of persistent thumbnail cache on disk in bytes.
  Future<int> getCacheSizeBytes() async {
    try {
      final dir = await _getCacheDirectory();
      if (!await dir.exists()) return 0;
      int total = 0;
      await for (final file in dir.list(recursive: false, followLinks: false)) {
        if (file is File) {
          total += await file.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Returns a human-readable cache size string (e.g. "14.2 MB", "850 KB", "0 B").
  Future<String> getFormattedCacheSize() async {
    final bytes = await getCacheSizeBytes();
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
