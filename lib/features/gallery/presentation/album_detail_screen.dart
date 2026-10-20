import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart' hide FilterOption;
import '../../../app/router.dart';
import '../../../core/enums/filter_option.dart';
import '../../../core/enums/sort_option.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/settings_model.dart';
import '../../../core/providers/media_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/trash_provider.dart';
import '../../../core/providers/vault_provider.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/utils/media_utils.dart';
import '../../../core/widgets/bouncy_tap.dart';
import 'widgets/filter_sort_bar.dart';
import 'widgets/media_grid_item.dart';
import 'widgets/delete_confirmation_sheet.dart';
import '../../../core/widgets/feedback_pill.dart';

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
  late final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveMedia(
    String mediaId,
    List<MediaItem> sortedItems,
    SettingsModel settings,
  ) {
    if (!mounted || !_scrollController.hasClients) return;
    final index = sortedItems.indexWhere((e) => e.id == mediaId);
    if (index < 0) return;

    final targetOffset = MediaUtils.calculateGridScrollOffset(
      index: index,
      crossAxisCount: settings.gridColumns,
      screenWidth: MediaQuery.sizeOf(context).width,
      viewportHeight: _scrollController.position.viewportDimension,
      currentScrollOffset: _scrollController.offset,
      maxScrollExtent: _scrollController.position.maxScrollExtent,
      paddingHorizontal: 4.0,
      paddingTop: 2.0,
      spacing: 2.0,
    );

    if ((targetOffset - _scrollController.offset).abs() > 1.0) {
      _scrollController.jumpTo(targetOffset);
    }
  }

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
    final toDelete = allItems.where((e) => _selected.contains(e.id)).toList();

    final confirm = await _confirmDelete(toDelete.length);
    if (!confirm || !mounted) return;

    final hasPerm = await PermissionService.instance.ensureManageStorage();
    if (!hasPerm) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr.manageFilesPermissionRequired),
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
        showFeedbackPill(
          context,
          message: 'Processed $successCount of ${toDelete.length} items.',
          icon: Icons.info_outline_rounded,
        );
      } else {
        showFeedbackPill(
          context,
          message: settings.enableTrash
              ? context.tr.moveToTrash
              : context.tr.delete,
          icon: settings.enableTrash
              ? Icons.delete_outline_rounded
              : Icons.delete_forever_rounded,
        );
      }
    }
  }

  Future<void> _moveToVaultSelected(List<MediaItem> allItems) async {
    final toVault = allItems.where((e) => _selected.contains(e.id)).toList();
    if (toVault.isEmpty) return;

    final hasPerm = await PermissionService.instance.ensureManageStorage();
    if (!hasPerm) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Manage All Files permission is required to move items to vault.'),
          ),
        );
      }
      return;
    }

    final toVaultIds = toVault.map((e) => e.id).toSet();
    ref.read(mediaListProvider.notifier).removeItems(toVaultIds);
    final count = toVault.length;
    _clearSelection();

    try {
      await ref.read(vaultProvider.notifier).moveToVaultBatch(toVault);
      if (mounted) {
        showFeedbackPill(
          context,
          message: context.tr.itemRestored(context.tr.itemsCount(count)),
          icon: Icons.lock_outline_rounded,
        );
      }
    } catch (e) {
      debugPrint('Vault move error: $e');
    }
  }

  Future<bool> _confirmDelete(int count) async {
    final settings = ref.read(settingsNotifierProvider);
    final isTrash = settings.enableTrash;
    final itemText = context.tr.itemsCount(count);
    final title = isTrash
        ? context.tr.moveToTrashTitle
        : context.tr.deletePermanentlyTitle;
    final contentText = isTrash
        ? context.tr.moveToTrashConfirm(itemText)
        : context.tr.deletePermanentlyConfirm(itemText);

    return showDeleteConfirmationSheet(
      context,
      title: title,
      contentText: contentText,
      isTrash: isTrash,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaAsync = ref.watch(mediaListProvider);
    final settings = ref.watch(settingsNotifierProvider);

    final allItems = mediaAsync.value ?? [];
    final albumItems = widget.albumName == 'Favorites'
        ? allItems.where((e) => settings.favoriteIds.contains(e.id)).toList()
        : allItems.where((e) => e.albumName == widget.albumName).toList();

    // 1. Filter by All / Photos / Videos
    final filteredItems = switch (_filter) {
      FilterOption.photosOnly => albumItems.where((e) => !e.isVideo).toList(),
      FilterOption.videosOnly => albumItems.where((e) => e.isVideo).toList(),
      _ => albumItems,
    };

    // 2. Sort by selected sort or settings.defaultSort
    final activeSort = _sort ?? settings.defaultSort;
    final sortedItems = switch (activeSort) {
      SortOption.newest => [...filteredItems]
        ..sort((a, b) => b.timeAdded.compareTo(a.timeAdded)),
      SortOption.oldest => [...filteredItems]
        ..sort((a, b) => a.timeAdded.compareTo(b.timeAdded)),
      SortOption.shootingTimeDesc => [...filteredItems]
        ..sort((a, b) => b.date.compareTo(a.date)),
      SortOption.shootingTimeAsc => [...filteredItems]
        ..sort((a, b) => a.date.compareTo(b.date)),
      SortOption.nameAZ => [...filteredItems]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      SortOption.nameZA => [...filteredItems]
        ..sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase())),
      SortOption.sizeDesc => [...filteredItems]
        ..sort((a, b) => b.size.compareTo(a.size)),
      SortOption.sizeAsc => [...filteredItems]
        ..sort((a, b) => a.size.compareTo(b.size)),
    };

    ref.listen<String?>(activeViewerMediaIdProvider, (_, nextId) {
      if (nextId != null) {
        _scrollToActiveMedia(nextId, sortedItems, settings);
      }
    });

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
              ? Text('${_selected.length} ${context.tr.selected}')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.albumName == 'Favorites'
                          ? context.tr.favorites
                          : widget.albumName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      context.tr.itemsCount(sortedItems.length),
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
              BouncyTap(
                scaleDown: 0.88,
                child: IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: context.tr.selectAll,
                  onPressed: () {
                    setState(() {
                      _selected.addAll(sortedItems.map((e) => e.id));
                    });
                  },
                ),
              ),
              if (settings.lockedVaultEnabled)
                BouncyTap(
                  scaleDown: 0.88,
                  child: IconButton(
                    icon: const Icon(Icons.lock_outline_rounded),
                    tooltip: context.tr.moveToVault,
                    onPressed: () => _moveToVaultSelected(sortedItems),
                  ),
                ),
              BouncyTap(
                scaleDown: 0.88,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: context.tr.deleteSelected,
                  onPressed: () => _deleteSelected(sortedItems),
                ),
              ),
              BouncyTap(
                scaleDown: 0.88,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _clearSelection,
                ),
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
                          controller: _scrollController,
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
                                Navigator.of(context).openVideo(sortedItems, i);
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
