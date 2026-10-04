import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/media_item.dart';
import '../enums/sort_option.dart';
import '../enums/filter_option.dart';
import '../services/media_scanner_service.dart';
import '../services/media_cache_service.dart';
import 'settings_provider.dart';

/// Singleton scanner – no analytics, no network, 100% local.
final mediaScannerProvider = Provider<MediaScannerService>(
  (_) => MediaScannerService(),
);

/// Raw scanned media list state.
class MediaListNotifier extends AsyncNotifier<List<MediaItem>> {
  final Set<String> _deletedIds = {};
  bool _backgroundRefreshing = false;

  @override
  Future<List<MediaItem>> build() async {
    final excludedFolders = ref.watch(
      settingsNotifierProvider.select((s) => s.excludedFolders),
    );

    // 1. Load from disk cache instantly (no spinner on re-open)
    final cached = await MediaCacheService.instance.load();
    if (cached != null && cached.isNotEmpty) {
      // Filter stale items from excluded folders and recently deleted IDs
      final visible = cached
          .where((e) => !excludedFolders.any((f) => e.path.startsWith(f)))
          .where((e) => !_deletedIds.contains(e.id))
          .toList();

      // Kick off background refresh so new/deleted files are picked up
      Future.microtask(() => _backgroundRefresh(excludedFolders));
      return visible;
    }

    // 2. First launch: full scan (no cache yet)
    return _scan(excludedFolders);
  }

  Future<List<MediaItem>> _scan(List<String> excludedFolders) async {
    final scanner = ref.read(mediaScannerProvider);
    final items = await scanner.scanAll(excludedFolders: excludedFolders);
    // Persist unfiltered list for next startup
    MediaCacheService.instance.save(items);
    if (_deletedIds.isEmpty) return items;
    return items.where((e) => !_deletedIds.contains(e.id)).toList();
  }

  Future<void> _backgroundRefresh(List<String> excludedFolders) async {
    if (_backgroundRefreshing) return;
    _backgroundRefreshing = true;
    try {
      final fresh = await _scan(excludedFolders);
      // Only update if we're still showing data (not re-loading)
      if (state.hasValue) {
        state = AsyncData(fresh);
      }
    } catch (_) {
    } finally {
      _backgroundRefreshing = false;
    }
  }

  /// Set of deleted/trashed IDs currently filtered out from scans.
  Set<String> get deletedIds => Set.unmodifiable(_deletedIds);

  /// Instantly removes items from state so the UI reflects deletions immediately.
  void removeItems(Iterable<String> ids) {
    _deletedIds.addAll(ids);
    state = state.whenData(
      (items) => items.where((e) => !_deletedIds.contains(e.id)).toList(),
    );
  }

  /// Un-blacklists items when restored from trash.
  void restoreItems(Iterable<String> ids) {
    _deletedIds.removeAll(ids);
  }

  /// Updates a single item in state (e.g. after rename).
  void updateItem(MediaItem updated) {
    state = state.whenData(
      (items) => items.map((e) => e.id == updated.id ? updated : e).toList(),
    );
  }

  /// Refreshes from disk without blanking the UI with a full loading spinner.
  Future<void> refresh() async {
    final settings = ref.read(settingsNotifierProvider);
    final updated = await AsyncValue.guard(
      () => _scan(settings.excludedFolders),
    );
    if (updated.hasValue) {
      state = updated;
    }
  }
}

final mediaListProvider =
    AsyncNotifierProvider<MediaListNotifier, List<MediaItem>>(MediaListNotifier.new);

/// Derived provider: applies sort + filter on top of [mediaListProvider].
final filteredMediaProvider = Provider<AsyncValue<List<MediaItem>>>((ref) {
  final raw      = ref.watch(mediaListProvider);
  final settings = ref.watch(settingsNotifierProvider);
  return raw.whenData((items) => applyFiltersAndSort(
        items,
        sort:   settings.defaultSort,
        filter: settings.defaultFilter,
      ));
});

List<MediaItem> applyFiltersAndSort(
  List<MediaItem> items, {
  required SortOption sort,
  required FilterOption filter,
}) {
  var result = switch (filter) {
    FilterOption.all || FilterOption.albums => items,
    FilterOption.photosOnly => items.where((e) => !e.isVideo).toList(),
    FilterOption.videosOnly => items.where((e) => e.isVideo).toList(),
  };

  return switch (sort) {
    SortOption.newest => [...result]..sort((a, b) => b.timeAdded.compareTo(a.timeAdded)),
    SortOption.oldest => [...result]..sort((a, b) => a.timeAdded.compareTo(b.timeAdded)),
    SortOption.shootingTimeDesc => [...result]..sort((a, b) => b.date.compareTo(a.date)),
    SortOption.shootingTimeAsc => [...result]..sort((a, b) => a.date.compareTo(b.date)),
    SortOption.nameAZ => [...result]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    SortOption.nameZA => [...result]
        ..sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase())),
    SortOption.sizeDesc => [...result]..sort((a, b) => b.size.compareTo(a.size)),
    SortOption.sizeAsc => [...result]..sort((a, b) => a.size.compareTo(b.size)),
  };
}
