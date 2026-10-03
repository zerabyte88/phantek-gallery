import 'package:equatable/equatable.dart';
import '../enums/sort_option.dart';
import '../enums/filter_option.dart';

/// Application-wide user preferences – stored locally via SettingsService.
class SettingsModel extends Equatable {
  const SettingsModel({
    this.themeMode = AppThemeMode.system,
    this.gridColumns = 3,
    this.showBadges = true,
    this.enableTrash = true,
    this.hardwareAcceleration = true,
    this.autoPlayVideo = false,
    this.excludedFolders = const [],
    this.autoCheckUpdate = true,
    this.defaultSort = SortOption.newest,
    this.defaultFilter = FilterOption.all,
  });

  final AppThemeMode themeMode;

  /// Number of grid columns in the gallery view (2–5).
  final int gridColumns;

  /// Show video/photo count badges on album thumbnails.
  final bool showBadges;

  /// When true, deleting moves items to .trash instead of permanently deleting.
  final bool enableTrash;

  /// Use Android hardware-accelerated video decoding in media_kit.
  final bool hardwareAcceleration;

  /// Auto-play first video when entering the player.
  final bool autoPlayVideo;

  /// List of folder paths to exclude from the gallery scan.
  final List<String> excludedFolders;

  /// Automatically check GitHub Releases for updates on launch.
  final bool autoCheckUpdate;

  final SortOption defaultSort;
  final FilterOption defaultFilter;

  SettingsModel copyWith({
    AppThemeMode? themeMode,
    int? gridColumns,
    bool? showBadges,
    bool? enableTrash,
    bool? hardwareAcceleration,
    bool? autoPlayVideo,
    List<String>? excludedFolders,
    bool? autoCheckUpdate,
    SortOption? defaultSort,
    FilterOption? defaultFilter,
  }) {
    return SettingsModel(
      themeMode: themeMode ?? this.themeMode,
      gridColumns: gridColumns ?? this.gridColumns,
      showBadges: showBadges ?? this.showBadges,
      enableTrash: enableTrash ?? this.enableTrash,
      hardwareAcceleration: hardwareAcceleration ?? this.hardwareAcceleration,
      autoPlayVideo: autoPlayVideo ?? this.autoPlayVideo,
      excludedFolders: excludedFolders ?? this.excludedFolders,
      autoCheckUpdate: autoCheckUpdate ?? this.autoCheckUpdate,
      defaultSort: defaultSort ?? this.defaultSort,
      defaultFilter: defaultFilter ?? this.defaultFilter,
    );
  }

  @override
  List<Object?> get props => [
        themeMode,
        gridColumns,
        showBadges,
        enableTrash,
        hardwareAcceleration,
        autoPlayVideo,
        excludedFolders,
        autoCheckUpdate,
        defaultSort,
        defaultFilter,
      ];
}

enum AppThemeMode { light, dark, system }
