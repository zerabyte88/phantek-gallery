// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/services/license_service.dart';
import '../../../../core/widgets/bouncy_tap.dart';

/// Developer & About card matching the Phantek Video Toolkit Vega standard.
class DeveloperAboutCard extends ConsumerWidget {
  const DeveloperAboutCard({super.key});

  static const _githubProfileUrl = 'https://github.com/zerabyte88';

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not open $url: $e');
    }
  }

  void _showAppLicensePage(
    BuildContext context,
    ThemeData theme,
    String version,
    String buildNumber,
  ) {
    LicenseService.registerLicenses();
    showLicensePage(
      context: context,
      applicationName: 'Phantek Gallery',
      applicationVersion: '',
      applicationLegalese: '',
      applicationIcon: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/app_icon.png',
                width: 56,
                height: 56,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.photo_library_rounded,
                  size: 56,
                ),
              ),
            ),
          ),
          Text(
            'v$version ($buildNumber)',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Text(
              'Copyright © 2026 zerabyte88\n'
              'Licensed under the MIT License.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final version = snapshot.data?.version ?? '2.14.9';
        final buildNumber = snapshot.data?.buildNumber ?? '762451';
        final isDark = theme.brightness == Brightness.dark;

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? cs.surfaceContainerLow : cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: isDark ? 0.12 : 0.18),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.tr.aboutApp,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildDetailRow(theme, context.tr.appVersion, 'v$version'),
              const SizedBox(height: 6),
              _buildDetailRow(theme, context.tr.buildNumberLabel, buildNumber),
              const SizedBox(height: 6),
              _buildDetailRow(
                theme,
                context.tr.license,
                'MIT License',
                onTap: () => _showAppLicensePage(
                  context,
                  theme,
                  version,
                  buildNumber,
                ),
              ),
              Divider(
                height: 24,
                thickness: 1,
                color: cs.outlineVariant.withValues(alpha: isDark ? 0.12 : 0.18),
              ),
              Row(
                children: [
                  SizedBox(
                    key: const ValueKey('developer_avatar'),
                    width: 36,
                    height: 36,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/developer_avatar.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: cs.surfaceContainerHighest
                              .withValues(alpha: isDark ? 0.55 : 0.75),
                          child: Icon(
                            Icons.person_rounded,
                            size: 18,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Developer: zerabyte88',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'github.com/zerabyte88',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  BouncyTap(
                    scaleDown: 0.94,
                    onTap: () => _openUrl(_githubProfileUrl),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest
                            .withValues(alpha: isDark ? 0.55 : 0.75),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 13,
                            color: cs.onSurface,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'GitHub',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(
    ThemeData theme,
    String label,
    String value, {
    VoidCallback? onTap,
    bool showChevron = false,
  }) {
    final rowContent = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: onTap != null
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
              if (showChevron && onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
              ],
            ],
          ),
        ],
      ),
    );

    if (onTap != null) {
      return BouncyTap(
        scaleDown: 0.985,
        onTap: onTap,
        child: rowContent,
      );
    }

    return rowContent;
  }
}
