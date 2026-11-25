import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/media_item.dart';
import '../enums/sort_option.dart';
import '../enums/filter_option.dart';
import '../utils/natural_sort.dart';
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
  Future<List<MediaItem>>? _inFlightScan;
  String? _inFlightExcludedKey;

  @override
  Future<List<MediaItem>> build() async {
    final excludedFolders = ref.watch(
      settingsNotifierProvider.select((s) => s.excludedFolders),
    );

    // Load from disk cache first for instant display.
    final cached = await MediaCacheService.instance.load();
    if (cached != null && cached.isNotEmpty) {
      // Filter out items in excluded folders and recently deleted IDs.
      final visible = cached
          .where((e) => !excludedFolders.any((f) => e.path.startsWith(f)))
          .where((e) => !_deletedIds.contains(e.id))
          .toList();

      // Trigger background refresh to detect file changes.
      Future.microtask(() => _backgroundRefresh(excludedFolders));
      return visible;
    }

    // Full media scan on initial launch.
    return _scan(excludedFolders);
  }

  String _excludedKey(List<String> excludedFolders) =>
      excludedFolders.join('\u0000');

  Future<List<MediaItem>> _scan(List<String> excludedFolders) async {
    final key = _excludedKey(excludedFolders);
    Future<List<MediaItem>> scanFuture;

    if (_inFlightScan != null && _inFlightExcludedKey == key) {
      scanFuture = _inFlightScan!;
    } else {
      final previous = _inFlightScan;
      if (previous != null) {
        // Wait for any overlapping scan with different excluded folders so two
        // full scans never run simultaneously.
        try {
          await previous;
        } catch (_) {}
        if (_inFlightScan != null && _inFlightExcludedKey == key) {
          scanFuture = _inFlightScan!;
        } else {
          scanFuture = _startScan(excludedFolders, key);
        }
      } else {
        scanFuture = _startScan(excludedFolders, key);
      }
    }

    final items = await scanFuture;
    if (_deletedIds.isEmpty) return items;
    return items.where((e) => !_deletedIds.contains(e.id)).toList();
  }

  Future<List<MediaItem>> _startScan(
    List<String> excludedFolders,
    String key,
  ) {
    final scanner = ref.read(mediaScannerProvider);
    late final Future<List<MediaItem>> future;
    future = () async {
      try {
        final items = await scanner.scanAll(excludedFolders: excludedFolders);
        // Persist full list to cache for subsequent launches.
        MediaCacheService.instance.save(items);
        return items;
      } finally {
        if (identical(_inFlightScan, future)) {
          _inFlightScan = null;
          _inFlightExcludedKey = null;
        }
      }
    }();
    _inFlightScan = future;
    _inFlightExcludedKey = key;
    return future;
  }

  Future<void> _backgroundRefresh(List<String> excludedFolders) async {
    if (_backgroundRefreshing) return;
    _backgroundRefreshing = true;
    try {
      final fresh = await _scan(excludedFolders);
      // Update data only if the current state is still active.
      if (state.hasValue) {
        state = AsyncData(fresh);
      }
    } catch (_) {
    } finally {
      _backgroundRefreshing = false;
    }
  }

  /// Set of deleted or trashed media IDs currently filtered out from scans.
  Set<String> get deletedIds => Set.unmodifiable(_deletedIds);

  /// Instantly removes items from state.
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

  /// Refreshes media list from disk in the background.
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
    AsyncNotifierProvider<MediaListNotifier, List<MediaItem>>(
        MediaListNotifier.new);

/// Derived provider: applies sort + filter on top of [mediaListProvider].
final filteredMediaProvider = Provider<AsyncValue<List<MediaItem>>>((ref) {
  final raw = ref.watch(mediaListProvider);
  final settings = ref.watch(settingsNotifierProvider);
  return raw.whenData((items) => applyFiltersAndSort(
        items,
        sort: settings.defaultSort,
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
    SortOption.newest => [...result]
      ..sort((a, b) => b.timeAdded.compareTo(a.timeAdded)),
    SortOption.oldest => [...result]
      ..sort((a, b) => a.timeAdded.compareTo(b.timeAdded)),
    SortOption.shootingTimeDesc => [...result]
      ..sort((a, b) => b.date.compareTo(a.date)),
    SortOption.shootingTimeAsc => [...result]
      ..sort((a, b) => a.date.compareTo(b.date)),
    SortOption.nameAZ => [...result]
      ..sort((a, b) => naturalCompare(a.name, b.name)),
    SortOption.nameZA => [...result]
      ..sort((a, b) => naturalCompare(b.name, a.name)),
    SortOption.sizeDesc => [...result]
      ..sort((a, b) => b.size.compareTo(a.size)),
    SortOption.sizeAsc => [...result]..sort((a, b) => a.size.compareTo(b.size)),
    SortOption.albumAZ => [...result]
      ..sort((a, b) {
        final c = naturalCompare(a.albumName, b.albumName);
        return c != 0 ? c : naturalCompare(a.name, b.name);
      }),
    SortOption.albumZA => [...result]
      ..sort((a, b) {
        final c = naturalCompare(b.albumName, a.albumName);
        return c != 0 ? c : naturalCompare(a.name, b.name);
      }),
  };
}

/// Tracks the media ID currently visible in the full-screen photo/video viewer.
/// Gallery and Album screens listen to this to silently align their scroll viewports.
final activeViewerMediaIdProvider = StateProvider<String?>((ref) => null);
