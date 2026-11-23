import 'dart:async';
import 'dart:io';
import 'dart:ui';
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
import '../../../core/widgets/styled_popup_menu.dart';
import 'widgets/album_grid_item.dart';
import 'widgets/drag_select_grid.dart';
import 'widgets/fast_scroll_handle.dart';
import 'widgets/filter_sort_bar.dart';
import 'widgets/grid_hi_res_scope.dart';
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

class _AlbumDetailScreenState extends ConsumerState<AlbumDetailScreen>
    with SingleTickerProviderStateMixin {
  static const List<FilterOption> _tabs = [
    FilterOption.all,
    FilterOption.photosOnly,
    FilterOption.videosOnly,
  ];
  static const List<String> _monthNames = [
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
    'Dec',
  ];

  final Set<String> _selected = {};
  bool _selecting = false;
  FilterOption _filter = FilterOption.all;
  SortOption? _sort;
  bool _flattenSubfolders = true;
  String? _selectedSubfolder;
  final Map<FilterOption, ScrollController> _scrollControllers = {
    FilterOption.all: ScrollController(),
    FilterOption.photosOnly: ScrollController(),
    FilterOption.videosOnly: ScrollController(),
  };
  late final ScrollController _subfolderScrollController = ScrollController();
  late PageController _pageController = PageController(initialPage: 0);
  bool _isTabTapTransition = false;
  int? _pendingTapTargetPage;
  Timer? _tabTapTimer;
  late final AnimationController _searchAnimController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  late final CurvedAnimation _searchCurvedAnim = CurvedAnimation(
    parent: _searchAnimController,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  Timer? _searchDebounce;

  List<MediaItem>? _cachedAllItemsRef;
  String? _cachedAlbumName;
  bool? _cachedShowHidden;
  bool? _cachedFilterSmall;
  List<String>? _cachedFavoriteIds;
  String? _cachedSelectedSubfolder;
  SortOption? _cachedActiveSort;
  String? _cachedSearchQuery;
  bool? _cachedFlattenSubfolders;

  List<MediaItem> _memoizedAlbumItems = const [];
  Map<String, List<MediaItem>> _memoizedSubfolderItemsMap = const {};
  List<String> _memoizedSubfolderNames = const [];
  bool _memoizedHasSubfolders = false;
  List<MediaItem> _memoizedScopedItems = const [];
  Map<FilterOption, List<MediaItem>> _memoizedByTab = {
    FilterOption.all: const [],
    FilterOption.photosOnly: const [],
    FilterOption.videosOnly: const [],
  };

  @override
  void dispose() {
    _tabTapTimer?.cancel();
    _searchDebounce?.cancel();
    _searchCurvedAnim.dispose();
    _searchAnimController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _pageController.dispose();
    _subfolderScrollController.dispose();
    for (final c in _scrollControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncPageControllerToFilter() {
    final targetIdx = _tabs.indexOf(_filter).clamp(0, _tabs.length - 1);
    if (_pageController.hasClients) {
      if (_pageController.page?.round() != targetIdx) {
        _pageController.jumpToPage(targetIdx);
      }
    } else if (_pageController.initialPage != targetIdx) {
      final oldController = _pageController;
      _pageController = PageController(initialPage: targetIdx);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldController.dispose();
      });
    }
  }

  void _onTabSelected(FilterOption f) {
    final targetIdx = _tabs.indexOf(f);
    if (targetIdx != -1 && f != _filter) {
      _tabTapTimer?.cancel();
      setState(() {
        _filter = f;
        _isTabTapTransition = true;
        _pendingTapTargetPage = targetIdx;
        if (_selected.isNotEmpty) {
          _selected.clear();
          _selecting = false;
        }
        if (!_pageController.hasClients) {
          _syncPageControllerToFilter();
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
    final nextFilter = _tabs[index];
    if (_filter != nextFilter) {
      setState(() {
        _filter = nextFilter;
        if (_selected.isNotEmpty) {
          _selected.clear();
          _selecting = false;
        }
      });
    }
  }

  int _compareMangaCanonical(
    MediaItem a,
    MediaItem b,
    bool hasSubfolders,
  ) {
    if (hasSubfolders && _selectedSubfolder == null) {
      final folderCmp =
          naturalCompare(a.immediateFolderName, b.immediateFolderName);
      if (folderCmp != 0) return folderCmp;
    }
    return naturalCompare(a.name, b.name);
  }

  List<MediaItem> _filterAndSortItems(
    List<MediaItem> scopedItems,
    FilterOption filter,
    SortOption activeSort,
    bool hasSubfolders,
  ) {
    var filteredItems = switch (filter) {
      FilterOption.photosOnly => scopedItems.where((e) => !e.isVideo).toList(),
      FilterOption.videosOnly => scopedItems.where((e) => e.isVideo).toList(),
      _ => scopedItems,
    };
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filteredItems = filteredItems
          .where((e) => e.name.toLowerCase().contains(q))
          .toList();
    }

    return switch (activeSort) {
      SortOption.newest => [...filteredItems]
        ..sort((a, b) => b.timeAdded.compareTo(a.timeAdded)),
      SortOption.oldest => [...filteredItems]
        ..sort((a, b) => a.timeAdded.compareTo(b.timeAdded)),
      SortOption.shootingTimeDesc => [...filteredItems]
        ..sort((a, b) => b.date.compareTo(a.date)),
      SortOption.shootingTimeAsc => [...filteredItems]
        ..sort((a, b) => a.date.compareTo(b.date)),
      SortOption.nameAZ => [...filteredItems]
        ..sort((a, b) => _compareMangaCanonical(a, b, hasSubfolders)),
      SortOption.nameZA => [...filteredItems]
        ..sort((a, b) => _compareMangaCanonical(b, a, hasSubfolders)),
      SortOption.sizeDesc => [...filteredItems]
        ..sort((a, b) => b.size.compareTo(a.size)),
      SortOption.sizeAsc => [...filteredItems]
        ..sort((a, b) => a.size.compareTo(b.size)),
      SortOption.albumAZ => [...filteredItems]
        ..sort((a, b) => _compareMangaCanonical(a, b, hasSubfolders)),
      SortOption.albumZA => [...filteredItems]
        ..sort((a, b) => _compareMangaCanonical(b, a, hasSubfolders)),
    };
  }

  void _scrollToActiveMedia(
    String mediaId,
    List<MediaItem> sortedItems,
    SettingsModel settings,
  ) {
    final controller = _scrollControllers[_filter];
    if (!mounted || controller == null || !controller.hasClients) return;
    final index = sortedItems.indexWhere((e) => e.id == mediaId);
    if (index < 0) return;

    final targetOffset = MediaUtils.calculateGridScrollOffset(
      index: index,
      crossAxisCount: settings.gridColumns,
      screenWidth: MediaQuery.sizeOf(context).width,
      viewportHeight: controller.position.viewportDimension,
      currentScrollOffset: controller.offset,
      maxScrollExtent: controller.position.maxScrollExtent,
      paddingHorizontal: 4.0,
      paddingTop: 2.0,
      spacing: 2.0,
    );

    if ((targetOffset - controller.offset).abs() > 1.0) {
      controller.jumpTo(targetOffset);
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

  void _openSearch() {
    setState(() => _isSearching = true);
    _searchAnimController.forward().then((_) {
      if (mounted && _isSearching) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _closeSearch() {
    _searchDebounce?.cancel();
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

  void _onSearchChanged(String raw, int sourceCount) {
    final q = raw.trim();
    if (q.isEmpty || sourceCount <= 250) {
      _searchDebounce?.cancel();
      if (_searchQuery != q) {
        setState(() => _searchQuery = q);
      }
      return;
    }
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted && _searchQuery != q) {
        setState(() => _searchQuery = q);
      }
    });
  }

  void _updateMemoizedAlbumState(
    List<MediaItem> allItems,
    SettingsModel settings,
  ) {
    final baseUnchanged = identical(_cachedAllItemsRef, allItems) &&
        _cachedAlbumName == widget.albumName &&
        _cachedShowHidden == settings.showHiddenFiles &&
        _cachedFilterSmall == settings.filterSmallImages &&
        _cachedFavoriteIds == settings.favoriteIds &&
        _cachedSelectedSubfolder == _selectedSubfolder;

    final activeSort = _sort ?? settings.defaultSort;
    final tabsUnchanged = baseUnchanged &&
        _cachedActiveSort == activeSort &&
        _cachedSearchQuery == _searchQuery &&
        _cachedFlattenSubfolders == _flattenSubfolders;

    if (tabsUnchanged) {
      return;
    }

    if (!baseUnchanged) {
      _cachedAllItemsRef = allItems;
      _cachedAlbumName = widget.albumName;
      _cachedShowHidden = settings.showHiddenFiles;
      _cachedFilterSmall = settings.filterSmallImages;
      _cachedFavoriteIds = settings.favoriteIds;
      _cachedSelectedSubfolder = _selectedSubfolder;

      var filtered = allItems;
      if (!settings.showHiddenFiles) {
        filtered =
            filtered.where((e) => !MediaUtils.isHiddenPath(e.path)).toList();
      }
      if (settings.filterSmallImages) {
        filtered =
            filtered.where((e) => e.isVideo || e.size >= 50 * 1024).toList();
      }
      final albumItems = widget.albumName == 'Favorites'
          ? filtered.where((e) => settings.favoriteIds.contains(e.id)).toList()
          : filtered
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

      _memoizedAlbumItems = albumItems;
      _memoizedSubfolderItemsMap = subfolderItemsMap;
      _memoizedSubfolderNames = subfolderNames;
      _memoizedHasSubfolders = hasSubfolders;
      _memoizedScopedItems = scopedItems;
    }

    _cachedActiveSort = activeSort;
    _cachedSearchQuery = _searchQuery;
    _cachedFlattenSubfolders = _flattenSubfolders;

    _memoizedByTab = {
      for (final tab in _tabs)
        tab: _filterAndSortItems(
          _memoizedScopedItems,
          tab,
          activeSort,
          _memoizedHasSubfolders,
        ),
    };
  }

  String? _buildScrollLabel(
    List<MediaItem> items,
    double fraction,
    SortOption activeSort,
  ) {
    if (activeSort.criterion != SortCriterion.timeAdded &&
        activeSort.criterion != SortCriterion.shootingTime) {
      return null;
    }
    if (items.isEmpty) return null;
    final index = (fraction.clamp(0.0, 1.0) * (items.length - 1)).round();
    final item = items[index];
    final useShootingDate = activeSort == SortOption.shootingTimeDesc ||
        activeSort == SortOption.shootingTimeAsc;
    final dt = useShootingDate ? item.date : item.timeAdded;
    return '${_monthNames[dt.month - 1]} ${dt.year}';
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
    final cs = Theme.of(context).colorScheme;
    final mediaAsync = ref.watch(mediaListProvider);
    final settings = ref.watch(settingsNotifierProvider);

    final rawAllItems = mediaAsync.value ?? const <MediaItem>[];
    _updateMemoizedAlbumState(rawAllItems, settings);
    final albumItems = _memoizedAlbumItems;
    final subfolderItemsMap = _memoizedSubfolderItemsMap;
    final subfolderNames = _memoizedSubfolderNames;
    final hasSubfolders = _memoizedHasSubfolders;

    // 1. Filter & sort for active tab (app bar count, actions, active-media listener)
    final activeSort = _sort ?? settings.defaultSort;
    final sortedItems = _memoizedByTab[_filter]!;
    final isShowingSubfolderGrid =
        hasSubfolders && !_flattenSubfolders && _selectedSubfolder == null;

    if (albumItems.isNotEmpty &&
        !isShowingSubfolderGrid &&
        !_pageController.hasClients &&
        _pageController.initialPage != _tabs.indexOf(_filter)) {
      final targetIdx = _tabs.indexOf(_filter).clamp(0, _tabs.length - 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(targetIdx);
        }
      });
    }

    ref.listen<String?>(activeViewerMediaIdProvider, (_, nextId) {
      if (nextId != null) {
        _scrollToActiveMedia(nextId, sortedItems, settings);
      }
    });

    return PopScope(
      canPop: !_selecting && !_isSearching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_selecting) {
            _clearSelection();
          } else if (_isSearching) {
            _closeSearch();
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
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context)
                          .scaffoldBackgroundColor
                          .withValues(alpha: 0.60),
                      Theme.of(context)
                          .scaffoldBackgroundColor
                          .withValues(alpha: 0.42),
                      Theme.of(context)
                          .scaffoldBackgroundColor
                          .withValues(alpha: 0.08),
                    ],
                    stops: const [0.0, 0.56, 1.0],
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _searchAnimController,
                builder: (context, _) {
                  final progress = _searchAnimController.value;
                  if (progress == 0.0 && !_isSearching) {
                    return const SizedBox.shrink();
                  }

                  final curvedProgress = _searchCurvedAnim.value;

                  final cs = Theme.of(context).colorScheme;
                  final topPadding = MediaQuery.paddingOf(context).top;
                  final clampedProgress = curvedProgress.clamp(0.0, 1.0);
                  final blurSigma = 20.0 * clampedProgress;

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
                          child: Transform.translate(
                            offset: Offset(20.0 * (1.0 - curvedProgress), 0.0),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(20),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(
                                          sigmaX: blurSigma,
                                          sigmaY: blurSigma,
                                        ),
                                        child: Container(
                                          height: 40,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12),
                                          decoration: BoxDecoration(
                                            color: cs.surfaceContainerHighest
                                                .withValues(
                                                    alpha:
                                                        0.68 * clampedProgress),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Opacity(
                                            opacity: clampedProgress,
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
                                                    key: const ValueKey(
                                                        'album_search_field'),
                                                    controller:
                                                        _searchController,
                                                    focusNode: _searchFocusNode,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      color: cs.onSurface,
                                                    ),
                                                    textInputAction:
                                                        TextInputAction.search,
                                                    decoration: InputDecoration(
                                                      hintText: context
                                                          .tr.searchInAlbumHint,
                                                      isDense: true,
                                                      contentPadding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                              vertical: 8),
                                                      border: InputBorder.none,
                                                      hintStyle: TextStyle(
                                                        color:
                                                            cs.onSurfaceVariant,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                    onChanged: (q) =>
                                                        _onSearchChanged(
                                                      q,
                                                      _memoizedScopedItems
                                                          .length,
                                                    ),
                                                    onSubmitted: (raw) {
                                                      _searchDebounce?.cancel();
                                                      final q = raw.trim();
                                                      if (_searchQuery != q) {
                                                        setState(() =>
                                                            _searchQuery = q);
                                                      }
                                                    },
                                                  ),
                                                ),
                                                ValueListenableBuilder<
                                                    TextEditingValue>(
                                                  valueListenable:
                                                      _searchController,
                                                  builder:
                                                      (context, value, _) {
                                                    if (value.text.isEmpty) {
                                                      return const SizedBox
                                                          .shrink();
                                                    }
                                                    return BouncyTap(
                                                      scaleDown: 0.88,
                                                      onTap: () {
                                                        _searchDebounce
                                                            ?.cancel();
                                                        _searchController
                                                            .clear();
                                                        if (_searchQuery
                                                            .isNotEmpty) {
                                                          setState(() =>
                                                              _searchQuery =
                                                                  '');
                                                        }
                                                      },
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(left: 4),
                                                        child: Icon(
                                                          Icons.close_rounded,
                                                          size: 18,
                                                          color: cs
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Opacity(
                                    opacity: clampedProgress,
                                    child: BouncyTap(
                                      key: const ValueKey(
                                          'album_search_cancel_button'),
                                      scaleDown: 0.92,
                                      onTap: _closeSearch,
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
                                  ),
                                ],
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
          leading: AnimatedBuilder(
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
            child: BouncyTap(
              scaleDown: 0.88,
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (_isSearching) {
                    _closeSearch();
                  } else if (_selectedSubfolder != null && !_flattenSubfolders) {
                    setState(() => _selectedSubfolder = null);
                  } else {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),
          ),
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
            child: Builder(
              builder: (context) {
                final cs = Theme.of(context).colorScheme;
                final haloColor = Theme.of(context).scaffoldBackgroundColor;
                final textShadows = [
                  Shadow(
                    color: haloColor.withValues(alpha: 0.92),
                    blurRadius: 8,
                  ),
                  Shadow(
                    color: haloColor.withValues(alpha: 0.75),
                    blurRadius: 2,
                  ),
                ];

                if (_selecting) {
                  return Text(
                    '${_selected.length} ${context.tr.selected}',
                    style: TextStyle(shadows: textShadows),
                  );
                }

                return Align(
                  key: const ValueKey('album_title_column'),
                  alignment: AlignmentDirectional.centerStart,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.albumName == 'Favorites'
                            ? context.tr.favorites
                            : (_selectedSubfolder != null && !_flattenSubfolders
                                ? '${widget.albumName} / $_selectedSubfolder'
                                : widget.albumName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                          shadows: textShadows,
                        ),
                      ),
                      Text(
                        context.tr.itemsCount(sortedItems.length),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w500,
                          shadows: textShadows,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_selecting)
                    BouncyTap(
                      scaleDown: 0.88,
                      child: IconButton(
                        icon: Icon(
                          Icons.search,
                          semanticLabel: context.tr.searchTooltip,
                        ),
                        onPressed: _openSearch,
                      ),
                    ),
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
                            if (_flattenSubfolders) {
                              _syncPageControllerToFilter();
                            }
                          });
                        },
                      ),
                    ),
                  if (!_selecting)
                    BouncyTap(
                      scaleDown: 0.88,
                      child: StyledMoreMenuButton<String>(
                        splashRadius: 20,
                        disableSplash: true,
                        placement: StyledMenuPlacement.topBar,
                        icon: Icon(
                          Icons.more_vert,
                          semanticLabel: context.tr.moreOptions,
                        ),
                        onSelected: (value) {
                          if (value == 'manga') {
                            final mangaItems = sortedItems
                                .where((e) =>
                                    !e.isVideo && !PsdService.isPsd(e.path))
                                .toList()
                              ..sort((a, b) =>
                                  _compareMangaCanonical(a, b, hasSubfolders));
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
                              final hasVideos =
                                  sortedItems.any((e) => e.isVideo);
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
                        actions: [
                          if (sortedItems.isNotEmpty) ...[
                            StyledMenuAction(
                              value: 'manga',
                              icon: Icons.auto_stories_rounded,
                              label: context.tr.readAsManga,
                            ),
                            StyledMenuAction(
                              value: 'slideshow',
                              icon: Icons.slideshow_rounded,
                              label: context.tr.slideshow,
                            ),
                          ],
                          StyledMenuAction(
                            value: 'select',
                            icon: Icons.checklist_rounded,
                            label: context.tr.select,
                          ),
                        ],
                      ),
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
            ),
          ],
        ),
        body: Column(
          children: [
            FilterSortBar(
              isAlbumDetail: true,
              currentFilter: _filter,
              onFilterChanged: _onTabSelected,
              currentSort: activeSort,
              onSortChanged: (s) => setState(() => _sort = s),
              pageController: isShowingSubfolderGrid ? null : _pageController,
              isDirectTabTransition:
                  isShowingSubfolderGrid ? false : _isTabTapTransition,
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
                    Text('•', style: TextStyle(color: cs.onSurfaceVariant)),
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
                          Icon(
                            Icons.photo_library_outlined,
                            size: 64,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No media in ${widget.albumName}',
                            style: TextStyle(
                              fontSize: 16,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : isShowingSubfolderGrid
                      ? GridHiResScope(
                          child: FastScrollHandle(
                            controller: _subfolderScrollController,
                            child: GridView.builder(
                              controller: _subfolderScrollController,
                              cacheExtent: 350.0,
                              addAutomaticKeepAlives: false,
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
                                final subItems =
                                    subfolderItemsMap[sub] ?? const [];
                                final cover =
                                    subItems.isNotEmpty ? subItems.first : null;
                                if (cover == null) {
                                  return const SizedBox.shrink();
                                }
                                final subAlbum = Album(
                                  name: sub,
                                  items: subItems,
                                  coverItem: cover,
                                );
                                return AlbumGridItem(
                                  key: ValueKey(sub),
                                  album: subAlbum,
                                  onTap: () {
                                    setState(() {
                                      _selectedSubfolder = sub;
                                      _syncPageControllerToFilter();
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                        )
                      : NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification is ScrollStartNotification &&
                                notification.dragDetails != null &&
                                (_isTabTapTransition ||
                                    _pendingTapTargetPage != null)) {
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
                            itemCount: _tabs.length,
                            onPageChanged: _onPageChanged,
                            physics: _selecting
                                ? const NeverScrollableScrollPhysics()
                                : const PageScrollPhysics(),
                            itemBuilder: (context, index) {
                              final tab = _tabs[index];
                              final pageItems = _memoizedByTab[tab]!;
                              return _KeepAliveAlbumPage(
                                child: HeroMode(
                                  enabled: _filter == tab,
                                  child: GridHiResScope(
                                    enabled: _filter == tab,
                                    child: pageItems.isEmpty
                                        ? Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  _searchQuery.isNotEmpty
                                                      ? Icons.search_off_outlined
                                                      : Icons
                                                          .photo_library_outlined,
                                                  size: 56,
                                                  color: cs.onSurfaceVariant
                                                      .withValues(alpha: 0.45),
                                                ),
                                                const SizedBox(height: 12),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 24),
                                                  child: Text(
                                                    _searchQuery.isNotEmpty
                                                        ? context.tr
                                                            .noMediaMatching(
                                                                _searchQuery)
                                                        : 'No ${tab.label.toLowerCase()} in this album',
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      color: cs.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ),
                                                if (_searchQuery.isNotEmpty) ...[
                                                  const SizedBox(height: 16),
                                                  OutlinedButton.icon(
                                                    key: const ValueKey(
                                                        'album_clear_search_button'),
                                                    onPressed: _closeSearch,
                                                    icon: const Icon(
                                                      Icons.close_rounded,
                                                      size: 16,
                                                    ),
                                                    label: Text(
                                                      context.tr.clearSearch,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          )
                                        : FastScrollHandle(
                                            controller: _scrollControllers[tab]!,
                                            labelBuilder: (fraction) =>
                                                _buildScrollLabel(
                                              pageItems,
                                              fraction,
                                              activeSort,
                                            ),
                                            child: DragSelectGrid(
                                              isSelecting: _selecting,
                                              itemCount: pageItems.length,
                                              crossAxisCount:
                                                  settings.gridColumns,
                                              crossAxisSpacing: 2,
                                              mainAxisSpacing: 2,
                                              padding: const EdgeInsets.all(2),
                                              scrollController:
                                                  _scrollControllers[tab]!,
                                              idAt: (i) => pageItems[i].id,
                                              isSelected: (id) =>
                                                  _selected.contains(id),
                                              onRangeSelectionChanged:
                                                  (ids, select) {
                                                setState(() {
                                                  if (select) {
                                                    _selected.addAll(ids);
                                                    _selecting = true;
                                                  } else {
                                                    _selected.removeAll(ids);
                                                  }
                                                });
                                              },
                                              child: GridView.builder(
                                                key: PageStorageKey(
                                                  'album_${widget.albumName}_${_selectedSubfolder ?? 'all'}_${tab.name}',
                                                ),
                                                controller:
                                                    _scrollControllers[tab],
                                                cacheExtent: 350.0,
                                                addAutomaticKeepAlives: false,
                                                padding: const EdgeInsets.all(2),
                                                gridDelegate:
                                                    SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount:
                                                      settings.gridColumns,
                                                  crossAxisSpacing: 2,
                                                  mainAxisSpacing: 2,
                                                ),
                                                itemCount: pageItems.length,
                                                itemBuilder: (_, i) {
                                                  final item = pageItems[i];
                                                  return MediaGridItem(
                                                    key: ValueKey(item.id),
                                                    item: item,
                                                    isSelected: _selected
                                                        .contains(item.id),
                                                    isSelecting: _selecting,
                                                    showBadges:
                                                        settings.showBadges,
                                                    onTap: () {
                                                      if (_selecting) {
                                                        _toggleSelect(item.id);
                                                        return;
                                                      }
                                                      if (pageItems.every(
                                                          (e) => !e.isVideo)) {
                                                        Navigator.of(context)
                                                            .openImage(
                                                                pageItems, i);
                                                      } else {
                                                        Navigator.of(context)
                                                            .openVideo(
                                                                pageItems, i);
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
                                          ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps AlbumDetailScreen PageView tab pages alive in memory.
class _KeepAliveAlbumPage extends StatefulWidget {
  const _KeepAliveAlbumPage({required this.child});
  final Widget child;

  @override
  State<_KeepAliveAlbumPage> createState() => _KeepAliveAlbumPageState();
}

class _KeepAliveAlbumPageState extends State<_KeepAliveAlbumPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RepaintBoundary(child: widget.child);
  }
}
