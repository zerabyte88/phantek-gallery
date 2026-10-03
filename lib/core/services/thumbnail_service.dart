import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:photo_manager/photo_manager.dart';

/// Queued thumbnail fetch request.
class _ThumbnailRequest {
  _ThumbnailRequest(this.id, this.completer);
  final String id;
  final Completer<Uint8List?> completer;
}

/// Asynchronous thumbnail cache with an isolated FIFO queue.
///
/// The queue processes requests one at a time so heavy thumbnail decoding
/// does not block the UI thread during fast scrolling.
class ThumbnailService {
  ThumbnailService._();
  static final ThumbnailService instance = ThumbnailService._();

  static const int _thumbnailSize = 256; // px — quality vs. memory trade-off
  static const int _maxCacheEntries = 800;

  final Map<String, Uint8List> _cache = {};
  final Queue<_ThumbnailRequest> _queue = Queue();
  bool _processing = false;

  /// Returns cached thumbnail bytes or fetches them asynchronously.
  Future<Uint8List?> getThumbnail(String assetId) async {
    final cached = _cache[assetId];
    if (cached != null) return cached;

    // Deduplicate in-flight requests for the same id.
    final inFlight = _queue
        .cast<_ThumbnailRequest?>()
        .firstWhere((r) => r?.id == assetId, orElse: () => null);
    if (inFlight != null) return inFlight.completer.future;

    final completer = Completer<Uint8List?>();
    _queue.add(_ThumbnailRequest(assetId, completer));
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
        }
      } catch (_) {
        bytes = null;
      }

      if (bytes != null) {
        _evictIfNeeded();
        _cache[req.id] = bytes;
      }
      req.completer.complete(bytes);
    }
    _processing = false;
  }

  void _evictIfNeeded() {
    // ponytail: simple FIFO eviction; upgrade to LRU if OOM issues arise.
    while (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Remove a single entry from cache (e.g., after deletion).
  void invalidate(String assetId) => _cache.remove(assetId);

  /// Wipe the entire cache (e.g., on low-memory pressure).
  void clearAll() => _cache.clear();
}
