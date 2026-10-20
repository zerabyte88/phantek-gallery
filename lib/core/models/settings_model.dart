import 'package:equatable/equatable.dart';
import '../enums/sort_option.dart';
import '../enums/filter_option.dart';
import '../enums/thumbnail_crop_style.dart';
import '../enums/timeline_grouping.dart';
import '../enums/trash_cleanup_interval.dart';
import '../enums/startup_screen.dart';
import '../localization/app_language.dart';

/// Application-wide user preferences – stored locally via SettingsService.
class SettingsModel extends Equatable {
  const SettingsModel({
    this.themeMode = AppThemeMode.system,
    this.language = AppLanguage.system,
    this.gridColumns = 3,
    this.albumGridColumns = 3,
    this.showBadges = true,
    this.enableTrash = true,
    this.hardwareAcceleration = true,
    this.autoPlayVideo = false,
    this.keepScreenOn = false,
    this.excludedFolders = const [],
    this.autoCheckUpdate = true,
    this.defaultSort = SortOption.newest,
    this.defaultFilter = FilterOption.all,
    this.favoriteIds = const [],
    this.thumbnailCropStyle = ThumbnailCropStyle.square,
    this.timelineGrouping = TimelineGrouping.daily,
    this.startupScreen = StartupScreen.all,
    this.autoTrashCleanup = TrashCleanupInterval.never,
    this.maxBrightnessOnMedia = false,
    this.slideshowInterval = 3,
    this.startMuted = false,
    this.doubleTapSeekInterval = 10,
    this.resumeVideoPlayback = false,
    this.filterSmallImages = false,
    this.showHiddenFiles = false,
    this.secureScreen = false,
    this.lockedVaultEnabled = false,
  });

  final AppThemeMode themeMode;
  final AppLanguage language;

  /// Number of grid columns in the gallery view (2–5).
  final int gridColumns;

  /// Number of grid columns in the albums view (2–5).
  final int albumGridColumns;

  /// Show video/photo count badges on album thumbnails.
  final bool showBadges;

  /// Keep the screen on while viewing photos or videos.
  final bool keepScreenOn;

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

  /// IDs of media items marked as favorites.
  final List<String> favoriteIds;

  /// Thumbnail crop behavior: square crop or adaptive original aspect ratio.
  final ThumbnailCropStyle thumbnailCropStyle;

  /// Timeline header grouping: continuous flat list, grouped by day, or by month.
  final TimelineGrouping timelineGrouping;

  /// Initial tab selected on application startup.
  final StartupScreen startupScreen;

  /// Automatic purge interval for Recycle Bin items.
  final TrashCleanupInterval autoTrashCleanup;

  /// Automatically boost screen brightness to maximum when viewing photos or videos.
  final bool maxBrightnessOnMedia;

  /// Time interval in seconds between automated slideshow page advances.
  final int slideshowInterval;

  /// Start video playback muted by default.
  final bool startMuted;

  /// Skip interval in seconds when double-tapping player left/right edges (5, 10, 15).
  final int doubleTapSeekInterval;

  /// Remember and resume playback position for videos.
  final bool resumeVideoPlayback;

  /// Filter out small/junk media files (< 50 KB).
  final bool filterSmallImages;

  /// Show hidden folders and files (.nomedia / dotfiles).
  final bool showHiddenFiles;

  /// Prevent screenshots and hide app previews in recent tasks (FLAG_SECURE).
  final bool secureScreen;

  /// Enable PIN / biometric protection for locked vault.
  final bool lockedVaultEnabled;

  SettingsModel copyWith({
    AppThemeMode? themeMode,
    AppLanguage? language,
    int? gridColumns,
    int? albumGridColumns,
    bool? showBadges,
    bool? keepScreenOn,
    bool? enableTrash,
    bool? hardwareAcceleration,
    bool? autoPlayVideo,
    List<String>? excludedFolders,
    bool? autoCheckUpdate,
    SortOption? defaultSort,
    FilterOption? defaultFilter,
    List<String>? favoriteIds,
    ThumbnailCropStyle? thumbnailCropStyle,
    TimelineGrouping? timelineGrouping,
    StartupScreen? startupScreen,
    TrashCleanupInterval? autoTrashCleanup,
    bool? maxBrightnessOnMedia,
    int? slideshowInterval,
    bool? startMuted,
    int? doubleTapSeekInterval,
    bool? resumeVideoPlayback,
    bool? filterSmallImages,
    bool? showHiddenFiles,
    bool? secureScreen,
    bool? lockedVaultEnabled,
  }) {
    return SettingsModel(
      themeMode: themeMode ?? this.themeMode,
      language: language ?? this.language,
      gridColumns: gridColumns ?? this.gridColumns,
      albumGridColumns: albumGridColumns ?? this.albumGridColumns,
      showBadges: showBadges ?? this.showBadges,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      enableTrash: enableTrash ?? this.enableTrash,
      hardwareAcceleration: hardwareAcceleration ?? this.hardwareAcceleration,
      autoPlayVideo: autoPlayVideo ?? this.autoPlayVideo,
      excludedFolders: excludedFolders ?? this.excludedFolders,
      autoCheckUpdate: autoCheckUpdate ?? this.autoCheckUpdate,
      defaultSort: defaultSort ?? this.defaultSort,
      defaultFilter: defaultFilter ?? this.defaultFilter,
      favoriteIds: favoriteIds ?? this.favoriteIds,
      thumbnailCropStyle: thumbnailCropStyle ?? this.thumbnailCropStyle,
      timelineGrouping: timelineGrouping ?? this.timelineGrouping,
      startupScreen: startupScreen ?? this.startupScreen,
      autoTrashCleanup: autoTrashCleanup ?? this.autoTrashCleanup,
      maxBrightnessOnMedia: maxBrightnessOnMedia ?? this.maxBrightnessOnMedia,
      slideshowInterval: slideshowInterval ?? this.slideshowInterval,
      startMuted: startMuted ?? this.startMuted,
      doubleTapSeekInterval:
          doubleTapSeekInterval ?? this.doubleTapSeekInterval,
      resumeVideoPlayback: resumeVideoPlayback ?? this.resumeVideoPlayback,
      filterSmallImages: filterSmallImages ?? this.filterSmallImages,
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      secureScreen: secureScreen ?? this.secureScreen,
      lockedVaultEnabled: lockedVaultEnabled ?? this.lockedVaultEnabled,
    );
  }

  @override
  List<Object?> get props => [
        themeMode,
        language,
        gridColumns,
        albumGridColumns,
        showBadges,
        keepScreenOn,
        enableTrash,
        hardwareAcceleration,
        autoPlayVideo,
        excludedFolders,
        autoCheckUpdate,
        defaultSort,
        defaultFilter,
        favoriteIds,
        thumbnailCropStyle,
        timelineGrouping,
        startupScreen,
        autoTrashCleanup,
        maxBrightnessOnMedia,
        slideshowInterval,
        startMuted,
        doubleTapSeekInterval,
        resumeVideoPlayback,
        filterSmallImages,
        showHiddenFiles,
        secureScreen,
        lockedVaultEnabled,
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
        AppThemeMode.system => 'System',
        AppThemeMode.light => 'Sunburst',
        AppThemeMode.dark => 'Snowfall',
        AppThemeMode.amoled => 'Midnight',
        AppThemeMode.amoledSakura => 'Sakura',
      };
}
