import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/media_item.dart';
import '../enums/sort_option.dart';
import '../enums/filter_option.dart';
import '../services/media_scanner_service.dart';
import 'settings_provider.dart';

/// Singleton scanner – no analytics, no network, 100% local.
final mediaScannerProvider = Provider<MediaScannerService>(
  (_) => MediaScannerService(),
);

/// Raw scanned media list state.
class MediaListNotifier extends AsyncNotifier<List<MediaItem>> {
  final Set<String> _deletedIds = {};

  @override
  Future<List<MediaItem>> build() async {
    final settings = ref.watch(settingsNotifierProvider);
    final scanner  = ref.read(mediaScannerProvider);
    final items = await scanner.scanAll(excludedFolders: settings.excludedFolders);
    if (_deletedIds.isEmpty) return items;
    return items.where((e) => !_deletedIds.contains(e.id)).toList();
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

  /// Refreshes from disk without blanking the UI with a full loading spinner.
  Future<void> refresh() async {
    final updated = await AsyncValue.guard(() async {
      final settings = ref.read(settingsNotifierProvider);
      final items = await ref.read(mediaScannerProvider).scanAll(
            excludedFolders: settings.excludedFolders,
          );
      return _deletedIds.isEmpty
          ? items
          : items.where((e) => !_deletedIds.contains(e.id)).toList();
    });
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
