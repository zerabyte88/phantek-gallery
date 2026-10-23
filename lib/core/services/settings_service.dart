import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/settings_model.dart';
import '../enums/sort_option.dart';
import '../enums/filter_option.dart';
import '../enums/thumbnail_crop_style.dart';
import '../enums/timeline_grouping.dart';
import '../enums/trash_cleanup_interval.dart';
import '../enums/startup_screen.dart';
import '../enums/video_double_tap_action.dart';
import '../localization/app_language.dart';

/// Keys used in SharedPreferences.
class _K {
  static const themeMode = 'themeMode';
  static const language = 'language';
  static const gridColumns = 'gridColumns';
  static const albumGridColumns = 'albumGridColumns';
  static const showBadges = 'showBadges';
  static const enableTrash = 'enableTrash';
  static const hardwareAccel = 'hardwareAcceleration';
  static const autoPlayVideo = 'autoPlayVideo';
  static const keepScreenOn = 'keepScreenOn';
  static const excludedFolders = 'excludedFolders';
  static const autoCheckUpdate = 'autoCheckUpdate';
  static const defaultSort = 'defaultSort';
  static const defaultFilter = 'defaultFilter';
  static const favoriteIds = 'favoriteIds';
  static const thumbnailCropStyle = 'thumbnailCropStyle';
  static const timelineGrouping = 'timelineGrouping';
  static const startupScreen = 'startupScreen';
  static const autoTrashCleanup = 'autoTrashCleanup';
  static const maxBrightnessOnMedia = 'maxBrightnessOnMedia';
  static const slideshowInterval = 'slideshowInterval';
  static const startMuted = 'startMuted';
  static const doubleTapSeekInterval = 'doubleTapSeekInterval';
  static const videoDoubleTapAction = 'videoDoubleTapAction';
  static const resumeVideoPlayback = 'resumeVideoPlayback';
  static const filterSmallImages = 'filterSmallImages';
  static const showHiddenFiles = 'showHiddenFiles';
  static const secureScreen = 'secureScreen';
}

/// Thin wrapper around SharedPreferences for typed settings access.
///
/// Initialise once with [SettingsService.init()] before using.
class SettingsService {
  SettingsService._(this._prefs);

  static SettingsService? _instance;
  static SettingsService get instance {
    assert(_instance != null, 'Call SettingsService.init() first');
    return _instance!;
  }

  final SharedPreferences _prefs;

