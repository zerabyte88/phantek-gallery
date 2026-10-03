import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart' hide FilterOption;
import '../../../core/enums/filter_option.dart';
import '../../../core/models/album.dart';
import '../../../core/models/media_item.dart';
import '../../../core/providers/media_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/trash_provider.dart';
import '../../../core/services/permission_service.dart';
import '../../../app/router.dart';
import '../../../core/utils/easter_egg_handler.dart';
import '../../../core/widgets/animated_flame_title.dart';
import '../../../core/widgets/bouncy_tap.dart';
import 'widgets/album_grid_item.dart';
import 'widgets/filter_sort_bar.dart';
import 'widgets/media_grid_item.dart';

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  final Set<String> _selected = {};
  bool _selecting = false;
  final _easterEggHandler = EasterEggTapHandler();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  // ── Permission + initial scan ──────────────────────────────────────────

  Future<void> _bootstrap() async {
    final granted =
        await PermissionService.instance.requestMediaPermissions();
    if (!mounted) return;
    if (granted) {
      ref.read(mediaListProvider.notifier).refresh();
    }
  }

  // ── Selection helpers ──────────────────────────────────────────────────

  void _toggleSelect(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _selecting = false;
      } else {
        _selected.add(id);
      }
    });
  }

  void _startSelect(String id) {
    setState(() {
      _selecting = true;
      _selected.add(id);
    });
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _selecting = false;
    });
  }

  // ── Delete selected ────────────────────────────────────────────────────

  Future<void> _deleteSelected(List<MediaItem> allItems) async {
    final settings = ref.read(settingsNotifierProvider);
    final toDelete =
        allItems.where((e) => _selected.contains(e.id)).toList();

    final confirm = await _confirmDelete(toDelete.length);
    if (!confirm || !mounted) return;

    final hasPerm = await PermissionService.instance.ensureManageStorage();
    if (!hasPerm) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Manage All Files permission is required to delete or move items to trash.'),
          ),
        );
      }
      return;
    }

    final toDeleteIds = toDelete.map((e) => e.id).toSet();
    // 1. Instantly remove from state so the gallery updates immediately
    ref.read(mediaListProvider.notifier).removeItems(toDeleteIds);
    _clearSelection();

    var successCount = 0;
    for (final item in toDelete) {
      try {
        if (settings.enableTrash) {
          await ref
              .read(trashProvider.notifier)
              .moveToTrash(id: item.id, path: item.path, isVideo: item.isVideo);
        } else {
          // Direct permanent delete.
          final f = File(item.path);
          if (await f.exists()) await f.delete();
          try {
            await PhotoManager.editor.deleteWithIds([item.id]);
          } catch (_) {}
        }
        successCount++;
      } catch (e) {
        debugPrint('Delete/trash error on ${item.path}: $e');
      }
    }
    if (mounted) {
      ref.read(mediaListProvider.notifier).refresh();
      if (successCount < toDelete.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Processed $successCount of ${toDelete.length} items.'),
          ),
        );
      }
    }
  }

  Future<bool> _confirmDelete(int count) async {
    final settings = ref.read(settingsNotifierProvider);
    final isTrash = settings.enableTrash;
    final itemText = count == 1 ? '1 item' : '$count items';

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isTrash ? 'Move to Trash?' : 'Delete Permanently?'),
        content: Text(
          isTrash
              ? '$itemText will be moved to trash.'
              : '$itemText will be permanently deleted. This action cannot be undone.',
        ),
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: isTrash
                ? null
                : FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(isTrash ? 'Move to Trash' : 'Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mediaAsync = ref.watch(filteredMediaProvider);
    final settings   = ref.watch(settingsNotifierProvider);
    final isAlbums   = settings.defaultFilter == FilterOption.albums;

    return PopScope(
      canPop: !_selecting || isAlbums,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: _selecting && !isAlbums
              ? Text('${_selected.length} selected')
              : BouncyTap(
                  key: const ValueKey('appbar_badge_easter_egg'),
                  scaleDown: 0.94,
                  onTap: () => _easterEggHandler.handleTap(context, ref),
                  child: const AnimatedFlameTitle(title: 'Phantek'),
                ),
          actions: [
            if (_selecting && !isAlbums) ...[
              IconButton(
                icon: const Icon(Icons.select_all),
                tooltip: 'Select all',
                onPressed: () {
                  final all = mediaAsync.value ?? [];
                  setState(() {
                    _selected.addAll(all.map((e) => e.id));
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete selected',
                onPressed: () =>
                    _deleteSelected(mediaAsync.value ?? []),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              ),
            ] else ...[
              BouncyTap(
                scaleDown: 0.88,
                child: IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: 'Trash',
                  onPressed: () =>
                      Navigator.of(context).openTrash(),
                ),
              ),
              BouncyTap(
                scaleDown: 0.88,
                child: IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                  onPressed: () =>
                      Navigator.of(context).openSettings(),
                ),
              ),
            ],
          ],
        ),
        body: Column(
          children: [
            const FilterSortBar(),
            const Divider(height: 1),
            Expanded(
              child: mediaAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorState(error: e, onRetry: _bootstrap),
                data: (items) {
                  if (items.isEmpty) {
                    return _EmptyState(onRefresh: _bootstrap);
                  }
                  if (isAlbums) {
                    final albums = groupMediaIntoAlbums(items, sort: settings.defaultSort);
                    if (albums.isEmpty) {
                      return _EmptyState(onRefresh: _bootstrap);
                    }
                    return RefreshIndicator(
                      onRefresh: () =>
                          ref.read(mediaListProvider.notifier).refresh(),
                      child: GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: settings.albumGridColumns,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 14,
                          childAspectRatio: 0.74,
                        ),
                        itemCount: albums.length,
                        itemBuilder: (_, i) {
                          final album = albums[i];
                          return AlbumGridItem(
                            key: ValueKey(album.name),
                            album: album,
                            onTap: () =>
                                Navigator.of(context).openAlbum(album.name),
                          );
                        },
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () =>
                        ref.read(mediaListProvider.notifier).refresh(),
                    child: GridView.builder(
                      padding: const EdgeInsets.all(2),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: settings.gridColumns,
                        crossAxisSpacing: 2,
                        mainAxisSpacing: 2,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final item = items[i];
                        return MediaGridItem(
                          key: ValueKey(item.id),
                          item: item,
                          isSelected: _selected.contains(item.id),
                          isSelecting: _selecting,
                          showBadges: settings.showBadges,
                          onTap: () {
                            if (_selecting) {
                              _toggleSelect(item.id);
                              return;
                            }
                            if (item.isVideo) {
                              final videos = items
                                  .where((e) => e.isVideo)
                                  .toList();
                              final idx = videos.indexOf(item);
                              Navigator.of(context).openVideo(
                                videos,
                                idx >= 0 ? idx : 0,
                              );
                            } else {
                              // Pass only photo items for swipe navigation.
                              final photos = items
                                  .where((e) => !e.isVideo)
                                  .toList();
                              final idx = photos.indexOf(item);
                              Navigator.of(context)
                                  .openImage(photos, idx >= 0 ? idx : 0);
                            }
                          },
                          onLongPress: () {
                            if (!_selecting) {
                              _startSelect(item.id);
                            } else {
                              _toggleSelect(item.id);
                            }
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_library_outlined, size: 80,
              color: Colors.white38),
          const SizedBox(height: 16),
          const Text('No media found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          const Text('Grant storage permission or add photos/videos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 60, color: Colors.redAccent),
          const SizedBox(height: 12),
          const Text('Could not load media'),
          const SizedBox(height: 8),
          Text('$error',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
