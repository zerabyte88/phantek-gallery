import 'dart:io';
import 'package:flutter/material.dart';
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
  final _easterEggHandler = EasterEggTapHandler();

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsNotifierProvider);
    final tabIdx = _tabs.indexOf(settings.defaultFilter);
    _currentPage = tabIdx >= 0 ? tabIdx : 0;
    _pageController = PageController(initialPage: _currentPage);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
      ref
          .read(settingsNotifierProvider.notifier)
          .update((s) => s.copyWith(defaultFilter: f));
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
      final f = _tabs[index];
      ref
          .read(settingsNotifierProvider.notifier)
          .update((s) => s.copyWith(defaultFilter: f));
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

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mediaAsync = ref.watch(mediaListProvider);
    final settings   = ref.watch(settingsNotifierProvider);
    final isAlbums   = _tabs[_currentPage] == FilterOption.albums;

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
            FilterSortBar(
              currentFilter: _tabs[_currentPage],
              onFilterChanged: _onTabSelected,
            ),
            const Divider(height: 1),
            Expanded(
              child: mediaAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorState(error: e, onRetry: _bootstrap),
                data: (allItems) {
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
                          items: applyFiltersAndSort(
                            allItems,
                            sort: settings.defaultSort,
                            filter: FilterOption.all,
                          ),
                          tab: FilterOption.all,
                          settings: settings,
                          storageKey: 'gallery_tab_all',
                        ),
                      ),
                      _KeepAlivePage(
                        child: _buildMediaGrid(
                          items: applyFiltersAndSort(
                            allItems,
                            sort: settings.defaultSort,
                            filter: FilterOption.photosOnly,
                          ),
                          tab: FilterOption.photosOnly,
                          settings: settings,
                          storageKey: 'gallery_tab_photos',
                        ),
                      ),
                      _KeepAlivePage(
                        child: _buildMediaGrid(
                          items: applyFiltersAndSort(
                            allItems,
                            sort: settings.defaultSort,
                            filter: FilterOption.videosOnly,
                          ),
                          tab: FilterOption.videosOnly,
                          settings: settings,
                          storageKey: 'gallery_tab_videos',
                        ),
                      ),
                      _KeepAlivePage(
                        child: _buildAlbumsGrid(
                          albums: groupMediaIntoAlbums(
                            allItems,
                            sort: settings.defaultSort,
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
                      tab == FilterOption.videosOnly
                          ? Icons.videocam_outlined
                          : Icons.photo_library_outlined,
                      size: 64,
                      color: Colors.white24,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tab == FilterOption.videosOnly
                          ? 'No videos found'
                          : 'No photos found',
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
        padding: const EdgeInsets.all(2),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
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
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open_outlined,
                        size: 64, color: Colors.white24),
                    SizedBox(height: 12),
                    Text('No albums found',
                        style: TextStyle(fontSize: 16, color: Colors.grey)),
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
