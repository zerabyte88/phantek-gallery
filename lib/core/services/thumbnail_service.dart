import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

/// Queued thumbnail fetch request for uncached items.
class _ThumbnailRequest {
  _ThumbnailRequest(this.id, this.completer, {this.filePath});
  final String id;
  final String? filePath;
  final Completer<Uint8List?> completer;
}

/// Asynchronous thumbnail cache with persistent disk storage and an in-memory layer.
///
/// Thumbnails are saved to disk on first scan/view so the app never re-decodes
/// existing thumbnails on subsequent launches. New media will automatically be
/// cached, and the cache can be wiped anytime via Settings.
class ThumbnailService {
  ThumbnailService._();
  static final ThumbnailService instance = ThumbnailService._();

  static const int _thumbnailSize = 256; // px — quality vs. memory trade-off
  static const int _maxMemoryEntries = 500;
  static const MethodChannel _nativeChannel =
      MethodChannel('com.phantek.gallery/thumbnail');

  final Map<String, Uint8List> _memoryCache = {};
  final Queue<_ThumbnailRequest> _queue = Queue();
  bool _processing = false;
  Directory? _cacheDir;

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
      debugPrint('[ThumbnailService] Native video thumbnail extraction failed for $filePath: $e');
      return null;
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
  Future<Uint8List?> getThumbnail(String assetId, {String? filePath}) async {
    // 1. Fast in-memory lookup (0ms)
    final cached = _memoryCache[assetId];
    if (cached != null) return cached;

    // 2. Persistent disk cache lookup (fast local read, skips MediaStore queue)
    try {
      final diskFile = await _fileForAsset(assetId);
      if (await diskFile.exists()) {
        final bytes = await diskFile.readAsBytes();
        if (bytes.isNotEmpty) {
          _putInMemory(assetId, bytes);
          return bytes;
        }
      }
    } catch (e) {
      debugPrint('[ThumbnailService] Error reading disk cache for $assetId: $e');
    }

    // 3. Deduplicate in-flight requests for the same id.
    final inFlight = _queue
        .cast<_ThumbnailRequest?>()
        .firstWhere((r) => r?.id == assetId, orElse: () => null);
    if (inFlight != null) return inFlight.completer.future;

    final completer = Completer<Uint8List?>();
    _queue.add(_ThumbnailRequest(assetId, completer, filePath: filePath));
    _processQueue();
    return completer.future;
  }

  void _processQueue() {
    if (_processing || _queue.isEmpty) return;
    _processing = true;
    _fetchNext();
  }

  Future<void> _fetchNext() async {
    while (_queue.isNotEmpty) {
      final req = _queue.removeFirst();
      if (req.completer.isCompleted) continue;

      Uint8List? bytes;
      try {
        final entity = await AssetEntity.fromId(req.id);
        if (entity != null) {
          bytes = await entity.thumbnailDataWithSize(
            const ThumbnailSize.square(_thumbnailSize),
            quality: 80,
          );
          if (bytes == null || bytes.isEmpty) {
            // photo_manager returned null (common on Android for .mkv, .mov, .webm).
            // Fallback to native MediaMetadataRetriever / ThumbnailUtils using origin file path!
            final file = await entity.originFile ?? await entity.file;
            if (file != null && await file.exists()) {
              bytes = await _extractNativeVideoThumbnail(file.path);
            }
          }
        }
      } catch (_) {
        bytes = null;
      }

      // If still null, try the explicitly provided filePath
      if ((bytes == null || bytes.isEmpty) && req.filePath != null) {
        try {
          final file = File(req.filePath!);
          if (await file.exists()) {
            bytes = await _extractNativeVideoThumbnail(req.filePath!);
          }
        } catch (_) {}
      }

      if (bytes != null && bytes.isNotEmpty) {
        _putInMemory(req.id, bytes);
        // Persist to disk asynchronously
        _saveToDisk(req.id, bytes);
      }
      req.completer.complete(bytes);
    }
    _processing = false;
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
