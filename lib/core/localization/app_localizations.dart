import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/settings_model.dart';
import 'translations/translations.dart';

/// Lightweight, type-safe localization dictionary for Phantek Gallery.
class AppLocalizations {
  final Locale locale;
  final Map<String, String> _dict;

  AppLocalizations(this.locale) : _dict = getTranslationMap(_resolveLang(locale));

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('en'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static String _resolveLang(Locale locale) {
    if (locale.languageCode == 'zh_TW' || locale.languageCode == 'zh_tw') {
      return 'zh_TW';
    }
    if (locale.languageCode == 'zh') {
      if (locale.countryCode?.toUpperCase() == 'TW' ||
          locale.scriptCode?.toLowerCase() == 'hant') {
        return 'zh_TW';
      }
      return 'zh';
    }
    return locale.languageCode;
  }

  /// Resolved language code (e.g. 'en', 'id', 'zh_TW').
  String get languageCode => _resolveLang(locale);

  String _t(String key) => _dict[key] ?? enTranslations[key] ?? key;

  // ── Getters ─────────────────────────────────────────────────────────────
  String get all => _t('all');
  String get photos => _t('photos');
  String get videos => _t('videos');
  String get albums => _t('albums');
  String get favorites => _t('favorites');
  String get searchHint => _t('searchHint');
  String get noMediaFound => _t('noMediaFound');
  String get selected => _t('selected');
  String get settings => _t('settings');
  String get appearance => _t('appearance');
  String get theme => _t('theme');
  String get language => _t('language');
  String get chooseLanguage => _t('chooseLanguage');
  String get gridColumns => _t('gridColumns');
  String get albumsGridColumns => _t('albumsGridColumns');
  String get showDurationBadges => _t('showDurationBadges');
  String get showDurationBadgesSubtitle => _t('showDurationBadgesSubtitle');
  String get cache => _t('cache');
  String get clearThumbnailCache => _t('clearThumbnailCache');
  String get playback => _t('playback');
  String get hardwareAcceleration => _t('hardwareAcceleration');
  String get hardwareAccelerationSubtitle => _t('hardwareAccelerationSubtitle');
  String get autoPlayVideo => _t('autoPlayVideo');
  String get autoPlayVideoSubtitle => _t('autoPlayVideoSubtitle');
  String get storage => _t('storage');
  String get storageAndCache => _t('storageAndCache');
  String get trashBin => _t('trashBin');
  String get trashBinSubtitle => _t('trashBinSubtitle');
  String get excludedFolders => _t('excludedFolders');
  String get excludedFoldersDescription => _t('excludedFoldersDescription');
  String get none => _t('none');
  String get allFilesAccess => _t('allFilesAccess');
  String get allFilesAccessSubtitle => _t('allFilesAccessSubtitle');
  String get updates => _t('updates');
  String get autoCheckUpdate => _t('autoCheckUpdate');
  String get checkUpdateNow => _t('checkUpdateNow');
  String get about => _t('about');
  String get resetAllSettings => _t('resetAllSettings');
  String get cancel => _t('cancel');
  String get save => _t('save');
  String get add => _t('add');
  String get delete => _t('delete');
  String get share => _t('share');
  String get pickFromManager => _t('pickFromManager');
  String get pickFromAlbums => _t('pickFromAlbums');
  String get manualPathEntry => _t('manualPathEntry');
  String get keepScreenOn => _t('keepScreenOn');
  String get keepScreenOnSubtitle => _t('keepScreenOnSubtitle');
  String get sort => _t('sort');
  String get restoreDefaults => _t('restoreDefaults');
  String get sortByShootingTime => _t('sortByShootingTime');
  String get sortByTimeAdded => _t('sortByTimeAdded');
  String get sortByName => _t('sortByName');
  String get sortBySize => _t('sortBySize');
  String get oldestToNewest => _t('oldestToNewest');
  String get newestToOldest => _t('newestToOldest');
  String get aToZ => _t('aToZ');
  String get zToA => _t('zToA');
  String get smallestToLargest => _t('smallestToLargest');
  String get largestToSmallest => _t('largestToSmallest');
  String get restore => _t('restore');
  String get details => _t('details');
  String get favorite => _t('favorite');
  String get more => _t('more');
  String get play => _t('play');
  String get pause => _t('pause');
  String get speed => _t('speed');
  String get normal => _t('normal');
  String get loopOn => _t('loopOn');
  String get loopOff => _t('loopOff');
  String get fullscreen => _t('fullscreen');
  String get exitFullscreen => _t('exitFullscreen');
  String get loopEnabled => _t('loopEnabled');
  String get loopDisabled => _t('loopDisabled');
  String get playbackSpeedTitle => _t('playbackSpeedTitle');
  String get rename => _t('rename');
  String get setAsWallpaper => _t('setAsWallpaper');
  String get renameFile => _t('renameFile');
  String get fileName => _t('fileName');
  String get nameCannotBeEmpty => _t('nameCannotBeEmpty');
  String get containsInvalidCharacters => _t('containsInvalidCharacters');
  String get fileAlreadyExists => _t('fileAlreadyExists');
  String get deletePermanentlyTitle => _t('deletePermanentlyTitle');
  String get moveToTrashTitle => _t('moveToTrashTitle');
  String get moveToTrash => _t('moveToTrash');
  String get manageFilesPermissionRequired => _t('manageFilesPermissionRequired');
  String get name => _t('name');
  String get date => _t('date');
  String get size => _t('size');
  String get resolution => _t('resolution');
  String get frameRate => _t('frameRate');
  String get codec => _t('codec');
  String get duration => _t('duration');
  String get path => _t('path');
  String get copyPath => _t('copyPath');
  String get pathCopied => _t('pathCopied');
  String get select => _t('select');
  String get selectAll => _t('selectAll');
  String get deselectAll => _t('deselectAll');
  String get deleteSelected => _t('deleteSelected');
  String get deleteSelectedAlbums => _t('deleteSelectedAlbums');
  String get searchTooltip => _t('searchTooltip');
  String get moreOptions => _t('moreOptions');
  String get noPhotosFound => _t('noPhotosFound');
  String get noVideosFound => _t('noVideosFound');
  String get noAlbumsFound => _t('noAlbumsFound');
  String get recentlyDeleted => _t('recentlyDeleted');
  String get selectItems => _t('selectItems');
  String get trashRetentionNote => _t('trashRetentionNote');
  String get noRecentlyDeleted => _t('noRecentlyDeleted');
  String get permanentlyDeleteAllTitle => _t('permanentlyDeleteAllTitle');
  String get checkUpdateOnLaunchSubtitle => _t('checkUpdateOnLaunchSubtitle');
  String get checkGitHubReleasesSubtitle => _t('checkGitHubReleasesSubtitle');
  String get allFilesGranted => _t('allFilesGranted');
  String get allFilesNotGranted => _t('allFilesNotGranted');
  String get supportedLanguagesCount => _t('supportedLanguagesCount');
  String get selectTheme => _t('selectTheme');
  String get chooseVisualMode => _t('chooseVisualMode');
  String get themeSystemDesc => _t('themeSystemDesc');
  String get themeLightDesc => _t('themeLightDesc');
  String get themeDarkDesc => _t('themeDarkDesc');
  String get themeAmoledDesc => _t('themeAmoledDesc');
  String get themeSakuraDesc => _t('themeSakuraDesc');
  String get selectGridColumns => _t('selectGridColumns');
  String get selectAlbumsGridColumns => _t('selectAlbumsGridColumns');
  String get chooseThumbnailDensity => _t('chooseThumbnailDensity');
  String get chooseAlbumDensity => _t('chooseAlbumDensity');
  String get largeComfortableView => _t('largeComfortableView');
  String get standardBalanced => _t('standardBalanced');
  String get compactDetailedView => _t('compactDetailedView');
  String get denseHighCapacity => _t('denseHighCapacity');
  String get aboutPhantek => _t('aboutPhantek');
  String get offlineGalleryDesc => _t('offlineGalleryDesc');
  String get appVersion => _t('appVersion');
  String get buildNumberLabel => _t('buildNumberLabel');
  String get architecture => _t('architecture');
  String get license => _t('license');
  String get developerLabel => _t('developerLabel');
  String get creatorMaintainer => _t('creatorMaintainer');
  String get openGitHubProfile => _t('openGitHubProfile');
  String get newVersionAvailable => _t('newVersionAvailable');
  String get whatsNew => _t('whatsNew');
  String get downloadAndInstall => _t('downloadAndInstall');
  String get later => _t('later');
  String get downloading => _t('downloading');
  String get alreadyUpToDate => _t('alreadyUpToDate');
  String get downloadFailed => _t('downloadFailed');

  // ── Parameterized methods ───────────────────────────────────────────────
  String renamedTo(String name) => _t('renamedTo').replaceAll('{name}', name);

  String failedToRename(String err) => _t('failedToRename').replaceAll('{err}', err);

  String deletePermanentlyItemDesc(String name) =>
      _t('deletePermanentlyItemDesc').replaceAll('{name}', name);

  String moveToTrashItemDesc(String name) =>
      _t('moveToTrashItemDesc').replaceAll('{name}', name);

  String itemRestored(String name) => _t('itemRestored').replaceAll('{name}', name);

  String itemsRestoredCount(int count) {
    if (count == 1 && _dict.containsKey('itemsRestoredCountSingular')) {
      return _dict['itemsRestoredCountSingular']!;
    }
    return _t('itemsRestoredCount').replaceAll('{count}', '$count');
  }

  String failedToDelete(String err) => _t('failedToDelete').replaceAll('{err}', err);

  String noMediaMatching(String query) =>
      _t('noMediaMatching').replaceAll('{query}', query);

  String noAlbumsMatching(String query) =>
      _t('noAlbumsMatching').replaceAll('{query}', query);

  String itemsCount(int count) {
    if (count == 1 && _dict.containsKey('itemsCountSingular')) {
      return _dict['itemsCountSingular']!;
    }
    return _t('itemsCount').replaceAll('{count}', '$count');
  }

  String albumsCount(int count) {
    if (count == 1 && _dict.containsKey('albumsCountSingular')) {
      return _dict['albumsCountSingular']!;
    }
    return _t('albumsCount').replaceAll('{count}', '$count');
  }

  String permanentlyDeleteCountTitle(int count) {
    if (count == 1 && _dict.containsKey('permanentlyDeleteCountTitleSingular')) {
      return _dict['permanentlyDeleteCountTitleSingular']!;
    }
    return _t('permanentlyDeleteCountTitle').replaceAll('{count}', '$count');
  }

  String moveToTrashConfirm(String name) =>
      _t('moveToTrashConfirm').replaceAll('{name}', name);

  String deletePermanentlyConfirm(String name) =>
      _t('deletePermanentlyConfirm').replaceAll('{name}', name);

  String daysLeft(int count) {
    if (count == 1 && _dict.containsKey('daysLeftSingular')) {
      return _dict['daysLeftSingular']!;
    }
    return _t('daysLeft').replaceAll('{count}', '$count');
  }

  String columnsCount(int count) => _t('columnsCount').replaceAll('{count}', '$count');

  String diskSize(String sizeStr) => _t('diskSize').replaceAll('{sizeStr}', sizeStr);

  String themeModeLabel(AppThemeMode mode) => switch (mode) {
        AppThemeMode.system => _t('themeModeSystem'),
        AppThemeMode.light => _t('themeModeLight'),
        AppThemeMode.dark => _t('themeModeDark'),
        AppThemeMode.amoled => _t('themeModeAmoled'),
        AppThemeMode.amoledSakura => _t('themeModeSakura'),
      };

  String downloadingPercent(int percent) =>
      _t('downloadingPercent').replaceAll('{percent}', '$percent');

  String updateAvailableVersion(String version) =>
      _t('updateAvailableVersion').replaceAll('{version}', version);

  String updateCheckFailed(String error) =>
      _t('updateCheckFailed').replaceAll('{error}', error);

  String installFailed(String error) =>
      _t('installFailed').replaceAll('{error}', error);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => [
        'en',
        'id',
        'ar',
        'zh',
        'da',
        'nl',
        'fi',
        'fr',
        'de',
        'hi',
        'it',
        'ja',
        'ko',
        'ms',
        'no',
        'pt',
        'ru',
        'es',
        'sv',
        'th',
        'vi',
      ].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// Convenience extension on [BuildContext] to access localized strings.
extension AppLocalizationsX on BuildContext {
  AppLocalizations get tr => AppLocalizations.of(this);
}
