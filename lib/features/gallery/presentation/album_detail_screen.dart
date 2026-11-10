import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart' hide FilterOption;
import '../../../app/router.dart';
import '../../../core/enums/filter_option.dart';
import '../../../core/enums/sort_option.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/utils/natural_sort.dart';
import '../../../core/models/album.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/settings_model.dart';
import '../../../core/providers/media_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/trash_provider.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/utils/media_utils.dart';
import '../../../core/widgets/bouncy_tap.dart';
import 'widgets/album_grid_item.dart';
import 'widgets/filter_sort_bar.dart';
import 'widgets/media_grid_item.dart';
import 'widgets/delete_confirmation_sheet.dart';
import '../../../core/widgets/feedback_pill.dart';
import '../../../core/services/psd_service.dart';
import '../../../core/widgets/theme_header_background.dart';

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
  bool _flattenSubfolders = true;
  String? _selectedSubfolder;
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
              ? (successCount == 1
                  ? context.tr.itemMovedToTrash(toDelete.first.name)
                  : context.tr.itemsMovedToTrashCount(successCount))
              : (successCount == 1
                  ? context.tr.itemDeleted(toDelete.first.name)
                  : context.tr.itemsDeletedCount(successCount)),
          icon: settings.enableTrash
              ? Icons.delete_outline_rounded
              : Icons.delete_forever_rounded,
        );
      }
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

    var allItems = mediaAsync.value ?? [];
    if (!settings.showHiddenFiles) {
      allItems = allItems.where((e) {
        final segments = e.path.split(RegExp(r'[/\\]'));
        return !segments
            .any((s) => s.isNotEmpty && s.startsWith('.') && s != '.');
      }).toList();
    }
    if (settings.filterSmallImages) {
      allItems =
          allItems.where((e) => e.isVideo || e.size >= 50 * 1024).toList();
    }
    final albumItems = widget.albumName == 'Favorites'
        ? allItems.where((e) => settings.favoriteIds.contains(e.id)).toList()
        : allItems
            .where((e) =>
                e.albumName == widget.albumName ||
                e.immediateFolderName == widget.albumName)
            .toList();

    final Map<String, List<MediaItem>> subfolderItemsMap = {};
    for (final item in albumItems) {
      if (item.immediateFolderName.isNotEmpty &&
          item.immediateFolderName != widget.albumName) {
        subfolderItemsMap
            .putIfAbsent(item.immediateFolderName, () => [])
            .add(item);
      }
    }
    for (final list in subfolderItemsMap.values) {
      list.sort((a, b) => naturalCompare(a.name, b.name));
    }
    final subfolderNames = subfolderItemsMap.keys.toList()
      ..sort(naturalCompare);
    final hasSubfolders = subfolderNames.length > 1;

    final scopedItems = (_selectedSubfolder != null)
        ? albumItems
            .where((e) => e.immediateFolderName == _selectedSubfolder)
            .toList()
        : albumItems;

    // 1. Filter by All / Photos / Videos
    final filteredItems = switch (_filter) {
      FilterOption.photosOnly => scopedItems.where((e) => !e.isVideo).toList(),
      FilterOption.videosOnly => scopedItems.where((e) => e.isVideo).toList(),
      _ => scopedItems,
    };

    int compareMangaCanonical(MediaItem a, MediaItem b) {
      if (hasSubfolders && _selectedSubfolder == null) {
        final folderCmp =
            naturalCompare(a.immediateFolderName, b.immediateFolderName);
        if (folderCmp != 0) return folderCmp;
      }
      return naturalCompare(a.name, b.name);
    }

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
      SortOption.nameAZ => [...filteredItems]..sort(compareMangaCanonical),
      SortOption.nameZA => [...filteredItems]
        ..sort((a, b) => compareMangaCanonical(b, a)),
      SortOption.sizeDesc => [...filteredItems]
        ..sort((a, b) => b.size.compareTo(a.size)),
      SortOption.sizeAsc => [...filteredItems]
        ..sort((a, b) => a.size.compareTo(b.size)),
      SortOption.albumAZ => [...filteredItems]..sort(compareMangaCanonical),
      SortOption.albumZA => [...filteredItems]
        ..sort((a, b) => compareMangaCanonical(b, a)),
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
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: const RepaintBoundary(
            child: ThemeHeaderBackground(),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_selectedSubfolder != null && !_flattenSubfolders) {
                setState(() => _selectedSubfolder = null);
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          title: _selecting
              ? Text('${_selected.length} ${context.tr.selected}')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.albumName == 'Favorites'
                          ? context.tr.favorites
                          : (_selectedSubfolder != null && !_flattenSubfolders
                              ? '${widget.albumName} / $_selectedSubfolder'
                              : widget.albumName),
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
            if (!_selecting && hasSubfolders)
              BouncyTap(
                scaleDown: 0.88,
                child: IconButton(
                  icon: Icon(
                    _flattenSubfolders
                        ? Icons.folder_copy_outlined
                        : Icons.grid_view_rounded,
                  ),
                  tooltip: _flattenSubfolders
                      ? context.tr.showSubfolders
                      : context.tr.flattenSubfolders,
                  onPressed: () {
                    setState(() {
                      _flattenSubfolders = !_flattenSubfolders;
                      _selectedSubfolder = null;
                    });
                  },
                ),
              ),
            if (!_selecting)
              PopupMenuButton<String>(
                splashRadius: 20,
                tooltip: context.tr.moreOptions,
                color: const Color(0xFF222222),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                constraints: const BoxConstraints(minWidth: 130, maxWidth: 195),
                offset: const Offset(0, 48),
                onSelected: (value) {
                  if (value == 'manga') {
                    final mangaItems = filteredItems
                        .where((e) => !e.isVideo && !PsdService.isPsd(e.path))
                        .toList()
                      ..sort(compareMangaCanonical);
                    if (mangaItems.isNotEmpty) {
                      Navigator.of(context).openImage(
                        mangaItems,
                        0,
                        initialMangaMode: true,
                      );
                    } else {
                      showFeedbackPill(
                        context,
                        message: context.tr.noPhotosFound,
                        icon: Icons.auto_stories_rounded,
                      );
                    }
                  } else if (value == 'slideshow') {
                    if (sortedItems.isNotEmpty) {
                      final hasVideos = sortedItems.any((e) => e.isVideo);
                      if (hasVideos) {
                        Navigator.of(context).openVideo(
                          sortedItems,
                          0,
                          startSlideshow: true,
                        );
                      } else {
                        Navigator.of(context).openImage(
                          sortedItems,
                          0,
                          startSlideshow: true,
                        );
                      }
                    }
                  } else if (value == 'select') {
                    setState(() {
                      _selecting = true;
                    });
                  }
                },
                itemBuilder: (context) => [
                  if (sortedItems.isNotEmpty) ...[
                    PopupMenuItem(
                      value: 'manga',
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          const Icon(Icons.auto_stories_rounded,
                              size: 18, color: Colors.white),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              context.tr.readAsManga,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'slideshow',
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          const Icon(Icons.slideshow_rounded,
                              size: 18, color: Colors.white),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              context.tr.slideshow,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  PopupMenuItem(
                    value: 'select',
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.checklist_rounded,
                            size: 18, color: Colors.white),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            context.tr.select,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                icon: const Icon(Icons.more_vert),
              ),
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
            if (hasSubfolders && _flattenSubfolders) ...[
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        selected: _selectedSubfolder == null,
                        label: Text(
                            '${context.tr.allChapters} (${albumItems.length})'),
                        onSelected: (_) {
                          setState(() => _selectedSubfolder = null);
                        },
                      ),
                    ),
                    for (final sub in subfolderNames)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          selected: _selectedSubfolder == sub,
                          label: Text(
                              '$sub (${subfolderItemsMap[sub]?.length ?? 0})'),
                          onSelected: (selected) {
                            setState(() {
                              _selectedSubfolder = selected ? sub : null;
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (hasSubfolders &&
                !_flattenSubfolders &&
                _selectedSubfolder != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.4),
                child: Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setState(() => _selectedSubfolder = null),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.arrow_back, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              context.tr.chapters,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('•', style: TextStyle(color: Colors.grey)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedSubfolder!,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      context.tr.itemsCount(sortedItems.length),
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
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
                  : (hasSubfolders &&
                          !_flattenSubfolders &&
                          _selectedSubfolder == null)
                      ? GridView.builder(
                          cacheExtent: 800.0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: settings.albumGridColumns,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.74,
                          ),
                          itemCount: subfolderNames.length,
                          itemBuilder: (_, i) {
                            final sub = subfolderNames[i];
                            final subItems = subfolderItemsMap[sub] ?? const [];
                            final cover =
                                subItems.isNotEmpty ? subItems.first : null;
                            if (cover == null) return const SizedBox.shrink();
                            final subAlbum = Album(
                              name: sub,
                              items: subItems,
                              coverItem: cover,
                            );
                            return AlbumGridItem(
                              key: ValueKey(sub),
                              album: subAlbum,
                              onTap: () {
                                setState(() => _selectedSubfolder = sub);
                              },
                            );
                          },
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
                              cacheExtent: 800.0,
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
                                    if (sortedItems.every((e) => !e.isVideo)) {
                                      Navigator.of(context)
                                          .openImage(sortedItems, i);
                                    } else {
                                      Navigator.of(context)
                                          .openVideo(sortedItems, i);
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
