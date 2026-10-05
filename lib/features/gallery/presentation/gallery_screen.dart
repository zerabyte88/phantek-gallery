import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart' hide FilterOption;
import '../../../core/enums/filter_option.dart';
import '../../../core/models/album.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/settings_model.dart';
import '../../../core/providers/media_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/trash_provider.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/services/share_service.dart';
import '../../../app/router.dart';
import '../../../core/utils/easter_egg_handler.dart';
import '../../../core/widgets/animated_flame_title.dart';
import '../../../core/widgets/bouncy_tap.dart';
import '../../../core/widgets/theme_header_background.dart';
import 'widgets/album_grid_item.dart';
import 'widgets/filter_sort_bar.dart';
import 'widgets/media_grid_item.dart';

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen>
    with WidgetsBindingObserver {
  static const _tabs = [
    FilterOption.all,
    FilterOption.photosOnly,
    FilterOption.videosOnly,
    FilterOption.albums,
  ];

  late final PageController _pageController;
  late int _currentPage;
  final Set<String> _selected = {};
  bool _selecting = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final _easterEggHandler = EasterEggTapHandler();
  StreamSubscription<bool>? _mediaChangeSub;
  DateTime _lastAutoRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final settings = ref.read(settingsNotifierProvider);
    final tabIdx = _tabs.indexOf(settings.defaultFilter);
    _currentPage = tabIdx >= 0 ? tabIdx : 0;
    _pageController = PageController(initialPage: _currentPage);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
    _initMediaChangeObserver();
  }

  void _initMediaChangeObserver() {
    try {
      PhotoManager.startChangeNotify();
      _mediaChangeSub = PhotoManager.notifyStream.listen((_) {
        _triggerAutoRefresh();
      });
    } catch (_) {}
  }

  void _triggerAutoRefresh() {
    final now = DateTime.now();
    if (now.difference(_lastAutoRefresh).inMilliseconds < 1000) return;
    _lastAutoRefresh = now;
    if (mounted) {
      ref.read(mediaListProvider.notifier).refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _triggerAutoRefresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mediaChangeSub?.cancel();
    try {
      PhotoManager.stopChangeNotify();
    } catch (_) {}
    _searchController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    setState(() {
      _isSearching = false;
      _searchController.clear();
      _searchQuery = '';
    });
  }

  List<MediaItem> _filterBySearch(List<MediaItem> items) {
    if (_searchQuery.isEmpty) return items;
    final q = _searchQuery.toLowerCase();
    return items.where((e) {
      return e.name.toLowerCase().contains(q) ||
          e.path.toLowerCase().contains(q) ||
          e.albumName.toLowerCase().contains(q);
    }).toList();
  }

  List<Album> _filterAlbumsBySearch(List<Album> albums) {
    if (_searchQuery.isEmpty) return albums;
    final q = _searchQuery.toLowerCase();
    return albums.where((a) => a.name.toLowerCase().contains(q)).toList();
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

  // ── Navigation & Selection helpers ──────────────────────────────────────

  void _onTabSelected(FilterOption f) {
    final targetIdx = _tabs.indexOf(f);
    if (targetIdx != -1 && targetIdx != _currentPage) {
      setState(() {
        _currentPage = targetIdx;
        if (_selected.isNotEmpty) {
          _selected.clear();
          _selecting = false;
        }
      });
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          targetIdx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _onPageChanged(int index) {
    if (_currentPage != index) {
      setState(() {
        _currentPage = index;
        if (_selected.isNotEmpty) {
          _selected.clear();
          _selecting = false;
        }
      });
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

  Future<void> _deleteSelectedAlbums(
    List<MediaItem> allItems,
    List<Album> allAlbums,
  ) async {
    final settings = ref.read(settingsNotifierProvider);
    final selectedAlbums =
        allAlbums.where((a) => _selected.contains(a.name)).toList();
    if (selectedAlbums.isEmpty) return;

    final toDelete = allItems.where((item) {
      if (_selected.contains(item.albumName)) return true;
      if (_selected.contains('Favorites') &&
          settings.favoriteIds.contains(item.id)) {
        return true;
      }
      return false;
    }).toList();

    final albumCount = selectedAlbums.length;
    final albumText = albumCount == 1 ? '1 album' : '$albumCount albums';
    final mediaText =
        toDelete.length == 1 ? '1 item' : '${toDelete.length} items';

    final isTrash = settings.enableTrash;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isTrash
            ? 'Move $albumText to Trash?'
            : 'Delete $albumText Permanently?'),
        content: Text(
          isTrash
              ? 'All $mediaText inside $albumText will be moved to trash.'
              : 'All $mediaText inside $albumText will be permanently deleted. This action cannot be undone.',
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

    if (confirm != true || !mounted) return;

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
    ref.read(mediaListProvider.notifier).removeItems(toDeleteIds);
    _clearSelection();

    var successCount = 0;
    for (final item in toDelete) {
      try {
        if (settings.enableTrash) {
          await ref.read(trashProvider.notifier).moveToTrash(
                id: item.id,
                path: item.path,
                isVideo: item.isVideo,
              );
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

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mediaAsync = ref.watch(mediaListProvider);
    final settings   = ref.watch(settingsNotifierProvider);
    final isAlbums   = _tabs[_currentPage] == FilterOption.albums;

    return PopScope(
      canPop: !_selecting && !_isSearching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_isSearching) {
            _clearSearch();
          } else if (_selecting) {
            _clearSelection();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: const ThemeHeaderBackground(),
          leading: _isSearching
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Close search',
                  onPressed: _clearSearch,
                )
              : null,
          centerTitle: !_isSearching,
          title: _isSearching
              ? Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Search media or albums...',
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 8),
                            border: InputBorder.none,
                            hintStyle: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 14,
                            ),
                          ),
                          onChanged: (q) =>
                              setState(() => _searchQuery = q.trim()),
                        ),
                      ),
                    ],
                  ),
                )
              : (_selecting
                  ? Text('${_selected.length} selected')
                  : BouncyTap(
                      key: const ValueKey('appbar_badge_easter_egg'),
                      scaleDown: 0.94,
                      onTap: () => _easterEggHandler.handleTap(context, ref),
                      child: const AnimatedFlameTitle(title: 'Phantek'),
                    )),
          actions: [
            if (_isSearching) ...[
              if (_searchController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
            ] else if (_selecting && isAlbums) ...[
              IconButton(
                icon: const Icon(Icons.select_all),
                tooltip: 'Select all',
                onPressed: () {
                  final allAlbums = _filterAlbumsBySearch(
                    groupMediaIntoAlbums(
                      mediaAsync.value ?? [],
                      sort: settings.defaultSort,
                      favoriteIds: settings.favoriteIds,
                    ),
                  );
                  setState(() {
                    if (_selected.length == allAlbums.length) {
                      _selected.clear();
                    } else {
                      _selected.addAll(allAlbums.map((a) => a.name));
                    }
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete selected albums',
                onPressed: () {
                  final allAlbums = _filterAlbumsBySearch(
                    groupMediaIntoAlbums(
                      mediaAsync.value ?? [],
                      sort: settings.defaultSort,
                      favoriteIds: settings.favoriteIds,
                    ),
                  );
                  _deleteSelectedAlbums(mediaAsync.value ?? [], allAlbums);
                },
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              ),
            ] else if (_selecting && !isAlbums) ...[
              IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Share selected',
                onPressed: () {
                  final all = mediaAsync.value ?? [];
                  final paths = all
                      .where((e) => _selected.contains(e.id))
                      .map((e) => e.path)
                      .toList();
                  if (paths.isNotEmpty) {
                    ShareService.shareFiles(paths);
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.select_all),
                tooltip: 'Select all',
                onPressed: () {
                  final all = applyFiltersAndSort(
                    mediaAsync.value ?? [],
                    sort: settings.defaultSort,
                    filter: _tabs[_currentPage],
                  );
                  setState(() {
                    if (_selected.length == all.length) {
                      _selected.clear();
                    } else {
                      _selected.addAll(all.map((e) => e.id));
                    }
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
                  icon: const Icon(Icons.search),
                  tooltip: 'Search',
                  onPressed: () {
                    setState(() {
                      _isSearching = true;
                    });
                  },
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More options',
                color: const Color(0xFF222222),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                offset: const Offset(0, 48),
                onSelected: (value) {
                  if (value == 'select') {
                    setState(() {
                      _selecting = true;
                    });
                  } else if (value == 'trash') {
                    Navigator.of(context).openTrash();
                  } else if (value == 'settings') {
                    Navigator.of(context).openSettings();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'select',
                    child: Row(
                      children: [
                        Icon(Icons.checklist_rounded,
                            size: 20, color: Colors.white),
                        SizedBox(width: 12),
                        Text('Select',
                            style:
                                TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'trash',
                    child: Row(
                      children: [
                        Icon(Icons.delete_sweep_outlined,
                            size: 20, color: Colors.white),
                        SizedBox(width: 12),
                        Text('Trash bin',
                            style:
                                TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'settings',
                    child: Row(
                      children: [
                        Icon(Icons.settings_outlined,
                            size: 20, color: Colors.white),
                        SizedBox(width: 12),
                        Text('Settings',
                            style:
                                TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                ],
                icon: const Icon(Icons.more_vert),
              ),
            ],
          ],
        ),
        body: Column(
          children: [
            FilterSortBar(
              currentFilter: _tabs[_currentPage],
              onFilterChanged: _onTabSelected,
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  final allItems = mediaAsync.valueOrNull;
                  if (allItems == null) {
                    if (mediaAsync.isLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (mediaAsync.hasError) {
                      return _ErrorState(
                        error: mediaAsync.error!,
                        onRetry: _bootstrap,
                      );
                    }
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (allItems.isEmpty) {
                    return _EmptyState(onRefresh: _bootstrap);
                  }

                  return PageView(
                    controller: _pageController,
                    physics: _selecting
                        ? const NeverScrollableScrollPhysics()
                        : const PageScrollPhysics(),
                    onPageChanged: _onPageChanged,
                    children: [
                      _KeepAlivePage(
                        child: _buildMediaGrid(
                          items: _filterBySearch(
                            applyFiltersAndSort(
                              allItems,
                              sort: settings.defaultSort,
                              filter: FilterOption.all,
                            ),
                          ),
                          tab: FilterOption.all,
                          settings: settings,
                          storageKey: 'gallery_tab_all',
                        ),
                      ),
                      _KeepAlivePage(
                        child: _buildMediaGrid(
                          items: _filterBySearch(
                            applyFiltersAndSort(
                              allItems,
                              sort: settings.defaultSort,
                              filter: FilterOption.photosOnly,
                            ),
                          ),
                          tab: FilterOption.photosOnly,
                          settings: settings,
                          storageKey: 'gallery_tab_photos',
                        ),
                      ),
                      _KeepAlivePage(
                        child: _buildMediaGrid(
                          items: _filterBySearch(
                            applyFiltersAndSort(
                              allItems,
                              sort: settings.defaultSort,
                              filter: FilterOption.videosOnly,
                            ),
                          ),
                          tab: FilterOption.videosOnly,
                          settings: settings,
                          storageKey: 'gallery_tab_videos',
                        ),
                      ),
                      _KeepAlivePage(
                        child: _buildAlbumsGrid(
                          albums: _filterAlbumsBySearch(
                            groupMediaIntoAlbums(
                              allItems,
                              sort: settings.defaultSort,
                              favoriteIds: settings.favoriteIds,
                            ),
                          ),
                          settings: settings,
                          storageKey: 'gallery_tab_albums',
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaGrid({
    required List<MediaItem> items,
    required FilterOption tab,
    required SettingsModel settings,
    required String storageKey,
  }) {
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => ref.read(mediaListProvider.notifier).refresh(),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _searchQuery.isNotEmpty
                          ? Icons.search_off_outlined
                          : (tab == FilterOption.videosOnly
                              ? Icons.videocam_outlined
                              : Icons.photo_library_outlined),
                      size: 64,
                      color: Colors.white24,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _searchQuery.isNotEmpty
                          ? 'No media matching "$_searchQuery"'
                          : (tab == FilterOption.videosOnly
                              ? 'No videos found'
                              : 'No photos found'),
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return _PinchZoomGridListener(
      child: RefreshIndicator(
        onRefresh: () =>
            ref.read(mediaListProvider.notifier).refresh(),
        child: GridView.builder(
          key: PageStorageKey(storageKey),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: settings.gridColumns,
            crossAxisSpacing: 3,
            mainAxisSpacing: 3,
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
      ),
    );
  }

  Widget _buildAlbumsGrid({
    required List<Album> albums,
    required SettingsModel settings,
    required String storageKey,
  }) {
    if (albums.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => ref.read(mediaListProvider.notifier).refresh(),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _searchQuery.isNotEmpty
                          ? Icons.search_off_outlined
                          : Icons.folder_open_outlined,
                      size: 64,
                      color: Colors.white24,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _searchQuery.isNotEmpty
                          ? 'No albums matching "$_searchQuery"'
                          : 'No albums found',
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(mediaListProvider.notifier).refresh(),
      child: GridView.builder(
        key: PageStorageKey(storageKey),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: settings.albumGridColumns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
          childAspectRatio: 0.74,
        ),
        itemCount: albums.length,
        itemBuilder: (_, i) {
          final album = albums[i];
          return AlbumGridItem(
            key: ValueKey(album.name),
            album: album,
            isSelected: _selected.contains(album.name),
            isSelecting: _selecting,
            onTap: () {
              if (_selecting) {
                _toggleSelect(album.name);
                return;
              }
              Navigator.of(context).openAlbum(album.name);
            },
            onLongPress: () {
              if (!_selecting) {
                _startSelect(album.name);
              } else {
                _toggleSelect(album.name);
              }
            },
          );
        },
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

/// Keeps PageView children alive in memory for instant, zero-rebuild swiping.
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});
  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Detects 2-finger pinch gestures to dynamically change grid columns (2 to 5)
/// without blocking single-finger vertical scroll or horizontal page swipe.
class _PinchZoomGridListener extends ConsumerStatefulWidget {
  const _PinchZoomGridListener({required this.child});
  final Widget child;

  @override
  ConsumerState<_PinchZoomGridListener> createState() =>
      _PinchZoomGridListenerState();
}

class _PinchZoomGridListenerState
    extends ConsumerState<_PinchZoomGridListener> {
  final Map<int, Offset> _pointers = {};
  double? _baseDistance;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) {
        _pointers[e.pointer] = e.position;
        if (_pointers.length == 2) {
          final pts = _pointers.values.toList();
          _baseDistance = (pts[0] - pts[1]).distance;
        }
      },
      onPointerMove: (e) {
        _pointers[e.pointer] = e.position;
        if (_pointers.length == 2 &&
            _baseDistance != null &&
            _baseDistance! > 20) {
          final pts = _pointers.values.toList();
          final currentDist = (pts[0] - pts[1]).distance;
          final ratio = currentDist / _baseDistance!;
          final cols = ref.read(settingsNotifierProvider).gridColumns;
          if (ratio > 1.35 && cols > 2) {
            HapticFeedback.selectionClick();
            ref
                .read(settingsNotifierProvider.notifier)
                .update((s) => s.copyWith(gridColumns: cols - 1));
            _baseDistance = currentDist;
          } else if (ratio < 0.72 && cols < 5) {
            HapticFeedback.selectionClick();
            ref
                .read(settingsNotifierProvider.notifier)
                .update((s) => s.copyWith(gridColumns: cols + 1));
            _baseDistance = currentDist;
          }
        }
      },
      onPointerUp: (e) {
        _pointers.remove(e.pointer);
        if (_pointers.length < 2) _baseDistance = null;
      },
      onPointerCancel: (e) {
        _pointers.remove(e.pointer);
        if (_pointers.length < 2) _baseDistance = null;
      },
      child: widget.child,
    );
  }
}

