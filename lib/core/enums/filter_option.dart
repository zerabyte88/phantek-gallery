/// Defines available media-type filters for the gallery grid.
enum FilterOption {
  /// Show all media (photos + videos).
  all,

  /// Show only photos.
  photosOnly,

  /// Show only videos.
  videosOnly,
}

extension FilterOptionLabel on FilterOption {
  String get label => switch (this) {
        FilterOption.all         => 'All',
        FilterOption.photosOnly  => 'Photos',
        FilterOption.videosOnly  => 'Videos',
      };
}
