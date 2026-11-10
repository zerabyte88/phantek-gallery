import 'package:equatable/equatable.dart';
import '../enums/sort_option.dart';
import '../enums/filter_option.dart';
import '../enums/thumbnail_crop_style.dart';
import '../enums/timeline_grouping.dart';
import '../enums/trash_cleanup_interval.dart';
import '../enums/startup_screen.dart';
import '../enums/video_double_tap_action.dart';
import '../localization/app_language.dart';
import '../services/translation/translation_models.dart';

/// Application-wide user preferences – stored locally via SettingsService.
class SettingsModel extends Equatable {
  const SettingsModel({
    this.themeMode = AppThemeMode.system,
    this.language = AppLanguage.en,
    this.gridColumns = 3,
    this.albumGridColumns = 3,
    this.showBadges = true,
    this.enableTrash = true,
    this.hardwareAcceleration = true,
    this.autoPlayVideo = false,
    this.keepScreenOn = false,
    this.excludedFolders = const [],
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
    this.videoDoubleTapAction = VideoDoubleTapAction.smart,
    this.resumeVideoPlayback = false,
    this.filterSmallImages = false,
    this.showHiddenFiles = false,
    this.secureScreen = false,
    this.activeAiModelPath = '',
    this.translationEngineType = TranslationEngineType.googleMlKit,
    this.translationSourceLanguage = TranslationSourceLanguage.japanese,
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

  /// Use Android hardware-accelerated video decoding.
  final bool hardwareAcceleration;

  /// Auto-play first video when entering the player.
  final bool autoPlayVideo;

  /// List of folder paths to exclude from the gallery scan.
  final List<String> excludedFolders;

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

  /// Behavior of double-tapping the video player (smart, seekOnly, zoomOnly).
  final VideoDoubleTapAction videoDoubleTapAction;

  /// Remember and resume playback position for videos.
  final bool resumeVideoPlayback;

  /// Filter out small/junk media files (< 50 KB).
  final bool filterSmallImages;

  /// Show hidden folders and files (.nomedia / dotfiles).
  final bool showHiddenFiles;

  /// Prevent screenshots and hide app previews in recent tasks (FLAG_SECURE).
  final bool secureScreen;

  /// Active offline GGUF LLM model file path for manga translation (empty for default auto-detect).
  final String activeAiModelPath;

  /// Active offline translation engine (Google ML Kit or Local GGUF LLM).
  final TranslationEngineType translationEngineType;

  /// Default source language for manga translation (Japanese, Chinese, Korean, Auto).
  final TranslationSourceLanguage translationSourceLanguage;

  Map<String, dynamic> toMap() => {
        'themeMode': themeMode.name,
        'language': language.name,
        'gridColumns': gridColumns,
        'albumGridColumns': albumGridColumns,
        'showBadges': showBadges,
        'keepScreenOn': keepScreenOn,
        'enableTrash': enableTrash,
        'hardwareAcceleration': hardwareAcceleration,
        'autoPlayVideo': autoPlayVideo,
        'excludedFolders': excludedFolders,
        'defaultSort': defaultSort.name,
        'defaultFilter': defaultFilter.name,
        'favoriteIds': favoriteIds,
        'thumbnailCropStyle': thumbnailCropStyle.name,
        'timelineGrouping': timelineGrouping.name,
        'startupScreen': startupScreen.name,
        'autoTrashCleanup': autoTrashCleanup.name,
        'maxBrightnessOnMedia': maxBrightnessOnMedia,
        'slideshowInterval': slideshowInterval,
        'startMuted': startMuted,
        'doubleTapSeekInterval': doubleTapSeekInterval,
        'videoDoubleTapAction': videoDoubleTapAction.name,
        'resumeVideoPlayback': resumeVideoPlayback,
        'filterSmallImages': filterSmallImages,
        'showHiddenFiles': showHiddenFiles,
        'secureScreen': secureScreen,
        'activeAiModelPath': activeAiModelPath,
        'translationEngineType': translationEngineType.name,
        'translationSourceLanguage': translationSourceLanguage.name,
      };

  Map<String, dynamic> toJson() => toMap();

  factory SettingsModel.fromJson(Map<String, dynamic> json) =>
      SettingsModel.fromMap(json);

  factory SettingsModel.fromMap(Map<String, dynamic> map) {
    return SettingsModel(
      themeMode: AppThemeMode.values.firstWhere(
        (e) => e.name == map['themeMode'],
        orElse: () => AppThemeMode.system,
      ),
      language: AppLanguage.values.firstWhere(
        (e) => e.name == map['language'],
        orElse: () => AppLanguage.en,
      ),
      gridColumns: map['gridColumns'] as int? ?? 3,
      albumGridColumns: map['albumGridColumns'] as int? ?? 3,
      showBadges: map['showBadges'] as bool? ?? true,
      keepScreenOn: map['keepScreenOn'] as bool? ?? false,
      enableTrash: map['enableTrash'] as bool? ?? true,
      hardwareAcceleration: map['hardwareAcceleration'] as bool? ?? true,
      autoPlayVideo: map['autoPlayVideo'] as bool? ?? false,
      excludedFolders:
          (map['excludedFolders'] as List?)?.cast<String>() ?? const [],
      defaultSort: SortOption.values.firstWhere(
        (e) => e.name == map['defaultSort'],
        orElse: () => SortOption.newest,
      ),
      defaultFilter: FilterOption.values.firstWhere(
        (e) => e.name == map['defaultFilter'],
        orElse: () => FilterOption.all,
      ),
      favoriteIds: (map['favoriteIds'] as List?)?.cast<String>() ?? const [],
      thumbnailCropStyle: ThumbnailCropStyle.values.firstWhere(
        (e) => e.name == map['thumbnailCropStyle'],
        orElse: () => ThumbnailCropStyle.square,
      ),
      timelineGrouping: TimelineGrouping.values.firstWhere(
        (e) => e.name == map['timelineGrouping'],
        orElse: () => TimelineGrouping.daily,
      ),
      startupScreen: StartupScreen.values.firstWhere(
        (e) => e.name == map['startupScreen'],
        orElse: () => StartupScreen.all,
      ),
      autoTrashCleanup: TrashCleanupInterval.values.firstWhere(
        (e) => e.name == map['autoTrashCleanup'],
        orElse: () => TrashCleanupInterval.never,
      ),
      maxBrightnessOnMedia: map['maxBrightnessOnMedia'] as bool? ?? false,
      slideshowInterval: map['slideshowInterval'] as int? ?? 3,
      startMuted: map['startMuted'] as bool? ?? false,
      doubleTapSeekInterval: map['doubleTapSeekInterval'] as int? ?? 10,
      videoDoubleTapAction: VideoDoubleTapAction.values.firstWhere(
        (e) => e.name == map['videoDoubleTapAction'],
        orElse: () => VideoDoubleTapAction.smart,
      ),
      resumeVideoPlayback: map['resumeVideoPlayback'] as bool? ?? false,
      filterSmallImages: map['filterSmallImages'] as bool? ?? false,
      showHiddenFiles: map['showHiddenFiles'] as bool? ?? false,
      secureScreen: map['secureScreen'] as bool? ?? false,
      activeAiModelPath: map['activeAiModelPath'] as String? ?? '',
      translationEngineType: TranslationEngineType.values.firstWhere(
        (e) => e.name == map['translationEngineType'],
        orElse: () => TranslationEngineType.googleMlKit,
      ),
      translationSourceLanguage: TranslationSourceLanguage.values.firstWhere(
        (e) => e.name == map['translationSourceLanguage'],
        orElse: () => TranslationSourceLanguage.japanese,
      ),
    );
  }

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
    VideoDoubleTapAction? videoDoubleTapAction,
    bool? resumeVideoPlayback,
    bool? filterSmallImages,
    bool? showHiddenFiles,
    bool? secureScreen,
    String? activeAiModelPath,
    TranslationEngineType? translationEngineType,
    TranslationSourceLanguage? translationSourceLanguage,
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
      videoDoubleTapAction: videoDoubleTapAction ?? this.videoDoubleTapAction,
      resumeVideoPlayback: resumeVideoPlayback ?? this.resumeVideoPlayback,
      filterSmallImages: filterSmallImages ?? this.filterSmallImages,
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      secureScreen: secureScreen ?? this.secureScreen,
      activeAiModelPath: activeAiModelPath ?? this.activeAiModelPath,
      translationEngineType:
          translationEngineType ?? this.translationEngineType,
      translationSourceLanguage:
          translationSourceLanguage ?? this.translationSourceLanguage,
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
        videoDoubleTapAction,
        resumeVideoPlayback,
        filterSmallImages,
        showHiddenFiles,
        secureScreen,
        activeAiModelPath,
        translationEngineType,
        translationSourceLanguage,
      ];
}

enum AppThemeMode {
  system,
  light,
  cleanLight,
  amoledSnowfall,
  amoledMidnight,
  amoledPure,
  amoledSakura,
}

extension AppThemeModeLabel on AppThemeMode {
  String get label => switch (this) {
        AppThemeMode.system => 'System',
        AppThemeMode.light => 'Sunlight',
        AppThemeMode.cleanLight => 'Light Mode',
        AppThemeMode.amoledSnowfall => 'Snowfall',
        AppThemeMode.amoledMidnight => 'Midnight',
        AppThemeMode.amoledPure => 'Dark Mode',
        AppThemeMode.amoledSakura => 'Sakura',
      };
}
