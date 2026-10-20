import 'package:flutter/material.dart';

/// Supported application languages.
enum AppLanguage {
  system(null, 'System Default', 'Default Sistem'),
  ar('ar', 'Arabic', 'العربية'),
  zh('zh', 'Chinese Simplified', '简体中文'),
  zhTw('zh_TW', 'Chinese Traditional', '繁體中文'),
  da('da', 'Danish', 'Dansk'),
  nl('nl', 'Dutch', 'Nederlands'),
  en('en', 'English', 'English'),
  fi('fi', 'Finnish', 'Suomi'),
  fr('fr', 'French', 'Français'),
  de('de', 'German', 'Deutsch'),
  hi('hi', 'Hindi', 'हिन्दी'),
  id('id', 'Indonesian', 'Bahasa Indonesia'),
  it('it', 'Italian', 'Italiano'),
  ja('ja', 'Japanese', '日本語'),
  ko('ko', 'Korean', '한국어'),
  ms('ms', 'Malay', 'Bahasa Melayu'),
  no('no', 'Norwegian', 'Norsk'),
  pt('pt', 'Portuguese', 'Português'),
  ru('ru', 'Russian', 'Русский'),
  es('es', 'Spanish', 'Español'),
  sv('sv', 'Swedish', 'Svenska'),
  th('th', 'Thai', 'ไทย'),
  vi('vi', 'Vietnamese', 'Tiếng Việt');

  const AppLanguage(this.code, this.englishName, this.nativeName);

  /// ISO language code (null for system default).
  final String? code;

  /// English display name.
  final String englishName;

  /// Native script display name.
  final String nativeName;

  /// Corresponding [Locale] or null for system default.
  Locale? get locale {
    if (code == null) return null;
    if (code!.contains('_')) {
      final parts = code!.split('_');
      return Locale(parts[0], parts[1]);
    }
    return Locale(code!);
  }

  /// Official national flag emoji, or null for system default.
  String? get flagEmoji {
    switch (this) {
      case AppLanguage.system:
        return null;
      case AppLanguage.ar:
        return '🇸🇦';
      case AppLanguage.zh:
        return '🇨🇳';
      case AppLanguage.zhTw:
        return '🇹🇼';
      case AppLanguage.da:
        return '🇩🇰';
      case AppLanguage.nl:
        return '🇳🇱';
      case AppLanguage.en:
        return '🇺🇸';
      case AppLanguage.fi:
        return '🇫🇮';
      case AppLanguage.fr:
        return '🇫🇷';
      case AppLanguage.de:
        return '🇩🇪';
      case AppLanguage.hi:
        return '🇮🇳';
      case AppLanguage.id:
        return '🇮🇩';
      case AppLanguage.it:
        return '🇮🇹';
      case AppLanguage.ja:
        return '🇯🇵';
      case AppLanguage.ko:
        return '🇰🇷';
      case AppLanguage.ms:
        return '🇲🇾';
      case AppLanguage.no:
        return '🇳🇴';
      case AppLanguage.pt:
        return '🇧🇷';
      case AppLanguage.ru:
        return '🇷🇺';
      case AppLanguage.es:
        return '🇪🇸';
      case AppLanguage.sv:
        return '🇸🇪';
      case AppLanguage.th:
        return '🇹🇭';
      case AppLanguage.vi:
        return '🇻🇳';
    }
  }

  /// Look up [AppLanguage] from language code.
  static AppLanguage fromCode(String? code) {
    if (code == null) return AppLanguage.system;
    return AppLanguage.values.firstWhere(
      (l) => l.code == code,
      orElse: () => AppLanguage.system,
    );
  }

  /// Languages sorted alphabetically (A-Z) by [englishName], with [system] pinned at the top.
  static List<AppLanguage> get sortedLanguages {
    final list = AppLanguage.values
        .where((l) => l != AppLanguage.system)
        .toList()
      ..sort((a, b) => a.englishName.compareTo(b.englishName));
    return [AppLanguage.system, ...list];
  }

  /// All supported [Locale]s for [MaterialApp].
  static List<Locale> get supportedLocales => const [
        Locale('en'),
        Locale('id'),
        Locale('ar'),
        Locale('zh'),
        Locale('zh', 'TW'),
        Locale('da'),
        Locale('nl'),
        Locale('fi'),
        Locale('fr'),
        Locale('de'),
        Locale('hi'),
        Locale('it'),
        Locale('ja'),
        Locale('ko'),
        Locale('ms'),
        Locale('no'),
        Locale('pt'),
        Locale('ru'),
        Locale('es'),
        Locale('sv'),
        Locale('th'),
        Locale('vi'),
      ];
}
