// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/settings_model.dart';
import '../providers/settings_provider.dart';

/// A calm, confident, elegant AppBar title widget for Phantek Gallery.
class AnimatedFlameTitle extends ConsumerWidget {
  final String title;

  const AnimatedFlameTitle({
    super.key,
    this.title = 'Phantek',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(
      settingsNotifierProvider.select((s) => s.themeMode),
    );

    final effectiveMode = switch (themeMode) {
      AppThemeMode.system => theme.brightness == Brightness.dark
          ? AppThemeMode.amoledPure
          : AppThemeMode.cleanLight,
      _ => themeMode,
    };

    final (icon, iconColor) = switch (effectiveMode) {
      AppThemeMode.amoledMidnight => (
          Icons.nights_stay_rounded,
          const Color(0xFF818CF8),
        ),
      AppThemeMode.amoledPure => (
          Icons.brightness_2_outlined,
          const Color(0xFF60A5FA),
        ),
      AppThemeMode.amoledSakura => (
          Icons.local_florist_rounded,
          const Color(0xFFFF7597),
        ),
      AppThemeMode.cleanLight => (
          Icons.wb_sunny_outlined,
          const Color(0xFF0EA5E9),
        ),
      AppThemeMode.amoledSnowfall => (
          Icons.ac_unit_rounded,
          const Color(0xFF38BDF8),
        ),
      AppThemeMode.light => (
          Icons.wb_sunny_rounded,
          const Color(0xFF0284C7),
        ),
      AppThemeMode.system => (
          Icons.brightness_2_outlined,
          const Color(0xFF60A5FA),
        ),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 18,
          color: iconColor,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
