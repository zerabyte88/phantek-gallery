import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/media_item.dart';

/// Persists the last media scan result to disk for instant display on startup.
class MediaCacheService {
  MediaCacheService._();
  static final MediaCacheService instance = MediaCacheService._();

  static const _fileName = 'media_list_cache.json';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// Loads the persisted media list from disk cache.
  Future<List<MediaItem>?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final content = await f.readAsString();
      if (content.isEmpty) return null;
      final list = jsonDecode(content) as List;
      return list
          .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[MediaCacheService] Load failed: $e');
      return null;
    }
  }

  /// Persists the media list to disk cache asynchronously.
  Future<void> save(List<MediaItem> items) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()));
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
