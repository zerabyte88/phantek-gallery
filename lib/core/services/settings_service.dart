import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/settings_model.dart';
import '../enums/sort_option.dart';
import '../enums/filter_option.dart';

/// Keys used in SharedPreferences.
class _K {
  static const themeMode          = 'themeMode';
  static const gridColumns        = 'gridColumns';
  static const showBadges         = 'showBadges';
  static const enableTrash        = 'enableTrash';
  static const hardwareAccel      = 'hardwareAcceleration';
  static const autoPlayVideo      = 'autoPlayVideo';
  static const excludedFolders    = 'excludedFolders';
  static const autoCheckUpdate    = 'autoCheckUpdate';
  static const defaultSort        = 'defaultSort';
  static const defaultFilter      = 'defaultFilter';
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

  SettingsModel get settings => SettingsModel(
        themeMode:           _readEnum(_K.themeMode, AppThemeMode.values, AppThemeMode.system),
        gridColumns:         _prefs.getInt(_K.gridColumns) ?? 3,
        showBadges:          _prefs.getBool(_K.showBadges) ?? true,
        enableTrash:         _prefs.getBool(_K.enableTrash) ?? true,
        hardwareAcceleration: _prefs.getBool(_K.hardwareAccel) ?? true,
        autoPlayVideo:       _prefs.getBool(_K.autoPlayVideo) ?? false,
        excludedFolders:     _readStringList(_K.excludedFolders),
        autoCheckUpdate:     _prefs.getBool(_K.autoCheckUpdate) ?? true,
        defaultSort:         _readEnum(_K.defaultSort, SortOption.values, SortOption.newest),
        defaultFilter:       _readEnum(_K.defaultFilter, FilterOption.values, FilterOption.all),
      );

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<void> save(SettingsModel model) async {
    await Future.wait([
      _prefs.setString(_K.themeMode,       model.themeMode.name),
      _prefs.setInt   (_K.gridColumns,     model.gridColumns),
      _prefs.setBool  (_K.showBadges,      model.showBadges),
      _prefs.setBool  (_K.enableTrash,     model.enableTrash),
      _prefs.setBool  (_K.hardwareAccel,   model.hardwareAcceleration),
      _prefs.setBool  (_K.autoPlayVideo,   model.autoPlayVideo),
      _prefs.setString(_K.excludedFolders, jsonEncode(model.excludedFolders)),
      _prefs.setBool  (_K.autoCheckUpdate, model.autoCheckUpdate),
      _prefs.setString(_K.defaultSort,     model.defaultSort.name),
      _prefs.setString(_K.defaultFilter,   model.defaultFilter.name),
    ]);
  }

  Future<void> reset() => save(const SettingsModel());

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
