import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/media_item.dart';

List<MediaItem> _decodeMediaCacheJson(String content) {
  final list = jsonDecode(content) as List<dynamic>;
  return list
      .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
      .toList();
}

String _encodeMediaCacheJson(List<MediaItem> items) {
  return jsonEncode(items.map((e) => e.toJson()).toList());
}

/// Persists the last media scan result to disk for instant display on startup.
class MediaCacheService {
  MediaCacheService._();
  static final MediaCacheService instance = MediaCacheService._();

  static const _fileName = 'media_list_cache.json';

  @visibleForTesting
  Directory? testDirectoryOverride;

  Future<File> _file() async {
    final dir = testDirectoryOverride ?? await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// Loads the persisted media list from disk cache.
  Future<List<MediaItem>?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final content = await f.readAsString();
      if (content.isEmpty) return null;
      return await compute(_decodeMediaCacheJson, content);
    } catch (e) {
      debugPrint('[MediaCacheService] Load failed: $e');
      return null;
    }
  }

  /// Persists the media list to disk cache asynchronously.
  Future<void> save(List<MediaItem> items) async {
    try {
      final f = await _file();
      final encoded = await compute(
        _encodeMediaCacheJson,
        List<MediaItem>.of(items),
      );
      await f.writeAsString(encoded);
    } catch (e) {
      debugPrint('[MediaCacheService] Save failed: $e');
    }
  }

  /// Deletes the cache file from disk.
  Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
