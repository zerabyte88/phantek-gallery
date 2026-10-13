import 'ar.dart';
import 'da.dart';
import 'de.dart';
import 'en.dart';
import 'es.dart';
import 'fi.dart';
import 'fr.dart';
import 'hi.dart';
import 'id.dart';
import 'it.dart';
import 'ja.dart';
import 'ko.dart';
import 'ms.dart';
import 'nl.dart';
import 'no.dart';
import 'pt.dart';
import 'ru.dart';
import 'sv.dart';
import 'th.dart';
import 'vi.dart';
import 'zh.dart';
import 'zh_tw.dart';

export 'ar.dart';
export 'da.dart';
export 'de.dart';
export 'en.dart';
export 'es.dart';
export 'fi.dart';
export 'fr.dart';
export 'hi.dart';
export 'id.dart';
export 'it.dart';
export 'ja.dart';
export 'ko.dart';
export 'ms.dart';
export 'nl.dart';
export 'no.dart';
export 'pt.dart';
export 'ru.dart';
export 'sv.dart';
export 'th.dart';
export 'vi.dart';
export 'zh.dart';
export 'zh_tw.dart';

/// Returns the translation map for [code], with automatic fallback to English.
Map<String, String> getTranslationMap(String code) {
  return switch (code) {
    'ar' => arTranslations,
    'da' => daTranslations,
    'de' => deTranslations,
    'es' => esTranslations,
    'fi' => fiTranslations,
    'fr' => frTranslations,
    'hi' => hiTranslations,
    'id' => idTranslations,
    'it' => itTranslations,
    'ja' => jaTranslations,
    'ko' => koTranslations,
    'ms' => msTranslations,
    'nl' => nlTranslations,
    'no' => noTranslations,
    'pt' => ptTranslations,
    'ru' => ruTranslations,
    'sv' => svTranslations,
    'th' => thTranslations,
    'vi' => viTranslations,
    'zh' => zhTranslations,
    'zh_TW' || 'zh_tw' => zhTwTranslations,
    _ => enTranslations,
  };
}
