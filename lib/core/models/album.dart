import 'package:equatable/equatable.dart';
import '../enums/sort_option.dart';
import 'media_item.dart';

/// Represents a media album (folder) containing photos and videos.
class Album extends Equatable {
  const Album({
    required this.name,
    required this.items,
    required this.coverItem,
  });

  /// Name of the album / folder (e.g. "DCIM", "Facebook", "Download").
  final String name;

  /// All media items in this album.
  final List<MediaItem> items;

  /// Primary representative item used as the album cover.
  final MediaItem coverItem;

  /// Total count of items in this album.
  int get itemCount => items.length;

  @override
  List<Object?> get props => [name, items, coverItem];
}

/// Groups a list of [MediaItem]s into [Album]s based on their folder names,
/// applying optional sorting.
List<Album> groupMediaIntoAlbums(List<MediaItem> items, {SortOption? sort}) {
  final Map<String, List<MediaItem>> grouped = {};
  for (final item in items) {
    grouped.putIfAbsent(item.albumName, () => []).add(item);
  }

  final albums = grouped.entries.map((entry) {
    final albumItems = entry.value;
    final sortedByDate = [...albumItems]..sort((a, b) => b.date.compareTo(a.date));
    return Album(
      name: entry.key,
      items: albumItems,
      coverItem: sortedByDate.first,
    );
  }).toList();

  if (sort != null) {
    switch (sort) {
      case SortOption.newest:
        albums.sort((a, b) => b.coverItem.date.compareTo(a.coverItem.date));
      case SortOption.oldest:
        albums.sort((a, b) => a.coverItem.date.compareTo(b.coverItem.date));
      case SortOption.nameAZ:
        albums.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case SortOption.nameZA:
        albums.sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
    }
  } else {
    albums.sort((a, b) => b.coverItem.date.compareTo(a.coverItem.date));
  }

  return albums;
}
