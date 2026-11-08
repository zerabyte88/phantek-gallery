// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/models/settings_model.dart';

/// Extension pembantu untuk memastikan akses getter `themeMode*` tersedia
/// secara langsung pada [AppLocalizations].
extension ModernThemeGridLocalizationsX on AppLocalizations {
  String get themeModeSystem => themeModeLabel(AppThemeMode.system);
  String get themeModeCleanLight => themeModeLabel(AppThemeMode.cleanLight);
  String get themeModeAmoledPure => themeModeLabel(AppThemeMode.amoledPure);
  String get themeModeDark => themeModeLabel(AppThemeMode.amoledSnowfall);
  String get themeModeLight => themeModeLabel(AppThemeMode.light);
  String get themeModeAmoled => themeModeLabel(AppThemeMode.amoledMidnight);
  String get themeModeSakura => themeModeLabel(AppThemeMode.amoledSakura);
}

/// Data representasi satu kartu tema di dalam grid.
class _ThemeItem {
  const _ThemeItem({
    required this.mode,
    required this.icon,
    required this.accent,
    required this.title,
    required this.badge,
  });

  final AppThemeMode mode;
  final IconData icon;
  final Color accent;
  final String title;
  final String badge;
}

/// Widget Grid Tema Modern mengadopsi standar visual & arsitektur dari Phantek Video Toolkit Vega.
///
/// Terdiri dari 2 baris kartu tema:
/// - Baris 1: 3 kartu tema statis / sistem (System, Clean Light, AMOLED Pure)
/// - Baris 2: 4 kartu tema animated / live (Snowfall, Sunlight, Midnight, Sakura)
class ModernThemeGrid extends StatelessWidget {
  const ModernThemeGrid({
    super.key,
    required this.currentTheme,
    required this.onThemeSelected,
  });

  final AppThemeMode currentTheme;
  final ValueChanged<AppThemeMode> onThemeSelected;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;

    final staticThemes = [
      _ThemeItem(
        mode: AppThemeMode.system,
        icon: Icons.brightness_auto_rounded,
        accent: const Color(0xFF2563EB),
        title: tr.themeModeSystem,
        badge: 'Auto',
      ),
      _ThemeItem(
        mode: AppThemeMode.cleanLight,
        icon: Icons.light_mode_rounded,
        accent: const Color(0xFF0EA5E9),
        title: tr.themeModeCleanLight,
        badge: 'Static',
      ),
      _ThemeItem(
        mode: AppThemeMode.amoledPure,
        icon: Icons.dark_mode_rounded,
        accent: const Color(0xFF60A5FA),
        title: tr.themeModeAmoledPure,
        badge: 'Static',
      ),
    ];

    final animatedThemes = [
      _ThemeItem(
        mode: AppThemeMode.amoledSnowfall,
        icon: Icons.ac_unit_rounded,
        accent: const Color(0xFF38BDF8),
        title: tr.themeModeDark,
        badge: 'Live',
      ),
      _ThemeItem(
        mode: AppThemeMode.light,
        icon: Icons.wb_sunny_rounded,
        accent: const Color(0xFFFBBF24),
        title: tr.themeModeLight,
        badge: 'Live',
      ),
      _ThemeItem(
        mode: AppThemeMode.amoledMidnight,
        icon: Icons.nights_stay_rounded,
        accent: const Color(0xFFA78BFA),
        title: tr.themeModeAmoled,
        badge: 'Live',
      ),
      _ThemeItem(
        mode: AppThemeMode.amoledSakura,
        icon: Icons.local_florist_rounded,
        accent: const Color(0xFFF472B6),
        title: tr.themeModeSakura,
        badge: 'Live',
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Baris 1: Static / System Themes (3 kartu)
        Row(
          children: [
            for (int i = 0; i < staticThemes.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _ThemeCard(
                  item: staticThemes[i],
                  isSelected: currentTheme == staticThemes[i].mode,
                  onTap: () => onThemeSelected(staticThemes[i].mode),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // Baris 2: Live / Animated Themes (4 kartu)
        Row(
          children: [
            for (int i = 0; i < animatedThemes.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: _ThemeCard(
                  item: animatedThemes[i],
                  isSelected: currentTheme == animatedThemes[i].mode,
                  onTap: () => onThemeSelected(animatedThemes[i].mode),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Kartu tema individu dengan visual and feel khas Phantek Video Toolkit Vega.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final _ThemeItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = item.accent;

    return Material(
      color: isSelected
          ? accent.withValues(alpha: isDark ? 0.16 : 0.10)
          : cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.35 : 0.45),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 78,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? accent
                  : cs.outlineVariant.withValues(alpha: isDark ? 0.18 : 0.25),
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                item.icon,
                size: 20,
                color: isSelected ? accent : cs.onSurface,
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  item.title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? accent : cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: accent.withValues(alpha: isDark ? 0.50 : 0.35),
                    width: 0.9,
                  ),
                ),
                child: Text(
                  item.badge,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: accent,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
