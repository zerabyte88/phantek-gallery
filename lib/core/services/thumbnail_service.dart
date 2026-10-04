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
  /// Handles codecs (VP9, HEVC, AV1) that Android's native MediaMetadataRetriever cannot decode.
  Future<Uint8List?> _extractFrameViaMpv(String filePath) async {
    final player = Player();
    try {
      if (player.platform is NativePlayer) {
        final native = player.platform as NativePlayer;
        await native.setProperty('vo', 'null'); // no video output
        await native.setProperty('ao', 'null'); // no audio output
        await native.setProperty('pause', 'yes');
        await native.setProperty('video-timing-offset', '0');
      }

      await player.open(Media(filePath), play: false);
      // Seek to 1 second for a representative frame
      await player.seek(const Duration(seconds: 1));
      await Future.delayed(const Duration(milliseconds: 500));

      if (player.platform is NativePlayer) {
        final native = player.platform as NativePlayer;
        final dir = await _getCacheDirectory();
        final tmpPath = p.join(dir.path, 'mpv_frame_${filePath.hashCode.abs()}.jpg');
        await native.setProperty('screenshot-format', 'jpg');
        await native.setProperty('screenshot-jpeg-quality', '80');
        await native.command(['screenshot-to-file', tmpPath, 'video']);

        await Future.delayed(const Duration(milliseconds: 200));
        final tmpFile = File(tmpPath);
        if (await tmpFile.exists()) {
          final bytes = await tmpFile.readAsBytes();
          await tmpFile.delete();
          if (bytes.isNotEmpty) return bytes;
        }
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
        // 1. If we have a file path, directly extract video thumbnail using native extractor!
        // This takes ~15ms and NEVER triggers photo_manager scoped-cache copy!
        if (req.filePath != null && req.filePath!.isNotEmpty) {
          try {
            bytes = await _extractNativeVideoThumbnail(req.filePath!)
                .timeout(const Duration(seconds: 4), onTimeout: () => null);
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
        //    This handles VP9, WebM, HEVC that Android's MediaMetadataRetriever can't decode.
        if ((bytes == null || bytes.isEmpty) && req.filePath != null) {
          try {
            bytes = await _extractFrameViaMpv(req.filePath!);
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
      final file = await _fileForAsset(assetId);
      await file.writeAsBytes(bytes, flush: true);
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
