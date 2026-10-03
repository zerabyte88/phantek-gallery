import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart' hide FilterOption;
import '../../../app/router.dart';
import '../../../core/enums/filter_option.dart';
import '../../../core/enums/sort_option.dart';
import '../../../core/models/media_item.dart';
import '../../../core/providers/media_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/trash_provider.dart';
import '../../../core/services/permission_service.dart';
import 'widgets/filter_sort_bar.dart';
import 'widgets/media_grid_item.dart';

/// Screen displaying photos and videos belonging to a specific album.
class AlbumDetailScreen extends ConsumerStatefulWidget {
  const AlbumDetailScreen({
    super.key,
    required this.albumName,
  });

  final String albumName;

  @override
  ConsumerState<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends ConsumerState<AlbumDetailScreen> {
  final Set<String> _selected = {};
  bool _selecting = false;
  FilterOption _filter = FilterOption.all;
  SortOption? _sort;

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
    // 1. Instantly remove from state so the album detail updates immediately
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

  @override
  Widget build(BuildContext context) {
    final mediaAsync = ref.watch(mediaListProvider);
    final settings = ref.watch(settingsNotifierProvider);

    final allItems = mediaAsync.value ?? [];
    final albumItems =
        allItems.where((e) => e.albumName == widget.albumName).toList();

    // 1. Filter by All / Photos / Videos
    final filteredItems = switch (_filter) {
      FilterOption.photosOnly => albumItems.where((e) => !e.isVideo).toList(),
      FilterOption.videosOnly => albumItems.where((e) => e.isVideo).toList(),
      _ => albumItems,
    };

    // 2. Sort by selected sort or settings.defaultSort
    final activeSort = _sort ?? settings.defaultSort;
    final sortedItems = switch (activeSort) {
      SortOption.newest => [...filteredItems]..sort((a, b) => b.date.compareTo(a.date)),
      SortOption.oldest => [...filteredItems]..sort((a, b) => a.date.compareTo(b.date)),
      SortOption.nameAZ => [...filteredItems]
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      SortOption.nameZA => [...filteredItems]
          ..sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase())),
    };

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: _selecting
              ? Text('${_selected.length} selected')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.albumName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${sortedItems.length} items',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
          actions: [
            if (_selecting) ...[
              IconButton(
                icon: const Icon(Icons.select_all),
                tooltip: 'Select all',
                onPressed: () {
                  setState(() {
                    _selected.addAll(sortedItems.map((e) => e.id));
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete selected',
                onPressed: () => _deleteSelected(sortedItems),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              ),
            ],
          ],
        ),
        body: Column(
          children: [
            FilterSortBar(
              isAlbumDetail: true,
              currentFilter: _filter,
              onFilterChanged: (f) => setState(() => _filter = f),
              currentSort: activeSort,
              onSortChanged: (s) => setState(() => _sort = s),
            ),
            const Divider(height: 1),
            Expanded(
              child: albumItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.photo_library_outlined,
                              size: 64, color: Colors.white38),
                          const SizedBox(height: 12),
                          Text(
                            'No media in ${widget.albumName}',
                            style: const TextStyle(
                                fontSize: 16, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : sortedItems.isEmpty
                      ? Center(
                          child: Text(
                            'No ${_filter.label.toLowerCase()} in this album',
                            style: const TextStyle(
                                fontSize: 14, color: Colors.grey),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(2),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: settings.gridColumns,
                            crossAxisSpacing: 2,
                            mainAxisSpacing: 2,
                          ),
                          itemCount: sortedItems.length,
                          itemBuilder: (_, i) {
                            final item = sortedItems[i];
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
                                  final videos = sortedItems
                                      .where((e) => e.isVideo)
                                      .toList();
                                  final idx = videos.indexOf(item);
                                  Navigator.of(context).openVideo(
                                    videos,
                                    idx >= 0 ? idx : 0,
                                  );
                                } else {
                                  final photos = sortedItems
                                      .where((e) => !e.isVideo)
                                      .toList();
                                  final idx = photos.indexOf(item);
                                  Navigator.of(context).openImage(
                                    photos,
                                    idx >= 0 ? idx : 0,
                                  );
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
            ),
          ],
        ),
      ),
    );
  }
}
