import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart' hide FilterOption;
import '../../../core/enums/filter_option.dart';
import '../../../core/enums/sort_option.dart';
import '../../../core/enums/startup_screen.dart';
import '../../../core/enums/thumbnail_crop_style.dart';
import '../../../core/enums/timeline_grouping.dart';
import '../../../core/models/album.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/settings_model.dart';
import '../../../core/providers/media_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/trash_provider.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/services/share_service.dart';
import '../../../app/router.dart';
import '../../../core/utils/media_utils.dart';
import '../../../core/widgets/animated_flame_title.dart';
import '../../../core/widgets/bouncy_tap.dart';
import '../../../core/widgets/styled_popup_menu.dart';
import '../../../core/widgets/theme_header_background.dart';
import 'widgets/album_grid_item.dart';
import 'widgets/fast_scroll_handle.dart';
import 'widgets/filter_sort_bar.dart';
import 'widgets/media_grid_item.dart';
import 'widgets/delete_confirmation_sheet.dart';
import 'widgets/manga_folder_picker_sheet.dart';
import '../../../core/widgets/feedback_pill.dart';

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _tabs = [
    FilterOption.all,
    FilterOption.photosOnly,
    FilterOption.videosOnly,
    FilterOption.albums,
  ];

  late final PageController _pageController;
  late final AnimationController _searchAnimController;
  final FocusNode _searchFocusNode = FocusNode();
  late int _currentPage;
  bool _isTabTapTransition = false;
  int? _pendingTapTargetPage;
  Timer? _tabTapTimer;
  final Set<String> _selected = {};
  bool _selecting = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  StreamSubscription<bool>? _mediaChangeSub;
  DateTime _lastAutoRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  final Map<FilterOption, ScrollController> _scrollControllers = {
    FilterOption.all: ScrollController(),
    FilterOption.photosOnly: ScrollController(),
    FilterOption.videosOnly: ScrollController(),
    FilterOption.albums: ScrollController(),
  };

  // Memoized tab items for smooth tab transitions.
  List<MediaItem>? _cachedAllItemsRef;
  SortOption? _cachedSort;
  String? _cachedSearchQuery;
  List<String>? _cachedFavoriteIds;
  bool? _cachedFilterSmall;
  bool? _cachedShowHidden;

  List<MediaItem> _memoizedAll = const [];
  List<MediaItem> _memoizedPhotos = const [];
  List<MediaItem> _memoizedVideos = const [];
  List<Album> _memoizedAlbums = const [];

  Map<String, int> _memoizedAllIndex = const {};
  Map<String, int> _memoizedPhotosIndex = const {};
  Map<String, int> _memoizedVideosIndex = const {};

  final Map<FilterOption, List<MediaItem>> _cachedGroupItems = {};
  final Map<FilterOption, TimelineGrouping> _cachedGroupTimelineGrouping = {};
  final Map<FilterOption, int> _cachedGroupDay = {};
  final Map<FilterOption, Map<String, List<int>>> _cachedGroupResult = {};
  final Map<FilterOption, Map<String, Map<String, int>>> _cachedGroupIndexMaps =
      {};

  static Map<String, int> _buildIndexMap(List<MediaItem> items) {
    final map = <String, int>{};
    for (var i = 0; i < items.length; i++) {
      map[items[i].id] = i;
    }
    return map;
  }

  void _updateMemoizedTabs(List<MediaItem> allItems, SettingsModel settings) {
    if (identical(_cachedAllItemsRef, allItems) &&
        _cachedSort == settings.defaultSort &&
        _cachedSearchQuery == _searchQuery &&
        _cachedFavoriteIds == settings.favoriteIds &&
        _cachedFilterSmall == settings.filterSmallImages &&
        _cachedShowHidden == settings.showHiddenFiles) {
      return;
    }

    _cachedAllItemsRef = allItems;
    _cachedSort = settings.defaultSort;
    _cachedSearchQuery = _searchQuery;
    _cachedFavoriteIds = settings.favoriteIds;
    _cachedFilterSmall = settings.filterSmallImages;
    _cachedShowHidden = settings.showHiddenFiles;

    var filteredItems = allItems;
    if (!settings.showHiddenFiles) {
      filteredItems = filteredItems.where((e) {
        final segments = e.path.split(RegExp(r'[/\\]'));
        return !segments
            .any((s) => s.isNotEmpty && s.startsWith('.') && s != '.');
      }).toList();
    }
    if (settings.filterSmallImages) {
      filteredItems =
          filteredItems.where((e) => e.isVideo || e.size >= 50 * 1024).toList();
    }

    _memoizedAll = _filterBySearch(
      applyFiltersAndSort(
        filteredItems,
        sort: settings.defaultSort,
        filter: FilterOption.all,
      ),
    );
    _memoizedPhotos = _filterBySearch(
      applyFiltersAndSort(
        filteredItems,
        sort: settings.defaultSort,
        filter: FilterOption.photosOnly,
      ),
    );
    _memoizedVideos = _filterBySearch(
      applyFiltersAndSort(
        filteredItems,
        sort: settings.defaultSort,
        filter: FilterOption.videosOnly,
      ),
    );
    _memoizedAllIndex = _buildIndexMap(_memoizedAll);
    _memoizedPhotosIndex = _buildIndexMap(_memoizedPhotos);
    _memoizedVideosIndex = _buildIndexMap(_memoizedVideos);
    _memoizedAlbums = _filterAlbumsBySearch(
      groupMediaIntoAlbums(
        filteredItems,
        sort: settings.defaultSort,
        favoriteIds: settings.favoriteIds,
      ),
    );
  }

  List<MediaItem> get _currentTabItems {
    if (_currentPage >= 0 && _currentPage < _tabs.length) {
      switch (_tabs[_currentPage]) {
        case FilterOption.photosOnly:
          return _memoizedPhotos;
        case FilterOption.videosOnly:
          return _memoizedVideos;
        case FilterOption.all:
        case FilterOption.albums:
          return _memoizedAll;
      }
    }
    return _memoizedAll;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    final settings = ref.read(settingsNotifierProvider);
    final startupFilter = switch (settings.startupScreen) {
      StartupScreen.all => FilterOption.all,
      StartupScreen.photosOnly => FilterOption.photosOnly,
      StartupScreen.videosOnly => FilterOption.videosOnly,
      StartupScreen.albums => FilterOption.albums,
    };
    final tabIdx = _tabs.indexOf(startupFilter);
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
    _tabTapTimer?.cancel();
    _mediaChangeSub?.cancel();
    try {
      PhotoManager.stopChangeNotify();
    } catch (_) {}
    _searchAnimController.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    _pageController.dispose();
    for (final c in _scrollControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _scrollToActiveMedia(String mediaId) {
    if (!mounted) return;
    final currentTab = _tabs[_currentPage];
    final controller = _scrollControllers[currentTab];
    if (controller == null || !controller.hasClients) return;

    final List<MediaItem> currentItems;
    switch (currentTab) {
      case FilterOption.photosOnly:
        currentItems = _memoizedPhotos;
        break;
      case FilterOption.videosOnly:
        currentItems = _memoizedVideos;
        break;
      default:
        currentItems = _memoizedAll;
        break;
    }

    final index = currentItems.indexWhere((e) => e.id == mediaId);
    if (index < 0) return;

    final settings = ref.read(settingsNotifierProvider);
    final targetOffset = MediaUtils.calculateGridScrollOffset(
      index: index,
      crossAxisCount: settings.gridColumns,
      screenWidth: MediaQuery.sizeOf(context).width,
      viewportHeight: controller.position.viewportDimension,
      currentScrollOffset: controller.offset,
      maxScrollExtent: controller.position.maxScrollExtent,
      paddingHorizontal: 6.0,
      paddingTop: 2.0,
      spacing: 3.0,
    );

    if ((targetOffset - controller.offset).abs() > 1.0) {
      controller.jumpTo(targetOffset);
    }
  }

  void _openSearch() {
    setState(() {
      _isSearching = true;
    });
    _searchAnimController.forward().then((_) {
      if (mounted && _isSearching) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _clearSearch() {
    _searchFocusNode.unfocus();
    _searchAnimController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchController.clear();
          _searchQuery = '';
        });
      }
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

  Future<void> _bootstrap() async {
    final granted = await PermissionService.instance.requestMediaPermissions();
    if (!mounted) return;
    if (granted) {
      ref.read(mediaListProvider.notifier).refresh();
    }
  }

  void _onTabSelected(FilterOption f) {
    final targetIdx = _tabs.indexOf(f);
    if (targetIdx != -1 && targetIdx != _currentPage) {
      _tabTapTimer?.cancel();
      setState(() {
        _currentPage = targetIdx;
        _isTabTapTransition = true;
        _pendingTapTargetPage = targetIdx;
        if (_selected.isNotEmpty) {
          _selected.clear();
          _selecting = false;
        }
      });
      _tabTapTimer = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        setState(() {
          _isTabTapTransition = false;
          _pendingTapTargetPage = null;
        });
      });
      if (_pageController.hasClients) {
        _pageController.jumpToPage(targetIdx);
      }
    }
  }

  void _onPageChanged(int index) {
    if (_pendingTapTargetPage != null && index != _pendingTapTargetPage) {
      return;
    }
    if (index == _pendingTapTargetPage) {
      _pendingTapTargetPage = null;
    }
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

  Future<void> _deleteSelected(List<MediaItem> allItems) async {
    final settings = ref.read(settingsNotifierProvider);
    final toDelete = allItems.where((e) => _selected.contains(e.id)).toList();

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
          message:
              settings.enableTrash ? context.tr.moveToTrash : context.tr.delete,
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
    final title = isTrash
        ? 'Move $albumText to Trash?'
        : 'Delete $albumText Permanently?';
    final contentText = isTrash
        ? 'All $mediaText inside $albumText will be moved to trash.'
        : 'All $mediaText inside $albumText will be permanently deleted. This action cannot be undone.';

    final confirm = await showDeleteConfirmationSheet(
      context,
      title: title,
      contentText: contentText,
      isTrash: isTrash,
    );

    if (confirm != true || !mounted) return;

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
        showFeedbackPill(
          context,
          message: 'Processed $successCount of ${toDelete.length} items.',
          icon: Icons.info_outline_rounded,
        );
      } else {
        showFeedbackPill(
          context,
          message: isTrash
              ? (successCount == 1
                  ? context.tr.itemMovedToTrash(toDelete.first.name)
                  : context.tr.itemsMovedToTrashCount(successCount))
              : (successCount == 1
                  ? context.tr.itemDeleted(toDelete.first.name)
                  : context.tr.itemsDeletedCount(successCount)),
          icon: isTrash
              ? Icons.delete_outline_rounded
              : Icons.delete_forever_rounded,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(activeViewerMediaIdProvider, (_, nextId) {
      if (nextId != null) {
        _scrollToActiveMedia(nextId);
      }
    });

    final mediaAsync = ref.watch(mediaListProvider);
    final settings = ref.watch(settingsNotifierProvider);
    final isAlbums = _tabs[_currentPage] == FilterOption.albums;
    if (mediaAsync.hasValue) {
      _updateMemoizedTabs(mediaAsync.value!, settings);
    }

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
          flexibleSpace: Stack(
            fit: StackFit.expand,
            children: [
              const RepaintBoundary(
                child: ThemeHeaderBackground(),
              ),
              AnimatedBuilder(
                animation: _searchAnimController,
                builder: (context, _) {
                  final progress = _searchAnimController.value;
                  if (progress == 0.0 && !_isSearching) {
                    return const SizedBox.shrink();
                  }

                  final curvedProgress = CurvedAnimation(
                    parent: _searchAnimController,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  ).value;

                  final cs = Theme.of(context).colorScheme;

                  final topPadding = MediaQuery.paddingOf(context).top;
                  return Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: topPadding + kToolbarHeight,
                    child: SafeArea(
                      bottom: false,
                      child: SizedBox(
                        height: kToolbarHeight,
                        child: Center(
                          child: Opacity(
                            opacity: curvedProgress.clamp(0.0, 1.0),
                            child: Transform.translate(
                              offset:
                                  Offset(20.0 * (1.0 - curvedProgress), 0.0),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        height: 40,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest
                                              .withValues(alpha: 0.5),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.search_rounded,
                                              size: 18,
                                              color: cs.onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: TextField(
                                                controller: _searchController,
                                                focusNode: _searchFocusNode,
                                                style: const TextStyle(
                                                    fontSize: 14),
                                                decoration: InputDecoration(
                                                  hintText:
                                                      context.tr.searchHint,
                                                  isDense: true,
                                                  contentPadding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                          vertical: 8),
                                                  border: InputBorder.none,
                                                  hintStyle: TextStyle(
                                                    color: cs.onSurfaceVariant,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                onChanged: (q) => setState(() =>
                                                    _searchQuery = q.trim()),
                                              ),
                                            ),
                                            if (_searchController
                                                .text.isNotEmpty)
                                              BouncyTap(
                                                scaleDown: 0.88,
                                                onTap: () {
                                                  _searchController.clear();
                                                  setState(
                                                      () => _searchQuery = '');
                                                },
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          left: 4),
                                                  child: Icon(
                                                    Icons.cancel,
                                                    size: 18,
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    BouncyTap(
                                      key: const ValueKey(
                                          'search_cancel_button'),
                                      scaleDown: 0.92,
                                      onTap: _clearSearch,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6.0,
                                          vertical: 6.0,
                                        ),
                                        child: Text(
                                          context.tr.cancel,
                                          style: TextStyle(
                                            color: cs.primary,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          automaticallyImplyLeading: false,
          leading: null,
          titleSpacing: 16.0,
          centerTitle: !_selecting,
          title: AnimatedBuilder(
            animation: _searchAnimController,
            builder: (context, child) {
              final normalOpacity =
                  (1.0 - _searchAnimController.value * 1.5).clamp(0.0, 1.0);
              return Opacity(
                opacity: normalOpacity,
                child: IgnorePointer(
                  ignoring: _searchAnimController.value > 0.0 || _isSearching,
                  child: child,
                ),
              );
            },
            child: _selecting
                ? Text('${_selected.length} ${context.tr.selected}')
                : const AnimatedFlameTitle(title: 'Phantek'),
          ),
          actions: [
            AnimatedBuilder(
              animation: _searchAnimController,
              builder: (context, child) {
                final normalOpacity =
                    (1.0 - _searchAnimController.value * 1.5).clamp(0.0, 1.0);
                return Opacity(
                  opacity: normalOpacity,
                  child: IgnorePointer(
                    ignoring: _searchAnimController.value > 0.0 || _isSearching,
                    child: child,
                  ),
                );
              },
              child:
                  _buildNormalActions(context, mediaAsync, settings, isAlbums),
            ),
          ],
          bottom: FilterSortBar(
            currentFilter: _tabs[_currentPage],
            onFilterChanged: _onTabSelected,
            pageController: _pageController,
            isDirectTabTransition: _isTabTapTransition,
          ),
        ),
        body: Builder(
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

            _updateMemoizedTabs(allItems, settings);

            return NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollStartNotification &&
                    notification.dragDetails != null &&
                    (_isTabTapTransition || _pendingTapTargetPage != null)) {
                  _tabTapTimer?.cancel();
                  setState(() {
                    _isTabTapTransition = false;
                    _pendingTapTargetPage = null;
                  });
                }
                return false;
              },
              child: PageView.builder(
                controller: _pageController,
                physics: _selecting
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                onPageChanged: _onPageChanged,
                itemCount: _tabs.length,
                itemBuilder: (context, index) {
                  final tab = _tabs[index];
                  if (tab == FilterOption.albums) {
                    return _KeepAlivePage(
                      child: _buildAlbumsGrid(
                        albums: _memoizedAlbums,
                        settings: settings,
                        storageKey: 'gallery_tab_albums',
                      ),
                    );
                  }
                  final List<MediaItem> tabItems;
                  switch (tab) {
                    case FilterOption.photosOnly:
                      tabItems = _memoizedPhotos;
                      break;
                    case FilterOption.videosOnly:
                      tabItems = _memoizedVideos;
                      break;
                    default:
                      tabItems = _memoizedAll;
                      break;
                  }
                  return _KeepAlivePage(
                    child: HeroMode(
                      enabled: _currentPage == index,
                      child: _buildMediaGrid(
                        items: tabItems,
                        tab: tab,
                        settings: settings,
                        storageKey: 'gallery_tab_${tab.name}',
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNormalActions(
    BuildContext context,
    AsyncValue<List<MediaItem>> mediaAsync,
    SettingsModel settings,
    bool isAlbums,
  ) {
    if (_selecting) {
      if (isAlbums) {
        final allItems = mediaAsync.value ?? [];
        final allAlbums = groupMediaIntoAlbums(
          allItems,
          sort: settings.defaultSort,
          favoriteIds: settings.favoriteIds,
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BouncyTap(
              scaleDown: 0.88,
              child: IconButton(
                icon: const Icon(Icons.select_all),
                tooltip: context.tr.selectAll,
                onPressed: () {
                  setState(() {
                    if (_selected.length == allAlbums.length) {
                      _selected.clear();
                    } else {
                      _selected.addAll(allAlbums.map((e) => e.name));
                    }
                  });
                },
              ),
            ),
            BouncyTap(
              scaleDown: 0.88,
              child: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: context.tr.deleteSelectedAlbums,
                onPressed: () => _deleteSelectedAlbums(allItems, allAlbums),
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
        );
      } else {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BouncyTap(
              scaleDown: 0.88,
              child: IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: context.tr.share,
                onPressed: () {
                  final paths = (mediaAsync.value ?? [])
                      .where((e) => _selected.contains(e.id))
                      .map((e) => e.path)
                      .toList();
                  if (paths.isNotEmpty) {
                    ShareService.shareFiles(paths);
                  }
                },
              ),
            ),
            BouncyTap(
              scaleDown: 0.88,
              child: IconButton(
                icon: const Icon(Icons.select_all),
                tooltip: context.tr.selectAll,
                onPressed: () {
                  final all = _currentTabItems;
                  setState(() {
                    if (_selected.length == all.length) {
                      _selected.clear();
                    } else {
                      _selected.addAll(all.map((e) => e.id));
                    }
                  });
                },
              ),
            ),
            BouncyTap(
              scaleDown: 0.88,
              child: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: context.tr.deleteSelected,
                onPressed: () => _deleteSelected(mediaAsync.value ?? []),
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
        );
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BouncyTap(
          scaleDown: 0.88,
          child: IconButton(
            icon: const Icon(Icons.search),
            tooltip: context.tr.searchTooltip,
            onPressed: _openSearch,
          ),
        ),
        StyledMoreMenuButton<String>(
          splashRadius: 20,
          tooltip: context.tr.moreOptions,
          placement: StyledMenuPlacement.topBar,
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'slideshow') {
              final items = _currentTabItems;
              if (items.isNotEmpty) {
                final hasVideos = items.any((e) => e.isVideo);
                if (hasVideos) {
                  Navigator.of(context)
                      .openVideo(items, 0, startSlideshow: true);
                } else {
                  Navigator.of(context)
                      .openImage(items, 0, startSlideshow: true);
                }
              }
            } else if (value == 'manga') {
              MangaFolderPickerSheet.show(
                context,
                allItems: mediaAsync.value ?? [],
              );
            } else if (value == 'select') {
              setState(() {
                _selecting = true;
              });
            } else if (value == 'trash') {
              Navigator.of(context).openTrash();
            } else if (value == 'settings') {
              Navigator.of(context).openSettings();
            }
          },
          actions: [
            StyledMenuAction(
              value: 'slideshow',
              icon: Icons.slideshow_rounded,
              label: context.tr.slideshow,
            ),
            StyledMenuAction(
              value: 'manga',
              icon: Icons.auto_stories_rounded,
              label: context.tr.readAsManga,
            ),
            StyledMenuAction(
              value: 'select',
              icon: Icons.checklist_rounded,
              label: context.tr.select,
            ),
            StyledMenuAction(
              value: 'trash',
              icon: Icons.delete_sweep_outlined,
              label: context.tr.trashBin,
            ),
            StyledMenuAction(
              value: 'settings',
              icon: Icons.settings_outlined,
              label: context.tr.settings,
            ),
          ],
        ),
      ],
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
                          ? context.tr.noMediaMatching(_searchQuery)
                          : (tab == FilterOption.videosOnly
                              ? context.tr.noVideosFound
                              : context.tr.noPhotosFound),
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

    final controller = _scrollControllers[tab]!;
    final aspectRatio =
        settings.thumbnailCropStyle == ThumbnailCropStyle.adaptive ? 0.8 : 1.0;

    if (settings.timelineGrouping == TimelineGrouping.continuous) {
      final indexMap = switch (tab) {
        FilterOption.photosOnly => _memoizedPhotosIndex,
        FilterOption.videosOnly => _memoizedVideosIndex,
        _ => _memoizedAllIndex,
      };
      return _PinchZoomGridListener(
        child: FastScrollHandle(
          controller: controller,
          child: RefreshIndicator(
            onRefresh: () => ref.read(mediaListProvider.notifier).refresh(),
            child: GridView.builder(
              key: PageStorageKey(storageKey),
              controller: controller,
              cacheExtent: 800.0,
              addAutomaticKeepAlives: false,
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: settings.gridColumns,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
                childAspectRatio: aspectRatio,
              ),
              itemCount: items.length,
              findChildIndexCallback: (Key key) {
                if (key is ValueKey<String>) {
                  return indexMap[key.value];
                }
                return null;
              },
              itemBuilder: (_, i) => _buildMediaGridItem(items, i, tab, settings),
            ),
          ),
        ),
      );
    }

    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final todayKey = now.year * 10000 + now.month * 100 + now.day;
    Map<String, List<int>> groups;
    Map<String, Map<String, int>> groupIndexMaps;
    if (identical(_cachedGroupItems[tab], items) &&
        _cachedGroupTimelineGrouping[tab] == settings.timelineGrouping &&
        _cachedGroupDay[tab] == todayKey &&
        _cachedGroupResult[tab] != null &&
        _cachedGroupIndexMaps[tab] != null) {
      groups = _cachedGroupResult[tab]!;
      groupIndexMaps = _cachedGroupIndexMaps[tab]!;
    } else {
      groups = <String, List<int>>{};
      groupIndexMaps = <String, Map<String, int>>{};
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        final key = _formatTimelineGroupKey(
          item.date,
          settings.timelineGrouping,
          today: todayDate,
        );
        final list = groups.putIfAbsent(key, () => []);
        final idMap = groupIndexMaps.putIfAbsent(key, () => {});
        idMap[item.id] = list.length;
        list.add(i);
      }
      _cachedGroupItems[tab] = items;
      _cachedGroupTimelineGrouping[tab] = settings.timelineGrouping;
      _cachedGroupDay[tab] = todayKey;
      _cachedGroupResult[tab] = groups;
      _cachedGroupIndexMaps[tab] = groupIndexMaps;
    }

    final cs = Theme.of(context).colorScheme;

    return _PinchZoomGridListener(
      child: FastScrollHandle(
        controller: controller,
        child: RefreshIndicator(
          onRefresh: () => ref.read(mediaListProvider.notifier).refresh(),
          child: CustomScrollView(
            key: PageStorageKey(storageKey),
            controller: controller,
            cacheExtent: 800.0,
            slivers: [
              for (final entry in groups.entries) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 18, 14, 6),
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: settings.gridColumns,
                      crossAxisSpacing: 3,
                      mainAxisSpacing: 3,
                      childAspectRatio: aspectRatio,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _buildMediaGridItem(
                        items,
                        entry.value[i],
                        tab,
                        settings,
                      ),
                      childCount: entry.value.length,
                      addAutomaticKeepAlives: false,
                      findChildIndexCallback: (Key key) {
                        if (key is ValueKey<String>) {
                          return groupIndexMaps[entry.key]?[key.value];
                        }
                        return null;
                      },
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimelineGroupKey(
    DateTime date,
    TimelineGrouping grouping, {
    DateTime? today,
  }) {
    if (grouping == TimelineGrouping.monthly) {
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      return '${months[date.month - 1]} ${date.year}';
    }
    final effectiveToday = today ??
        () {
          final now = DateTime.now();
          return DateTime(now.year, now.month, now.day);
        }();
    final target = DateTime(date.year, date.month, date.day);
    final diff = effectiveToday.difference(target).inDays;
    if (diff == 0) return context.tr.today;
    if (diff == 1) return context.tr.yesterday;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget _buildMediaGridItem(
    List<MediaItem> items,
    int index,
    FilterOption tab,
    SettingsModel settings,
  ) {
    final item = items[index];
    return MediaGridItem(
      key: ValueKey(item.id),
      item: item,
      cropStyle: settings.thumbnailCropStyle,
      isSelected: _selected.contains(item.id),
      isSelecting: _selecting,
      showBadges: settings.showBadges,
      onTap: () {
        if (_selecting) {
          _toggleSelect(item.id);
          return;
        }
        if (item.isVideo) {
          Navigator.of(context).openVideo(items, index);
        } else {
          Navigator.of(context).openImage(items, index);
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
                          ? context.tr.noAlbumsMatching(_searchQuery)
                          : context.tr.noAlbumsFound,
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

    final controller = _scrollControllers[FilterOption.albums]!;

    return FastScrollHandle(
      controller: controller,
      child: RefreshIndicator(
        onRefresh: () => ref.read(mediaListProvider.notifier).refresh(),
        child: GridView.builder(
          key: PageStorageKey(storageKey),
          controller: controller,
          addAutomaticKeepAlives: false,
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
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_library_outlined,
              size: 80, color: Colors.white38),
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

/// Keeps PageView children alive in memory.
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
    return RepaintBoundary(child: widget.child);
  }
}

/// Detects 2-finger pinch gestures to dynamically change grid columns (2 to 5).
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
