import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:phantek_gallery/core/enums/startup_screen.dart';
import 'package:phantek_gallery/core/enums/thumbnail_crop_style.dart';
import 'package:phantek_gallery/core/enums/timeline_grouping.dart';
import 'package:phantek_gallery/core/enums/trash_cleanup_interval.dart';
import 'package:phantek_gallery/core/enums/video_double_tap_action.dart';
import 'package:phantek_gallery/core/localization/app_localizations.dart';
import 'package:phantek_gallery/core/localization/translations/translations.dart';
import 'package:phantek_gallery/core/models/settings_model.dart';

void main() {
  group('Translation Integrity & Typo Checks Across All 22 Languages', () {
    const allLangs = [
      'ar',
      'da',
      'de',
      'es',
      'fi',
      'fr',
      'hi',
      'id',
      'it',
      'ja',
      'ko',
      'ms',
      'nl',
      'no',
      'pt',
      'ru',
      'sv',
      'th',
      'vi',
      'zh',
      'zh_TW',
    ];

    test('Verify all language maps are non-empty and accessible', () {
      expect(enTranslations.isNotEmpty, isTrue);
      for (final lang in allLangs) {
        final dict = getTranslationMap(lang);
        expect(dict.isNotEmpty, isTrue, reason: 'Language $lang map is empty');
      }
    });

    test('Check for missing keys and placeholder parameter consistency', () {
      final placeholderRegex = RegExp(r'\{[a-zA-Z0-9_]+\}');
      final missingKeysByLang = <String, List<String>>{};
      final extraKeysByLang = <String, List<String>>{};
      final placeholderMismatches = <String, List<String>>{};

      for (final lang in allLangs) {
        final dict = getTranslationMap(lang);

        // Missing keys in other language
        for (final key in enTranslations.keys) {
          if (!dict.containsKey(key)) {
            missingKeysByLang.putIfAbsent(lang, () => []).add(key);
          } else {
            // Check placeholders
            final enVal = enTranslations[key]!;
            final langVal = dict[key]!;

            final enPlaceholders = placeholderRegex
                .allMatches(enVal)
                .map((m) => m.group(0)!)
                .toSet();
            final langPlaceholders = placeholderRegex
                .allMatches(langVal)
                .map((m) => m.group(0)!)
                .toSet();

            if (!enPlaceholders.containsAll(langPlaceholders) ||
                !langPlaceholders.containsAll(enPlaceholders)) {
              placeholderMismatches.putIfAbsent(lang, () => []).add(
                  '$key: expected $enPlaceholders but found $langPlaceholders in "$langVal"');
            }
          }
        }

        // Extra keys in other language not in en
        for (final key in dict.keys) {
          if (!enTranslations.containsKey(key)) {
            extraKeysByLang.putIfAbsent(lang, () => []).add(key);
          }
        }
      }


      expect(missingKeysByLang, isEmpty,
          reason: 'Some languages are missing keys defined in enTranslations');
      expect(extraKeysByLang, isEmpty,
          reason: 'Some languages have extra keys not defined in enTranslations');
      expect(placeholderMismatches, isEmpty,
          reason: 'Some translations have mismatched {placeholder} parameter names');
    });

    test('Check for empty translation values', () {
      final emptyValues = <String, List<String>>{};
      for (final lang in ['en', ...allLangs]) {
        final dict = getTranslationMap(lang);
        for (final entry in dict.entries) {
          if (entry.value.trim().isEmpty) {
            emptyValues.putIfAbsent(lang, () => []).add(entry.key);
          }
        }
      }
      expect(emptyValues, isEmpty,
          reason: 'Found empty translation values in: $emptyValues');
    });

    test('Verify AppLocalizations getters and enum switches across all 22 languages', () {
      for (final code in ['en', ...allLangs]) {
        final loc = AppLocalizations(Locale(code.contains('_') ? code.split('_')[0] : code, code.contains('_') ? code.split('_')[1] : null));

        expect(loc.aToZ.isNotEmpty, isTrue, reason: '$code aToZ');
        expect(loc.zToA.isNotEmpty, isTrue, reason: '$code zToA');
        expect(loc.whatsNew.isNotEmpty, isTrue, reason: '$code whatsNew');
        expect(loc.videoDoubleTapAction.isNotEmpty, isTrue, reason: '$code videoDoubleTapAction');
        expect(loc.doubleTapActionSmart.isNotEmpty, isTrue, reason: '$code doubleTapActionSmart');
        expect(loc.doubleTapActionSeekOnly.isNotEmpty, isTrue, reason: '$code doubleTapActionSeekOnly');
        expect(loc.doubleTapActionZoomOnly.isNotEmpty, isTrue, reason: '$code doubleTapActionZoomOnly');

        for (final action in VideoDoubleTapAction.values) {
          expect(loc.videoDoubleTapActionLabel(action).isNotEmpty, isTrue,
              reason: '$code videoDoubleTapActionLabel($action)');
        }

        for (final theme in AppThemeMode.values) {
          expect(loc.themeModeLabel(theme).isNotEmpty, isTrue,
              reason: '$code themeModeLabel($theme)');
        }

        for (final crop in ThumbnailCropStyle.values) {
          expect(loc.thumbnailCropStyleLabel(crop).isNotEmpty, isTrue,
              reason: '$code thumbnailCropStyleLabel($crop)');
        }

        for (final grouping in TimelineGrouping.values) {
          expect(loc.timelineGroupingLabel(grouping).isNotEmpty, isTrue,
              reason: '$code timelineGroupingLabel($grouping)');
        }

        for (final screen in StartupScreen.values) {
          expect(loc.startupScreenLabel(screen).isNotEmpty, isTrue,
              reason: '$code startupScreenLabel($screen)');
        }

        for (final interval in TrashCleanupInterval.values) {
          expect(loc.trashCleanupIntervalLabel(interval).isNotEmpty, isTrue,
              reason: '$code trashCleanupIntervalLabel($interval)');
        }
      }
    });
  });
}
