import 'package:equatable/equatable.dart';
import '../enums/sort_option.dart';
import '../enums/filter_option.dart';

/// Application-wide user preferences – stored locally via SettingsService.
class SettingsModel extends Equatable {
  const SettingsModel({
    this.themeMode = AppThemeMode.system,
    this.gridColumns = 3,
    this.albumGridColumns = 3,
    this.showBadges = true,
    this.enableTrash = true,
    this.hardwareAcceleration = true,
    this.autoPlayVideo = false,
    this.excludedFolders = const [],
    this.autoCheckUpdate = true,
    this.defaultSort = SortOption.newest,
    this.defaultFilter = FilterOption.all,
    this.isSakuraUnlocked = false,
    this.favoriteIds = const [],
  });

  final AppThemeMode themeMode;

  /// Number of grid columns in the gallery view (2–5).
  final int gridColumns;

  /// Number of grid columns in the albums view (2–5).
  final int albumGridColumns;

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

  /// Easter Egg: whether AMOLED Sakura theme has been unlocked.
  final bool isSakuraUnlocked;

  /// IDs of media items marked as favorites.
  final List<String> favoriteIds;

  SettingsModel copyWith({
    AppThemeMode? themeMode,
    int? gridColumns,
    int? albumGridColumns,
    bool? showBadges,
    bool? enableTrash,
    bool? hardwareAcceleration,
    bool? autoPlayVideo,
    List<String>? excludedFolders,
    bool? autoCheckUpdate,
    SortOption? defaultSort,
    FilterOption? defaultFilter,
    bool? isSakuraUnlocked,
    List<String>? favoriteIds,
  }) {
    return SettingsModel(
      themeMode: themeMode ?? this.themeMode,
      gridColumns: gridColumns ?? this.gridColumns,
      albumGridColumns: albumGridColumns ?? this.albumGridColumns,
      showBadges: showBadges ?? this.showBadges,
      enableTrash: enableTrash ?? this.enableTrash,
      hardwareAcceleration: hardwareAcceleration ?? this.hardwareAcceleration,
      autoPlayVideo: autoPlayVideo ?? this.autoPlayVideo,
      excludedFolders: excludedFolders ?? this.excludedFolders,
      autoCheckUpdate: autoCheckUpdate ?? this.autoCheckUpdate,
      defaultSort: defaultSort ?? this.defaultSort,
      defaultFilter: defaultFilter ?? this.defaultFilter,
      isSakuraUnlocked: isSakuraUnlocked ?? this.isSakuraUnlocked,
      favoriteIds: favoriteIds ?? this.favoriteIds,
    );
  }

  @override
  List<Object?> get props => [
        themeMode,
        gridColumns,
        albumGridColumns,
        showBadges,
        enableTrash,
        hardwareAcceleration,
        autoPlayVideo,
        excludedFolders,
        autoCheckUpdate,
        defaultSort,
        defaultFilter,
        isSakuraUnlocked,
        favoriteIds,
      ];
}

enum AppThemeMode {
  system,
  light,
  dark,
  amoled,
  amoledSakura,
}

extension AppThemeModeLabel on AppThemeMode {
  String get label => switch (this) {
        AppThemeMode.system       => 'System',
        AppThemeMode.light        => 'Light',
        AppThemeMode.dark         => 'Dark',
        AppThemeMode.amoled       => 'AMOLED',
        AppThemeMode.amoledSakura => 'AMOLED Sakura 🌸',
      };
}