  static Future<SettingsService> init() async {
    final prefs = await SharedPreferences.getInstance();
    _instance = SettingsService._(prefs);
    return _instance!;
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  SettingsModel get settings {
    final rawTheme = _prefs.getString(_K.themeMode);
    final themeMode = switch (rawTheme) {
      'dark' => AppThemeMode.amoledSnowfall,
      'amoled' => AppThemeMode.amoledMidnight,
      _ => _readEnum(_K.themeMode, AppThemeMode.values, AppThemeMode.system),
    };
    return SettingsModel(
      themeMode: themeMode,
      language:
          _readEnum(_K.language, AppLanguage.values, AppLanguage.system),
        gridColumns: _prefs.getInt(_K.gridColumns) ?? 3,
        albumGridColumns: _prefs.getInt(_K.albumGridColumns) ?? 3,
        showBadges: _prefs.getBool(_K.showBadges) ?? true,
        keepScreenOn: _prefs.getBool(_K.keepScreenOn) ?? false,
        enableTrash: _prefs.getBool(_K.enableTrash) ?? true,
        hardwareAcceleration: _prefs.getBool(_K.hardwareAccel) ?? true,
        autoPlayVideo: _prefs.getBool(_K.autoPlayVideo) ?? false,
        excludedFolders: _readStringList(_K.excludedFolders),
        autoCheckUpdate: _prefs.getBool(_K.autoCheckUpdate) ?? true,
        defaultSort:
            _readEnum(_K.defaultSort, SortOption.values, SortOption.newest),
        defaultFilter:
            _readEnum(_K.defaultFilter, FilterOption.values, FilterOption.all),
        favoriteIds: _readStringList(_K.favoriteIds),
        thumbnailCropStyle: _readEnum(_K.thumbnailCropStyle,
            ThumbnailCropStyle.values, ThumbnailCropStyle.square),
        timelineGrouping: _readEnum(_K.timelineGrouping,
            TimelineGrouping.values, TimelineGrouping.daily),
        startupScreen: _readEnum(
            _K.startupScreen, StartupScreen.values, StartupScreen.all),
        autoTrashCleanup: _readEnum(_K.autoTrashCleanup,
            TrashCleanupInterval.values, TrashCleanupInterval.never),
        maxBrightnessOnMedia: _prefs.getBool(_K.maxBrightnessOnMedia) ?? false,
        slideshowInterval: _prefs.getInt(_K.slideshowInterval) ?? 3,
        startMuted: _prefs.getBool(_K.startMuted) ?? false,
        doubleTapSeekInterval: _prefs.getInt(_K.doubleTapSeekInterval) ?? 10,
        videoDoubleTapAction: _readEnum(_K.videoDoubleTapAction,
            VideoDoubleTapAction.values, VideoDoubleTapAction.smart),
        resumeVideoPlayback: _prefs.getBool(_K.resumeVideoPlayback) ?? false,
        filterSmallImages: _prefs.getBool(_K.filterSmallImages) ?? false,
        showHiddenFiles: _prefs.getBool(_K.showHiddenFiles) ?? false,
        secureScreen: _prefs.getBool(_K.secureScreen) ?? false,
      );
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<void> save(SettingsModel model) async {
    await Future.wait([
      _prefs.setString(_K.themeMode, model.themeMode.name),
      _prefs.setString(_K.language, model.language.name),
      _prefs.setInt(_K.gridColumns, model.gridColumns),
      _prefs.setInt(_K.albumGridColumns, model.albumGridColumns),
      _prefs.setBool(_K.showBadges, model.showBadges),
      _prefs.setBool(_K.keepScreenOn, model.keepScreenOn),
      _prefs.setBool(_K.enableTrash, model.enableTrash),
      _prefs.setBool(_K.hardwareAccel, model.hardwareAcceleration),
      _prefs.setBool(_K.autoPlayVideo, model.autoPlayVideo),
      _prefs.setString(_K.excludedFolders, jsonEncode(model.excludedFolders)),
      _prefs.setBool(_K.autoCheckUpdate, model.autoCheckUpdate),
      _prefs.setString(_K.defaultSort, model.defaultSort.name),
      _prefs.setString(_K.defaultFilter, model.defaultFilter.name),
      _prefs.setString(_K.favoriteIds, jsonEncode(model.favoriteIds)),
      _prefs.setString(_K.thumbnailCropStyle, model.thumbnailCropStyle.name),
      _prefs.setString(_K.timelineGrouping, model.timelineGrouping.name),
      _prefs.setString(_K.startupScreen, model.startupScreen.name),
      _prefs.setString(_K.autoTrashCleanup, model.autoTrashCleanup.name),
      _prefs.setBool(_K.maxBrightnessOnMedia, model.maxBrightnessOnMedia),
      _prefs.setInt(_K.slideshowInterval, model.slideshowInterval),
      _prefs.setBool(_K.startMuted, model.startMuted),
      _prefs.setInt(_K.doubleTapSeekInterval, model.doubleTapSeekInterval),
      _prefs.setString(
          _K.videoDoubleTapAction, model.videoDoubleTapAction.name),
      _prefs.setBool(_K.resumeVideoPlayback, model.resumeVideoPlayback),
      _prefs.setBool(_K.filterSmallImages, model.filterSmallImages),
      _prefs.setBool(_K.showHiddenFiles, model.showHiddenFiles),
      _prefs.setBool(_K.secureScreen, model.secureScreen),
    ]);
  }

  Future<void> reset() => save(const SettingsModel());

  // ── Video Resume Position ──────────────────────────────────────────────────

  String _posKey(String path) {
    final normalized = path.replaceAll(r'\', '/');
    return 'playback_pos_${base64Url.encode(utf8.encode(normalized))}';
  }

  Duration? getVideoPlaybackPosition(String path) {
    if (!settings.resumeVideoPlayback) return null;
    final normalized = path.replaceAll(r'\', '/');
    final key = _posKey(normalized);
    final posMs = _prefs.getInt(key) ??
        _prefs.getInt('playback_pos_${normalized.hashCode}') ??
        _prefs.getInt('playback_pos_${path.hashCode}');
    if (posMs != null && posMs > 2000) {
      return Duration(milliseconds: posMs);
    }
    return null;
  }

  void saveVideoPlaybackPosition(
      String path, Duration position, Duration duration) {
    if (!settings.resumeVideoPlayback) return;
    final posMs = position.inMilliseconds;
    if (posMs <= 0) return;
    final normalized = path.replaceAll(r'\', '/');
    final key = _posKey(normalized);
    final legacyKey = 'playback_pos_${normalized.hashCode}';
    final rawLegacyKey = 'playback_pos_${path.hashCode}';
    final durMs = duration.inMilliseconds;
    if (durMs > 0 && durMs - posMs < 3000) {
      _prefs.remove(key);
      _prefs.remove(legacyKey);
      _prefs.remove(rawLegacyKey);
    } else if (posMs > 2000) {
      _prefs.setInt(key, posMs);
    } else if (posMs > 0 && posMs <= 2000) {
      _prefs.remove(key);
      _prefs.remove(legacyKey);
      _prefs.remove(rawLegacyKey);
    }
  }

  void clearVideoPlaybackPosition(String path) {
    final normalized = path.replaceAll(r'\', '/');
    _prefs.remove(_posKey(normalized));
    _prefs.remove('playback_pos_${normalized.hashCode}');
    _prefs.remove('playback_pos_${path.hashCode}');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  T _readEnum<T extends Enum>(String key, List<T> values, T fallback) {
    final name = _prefs.getString(key);
    if (name == null) return fallback;
    return values.firstWhere((e) => e.name == name, orElse: () => fallback);
  }

  List<String> _readStringList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return const [];
    try {
      return List<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      return const [];
    }
  }
}
