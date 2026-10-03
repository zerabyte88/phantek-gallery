import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/trash_item.dart';

/// Relative path inside external storage where trashed items are kept.
const _kTrashFolder = '.trash/PhantekGallery';

/// Manages the soft-delete / trash workflow.
///
/// When [SettingsService.settings.enableTrash] is true:
///   delete  → move file to [_kTrashFolder] and record metadata
///   restore → move file back to original path
///   purge   → permanently delete from [_kTrashFolder]
///
/// When enableTrash is false, delete is immediate (permanent).
class TrashService {
  TrashService();

  // In-memory index; persisted to a JSON sidecar in _trashDir.
  // ponytail: flat JSON is sufficient for < 10 k items; migrate to SQLite if needed.
  final List<TrashItem> _items = [];
  bool _loaded = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<List<TrashItem>> getItems() async {
    await _ensureLoaded();
    return List.unmodifiable(_items);
  }

  /// Moves [sourcePath] to trash. Throws if the file does not exist.
  Future<TrashItem> moveToTrash({
    required String id,
    required String sourcePath,
    required bool isVideo,
  }) async {
    final src = File(sourcePath);
    if (!await src.exists()) {
      throw FileSystemException('File not found', sourcePath);
    }

    final trashDir = await _getTrashDir();
    final name = p.basename(sourcePath);
    // Prefix with timestamp to avoid collisions.
    final trashName = '${DateTime.now().millisecondsSinceEpoch}_$name';
    final trashPath = p.join(trashDir.path, trashName);

    try {
      await src.rename(trashPath);
    } catch (_) {
      // Fallback for cross-device / cross-filesystem moves (EXDEV)
      await src.copy(trashPath);
      await src.delete();
    }

    // Inform MediaStore/PhotoManager that original entry is gone
    try {
      await PhotoManager.editor.deleteWithIds([id]);
    } catch (_) {}

    final item = TrashItem(
      id: id,
      originalPath: sourcePath,
      trashPath: trashPath,
      name: name,
      deletedDate: DateTime.now(),
      isVideo: isVideo,
      size: await File(trashPath).length(),
    );

    await _ensureLoaded();
    _items.add(item);
    await _persist();
    return item;
  }

  /// Restores a trashed item to its original location.
  Future<void> restore(String trashItemId) async {
    await _ensureLoaded();
    final idx = _items.indexWhere((e) => e.id == trashItemId);
    if (idx == -1) throw StateError('TrashItem $trashItemId not found');

    final item = _items[idx];
    final dest = File(item.originalPath);
    await dest.parent.create(recursive: true);
    final trashFile = File(item.trashPath);
    try {
      await trashFile.rename(item.originalPath);
    } catch (_) {
      await trashFile.copy(item.originalPath);
      await trashFile.delete();
    }

    _items.removeAt(idx);
    await _persist();
  }

  /// Permanently deletes a trashed item from disk.
  Future<void> permanentDelete(String trashItemId) async {
    await _ensureLoaded();
    final idx = _items.indexWhere((e) => e.id == trashItemId);
    if (idx == -1) throw StateError('TrashItem $trashItemId not found');

    final item = _items[idx];
    final f = File(item.trashPath);
    if (await f.exists()) await f.delete();

    _items.removeAt(idx);
    await _persist();
  }

  /// Permanently deletes ALL items in trash.
  Future<void> emptyTrash() async {
    await _ensureLoaded();
    for (final item in List.of(_items)) {
      final f = File(item.trashPath);
      if (await f.exists()) await f.delete();
    }
    _items.clear();
    await _persist();
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<Directory> _getTrashDir() async {
    // Store trash alongside the app's external files to avoid scoped-storage issues.
    String? basePath;
    try {
      if (Platform.isAndroid) {
        final external = await getExternalStorageDirectory();
        basePath = external?.path;
      }
    } catch (_) {}

    if (basePath == null) {
      try {
        basePath = (await getApplicationDocumentsDirectory()).path;
      } catch (_) {
        basePath = Directory.systemTemp.path;
      }
    }

    final dir = Directory(p.join(basePath, _kTrashFolder));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _indexFile() async {
    final dir = await _getTrashDir();
    return File(p.join(dir.path, '_index.json'));
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final f = await _indexFile();
    if (!await f.exists()) return;
    try {
      final content = await f.readAsString();
      if (content.trim().isEmpty) return;
      final list = (jsonDecode(content) as List);
      _items.addAll(list.map((e) => _fromJson(e as Map<String, dynamic>)));
    } catch (_) {
      // Corrupt index – start fresh.
      _items.clear();
    }
  }

  Future<void> _persist() async {
    final f = await _indexFile();
    await f.writeAsString(jsonEncode(_items.map(_toJson).toList()));
  }

  // ── JSON helpers ───────────────────────────────────────────────────────────

  static Map<String, dynamic> _toJson(TrashItem e) => {
        'id': e.id,
        'originalPath': e.originalPath,
        'trashPath': e.trashPath,
        'name': e.name,
        'deletedDate': e.deletedDate.toIso8601String(),
        'isVideo': e.isVideo,
        'size': e.size,
      };

  static TrashItem _fromJson(Map<String, dynamic> m) => TrashItem(
        id: m['id'] as String,
        originalPath: m['originalPath'] as String,
        trashPath: m['trashPath'] as String,
        name: m['name'] as String,
        deletedDate: DateTime.parse(m['deletedDate'] as String),
        isVideo: m['isVideo'] as bool,
        size: m['size'] as int?,
      );
}

