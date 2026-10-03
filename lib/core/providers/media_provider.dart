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
  @override
  Future<List<MediaItem>> build() async {
    final settings = ref.watch(settingsNotifierProvider);
    final scanner  = ref.read(mediaScannerProvider);
    return scanner.scanAll(excludedFolders: settings.excludedFolders);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final settings = ref.read(settingsNotifierProvider);
      return ref.read(mediaScannerProvider).scanAll(
            excludedFolders: settings.excludedFolders,
          );
    });
  }
}

final mediaListProvider =
    AsyncNotifierProvider<MediaListNotifier, List<MediaItem>>(MediaListNotifier.new);

/// Derived provider: applies sort + filter on top of [mediaListProvider].
final filteredMediaProvider = Provider<AsyncValue<List<MediaItem>>>((ref) {
  final raw      = ref.watch(mediaListProvider);
  final settings = ref.watch(settingsNotifierProvider);
  return raw.whenData((items) => _applyFiltersAndSort(
        items,
        sort:   settings.defaultSort,
        filter: settings.defaultFilter,
      ));
});

List<MediaItem> _applyFiltersAndSort(
  List<MediaItem> items, {
  required SortOption sort,
  required FilterOption filter,
}) {
  var result = switch (filter) {
    FilterOption.all        => items,
    FilterOption.photosOnly => items.where((e) => !e.isVideo).toList(),
    FilterOption.videosOnly => items.where((e) => e.isVideo).toList(),
  };

  return switch (sort) {
    SortOption.newest => [...result]..sort((a, b) => b.date.compareTo(a.date)),
    SortOption.oldest => [...result]..sort((a, b) => a.date.compareTo(b.date)),
    SortOption.nameAZ => [...result]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    SortOption.nameZA => [...result]
        ..sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase())),
  };
}
