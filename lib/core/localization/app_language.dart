import 'package:flutter/material.dart';

/// Supported application languages.
enum AppLanguage {
  system(null, 'System Default', 'Default Sistem'),
  id('id', 'Indonesian', 'Bahasa Indonesia'),
  en('en', 'English', 'English'),
  zh('zh', 'Chinese Simplified', '简体中文'),
  es('es', 'Spanish', 'Español'),
  pt('pt', 'Portuguese', 'Português'),
  ja('ja', 'Japanese', '日本語'),
  ko('ko', 'Korean', '한국어'),
  hi('hi', 'Hindi', 'हिन्दी'),
  ar('ar', 'Arabic', 'العربية'),
  fr('fr', 'French', 'Français'),
  ru('ru', 'Russian', 'Русский');

  const AppLanguage(this.code, this.englishName, this.nativeName);

  /// ISO language code (null for system default).
  final String? code;

  /// English display name.
  final String englishName;

  /// Native script display name.
  final String nativeName;

  /// Corresponding [Locale] or null for system default.
  Locale? get locale => code != null ? Locale(code!) : null;

  /// Look up [AppLanguage] from language code.
  static AppLanguage fromCode(String? code) {
    if (code == null) return AppLanguage.system;
    return AppLanguage.values.firstWhere(
      (l) => l.code == code,
      orElse: () => AppLanguage.system,
    );
  }

  /// All supported [Locale]s for [MaterialApp].
  static List<Locale> get supportedLocales => const [
        Locale('id'),
        Locale('en'),
        Locale('zh'),
        Locale('es'),
        Locale('pt'),
        Locale('ja'),
        Locale('ko'),
        Locale('hi'),
        Locale('ar'),
        Locale('fr'),
        Locale('ru'),
      ];
}
