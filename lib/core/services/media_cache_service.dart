import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/media_item.dart';

/// Persists the last media scan result to disk so the gallery can render
/// immediately on the next app open without showing a loading spinner.
///
/// Usage: stale-while-revalidate
///   1. [load()] → returns last known list instantly (~10–50 ms)
///   2. Show grid immediately with cached data
///   3. Run background scan → call [save()] when done → update UI state
class MediaCacheService {
  MediaCacheService._();
  static final MediaCacheService instance = MediaCacheService._();

  static const _fileName = 'media_list_cache.json';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// Load persisted media list. Returns null if no cache or corrupt data.
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

  /// Persist media list to disk (fire-and-forget safe to call unawaited).
  Future<void> save(List<MediaItem> items) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('[MediaCacheService] Save failed: $e');
    }
  }

  /// Remove cache file (e.g., on settings reset).
  Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
