import 'package:flutter/material.dart';
import '../localization/app_localizations.dart';

/// Defines available media-type filters for the gallery grid.
enum FilterOption {
  /// Show all media (photos + videos).
  all,

  /// Show only photos.
  photosOnly,

  /// Show only videos.
  videosOnly,

  /// Show media grouped by albums.
  albums,
}

extension FilterOptionLabel on FilterOption {
  String get label => switch (this) {
        FilterOption.all         => 'All',
        FilterOption.photosOnly  => 'Photos',
        FilterOption.videosOnly  => 'Videos',
        FilterOption.albums      => 'Albums',
      };

  String localizedLabel(BuildContext context) => switch (this) {
        FilterOption.all         => context.tr.all,
        FilterOption.photosOnly  => context.tr.photos,
        FilterOption.videosOnly  => context.tr.videos,
        FilterOption.albums      => context.tr.albums,
      };
}
