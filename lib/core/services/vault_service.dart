import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/media_item.dart';
import '../models/vault_item.dart';
import 'thumbnail_service.dart';

/// Hidden folder on external storage where vaulted items are kept safely
/// even if the application is uninstalled.
const _kVaultExternalFolder = '/storage/emulated/0/.PhantekVault';

class VaultService {
  VaultService._();
  static final VaultService instance = VaultService._();

  final List<VaultItem> _items = [];
  bool _loaded = false;

  /// Returns an unmodifiable list of all vaulted items.
  Future<List<VaultItem>> getItems() async {
    await _ensureLoaded();
    return List.unmodifiable(_items);
  }

  /// Returns the current count of items in the vault.
  Future<int> getItemCount() async {
    await _ensureLoaded();
    return _items.length;
  }

  /// Moves a single [MediaItem] into the Locked Vault.
  Future<VaultItem> moveToVault(MediaItem item) async {
    final result = await moveToVaultBatch([item]);
    if (result.isEmpty) {
      throw FileSystemException('Failed to move media to vault', item.path);
    }
    return result.first;
  }

  /// Moves multiple [MediaItem] items into the Locked Vault in batch.
  Future<List<VaultItem>> moveToVaultBatch(List<MediaItem> items) async {
    await _ensureLoaded();
    final vaultDir = await _getVaultDir();
    final List<VaultItem> addedItems = [];
    final List<String> mediaStoreIdsToDelete = [];

    for (final item in items) {
      final src = File(item.path);
      if (!await src.exists()) continue;

      final name = p.basename(item.path);
      final vaultName = '${DateTime.now().millisecondsSinceEpoch}_$name';
      final vaultPath = p.join(vaultDir.path, vaultName);

      try {
        await src.rename(vaultPath);
      } catch (_) {
        // Fallback for cross-device/filesystem moves
        await src.copy(vaultPath);
        await src.delete();
      }

      mediaStoreIdsToDelete.add(item.id);
      ThumbnailService.instance.invalidate(item.id);

      final vItem = VaultItem(
        id: item.id,
        originalPath: item.path,
        vaultPath: vaultPath,
        name: name,
        dateMoved: DateTime.now(),
        isVideo: item.isVideo,
        size: await File(vaultPath).length(),
        duration: item.duration,
        width: item.width,
        height: item.height,
        mimeType: item.mimeType,
        originalAlbumName: item.albumName,
      );

      _items.insert(0, vItem);
      addedItems.add(vItem);
    }

    // Unlink from Android MediaStore so it vanishes from public gallery
    if (mediaStoreIdsToDelete.isNotEmpty) {
      try {
        await PhotoManager.editor.deleteWithIds(mediaStoreIdsToDelete);
      } catch (_) {}
    }

    await _persist();
    return addedItems;
  }

  /// Restores a single vaulted item back to its original path.
  Future<void> restore(String vaultItemId) async {
    await restoreBatch([vaultItemId]);
  }

  /// Restores multiple vaulted items back to their original paths in batch.
  Future<void> restoreBatch(List<String> vaultItemIds) async {
    await _ensureLoaded();
    final targetIds = vaultItemIds.toSet();
    final toRemove = <VaultItem>[];

    for (final id in targetIds) {
      final idx = _items.indexWhere((e) => e.id == id);
      if (idx == -1) continue;
      final item = _items[idx];

      final dest = File(item.originalPath);
      await dest.parent.create(recursive: true);
      final vaultFile = File(item.vaultPath);

      if (await vaultFile.exists()) {
        try {
          await vaultFile.rename(item.originalPath);
        } catch (_) {
          await vaultFile.copy(item.originalPath);
          await vaultFile.delete();
        }
      }

      ThumbnailService.instance.invalidate(item.id);
      toRemove.add(item);
    }

    _items.removeWhere((e) => toRemove.contains(e));
    await _persist();
  }

  /// Permanently deletes an item from disk.
  Future<void> permanentDelete(String vaultItemId) async {
    await permanentDeleteBatch([vaultItemId]);
  }

  /// Permanently deletes multiple items from disk in batch.
  Future<void> permanentDeleteBatch(List<String> vaultItemIds) async {
    await _ensureLoaded();
    final targetIds = vaultItemIds.toSet();
    final toRemove = <VaultItem>[];

    for (final id in targetIds) {
      final idx = _items.indexWhere((e) => e.id == id);
      if (idx == -1) continue;
      final item = _items[idx];

      final f = File(item.vaultPath);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }

      ThumbnailService.instance.invalidate(item.id);
      toRemove.add(item);
    }

    _items.removeWhere((e) => toRemove.contains(e));
    await _persist();
  }

  /// Resolves the secure vault directory, ensuring it exists and contains a .nomedia file.
  Future<Directory> _getVaultDir() async {
    Directory dir = Directory(_kVaultExternalFolder);
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (_) {
      // Fallback to app-specific external or internal documents directory if direct root is restricted
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          dir = Directory(p.join(ext.path, '.PhantekVault'));
          await dir.create(recursive: true);
        } else {
          final doc = await getApplicationDocumentsDirectory();
          dir = Directory(p.join(doc.path, '.PhantekVault'));
          await dir.create(recursive: true);
        }
      } catch (_) {
        final doc = await getApplicationDocumentsDirectory();
        dir = Directory(p.join(doc.path, '.PhantekVault'));
        await dir.create(recursive: true);
      }
    }

    // Ensure .nomedia file exists to hide from media scanners
    final noMedia = File(p.join(dir.path, '.nomedia'));
    if (!await noMedia.exists()) {
      try {
        await noMedia.create();
      } catch (_) {}
    }

    return dir;
  }

  Future<File> _indexFile() async {
    final dir = await _getVaultDir();
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
      _items.clear();
      _items.addAll(list.map((e) => VaultItem.fromJson(e as Map<String, dynamic>)));
    } catch (_) {
      // Corrupt index
      _items.clear();
    }
  }

  Future<void> _persist() async {
    final f = await _indexFile();
    await f.writeAsString(jsonEncode(_items.map((e) => e.toJson()).toList()));
  }
}
