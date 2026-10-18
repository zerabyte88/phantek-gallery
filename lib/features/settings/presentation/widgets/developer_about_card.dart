// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 zerabyte88

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/localization/app_localizations.dart';

/// Developer & About card placed at the bottom of the Settings screen.
class DeveloperAboutCard extends ConsumerWidget {
  const DeveloperAboutCard({super.key});

  static const _cyan = Color(0xFF06B6D4);
  static const _githubProfileUrl = 'https://github.com/zerabyte88';

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not open $url: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final version = snapshot.data?.version ?? '2.8.1';
        final buildNumber = snapshot.data?.buildNumber ?? '43';

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.60),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: cs.outline.withValues(alpha: 0.12),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: About App ───────────────────────────────────
              Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: _cyan,
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
              const SizedBox(height: 4),
              Text(
                context.tr.offlineGalleryDesc,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.55),
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 14),

              // ── Detail Rows ─────────────────────────────────────────
              _buildDetailRow(theme, context.tr.appVersion, 'v$version'),
              _buildDetailRow(
                theme,
                context.tr.buildNumberLabel,
                '$buildNumber (Release APK)',
              ),
              _buildDetailRow(
                theme,
                context.tr.architecture,
                'ARM64-v8a (MediaKit)',
              ),
              _buildDetailRow(
                theme,
                context.tr.license,
                'GPLv3',
                onTap: () {
                  showLicensePage(
                    context: context,
                    applicationName: 'Phantek Gallery',
                    applicationVersion: 'v$version ($buildNumber)',
                    applicationLegalese:
                        'Copyright © 2026 zerabyte88\nLicensed under GNU General Public License v3.0 (GPLv3)',
                  );
                },
              ),

              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(
                  height: 1,
                  color: cs.outline.withValues(alpha: 0.15),
                ),
              ),

              // ── Developer Profile ───────────────────────────────────
              Row(
                children: [
                  Container(
                    key: const ValueKey('developer_avatar'),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _cyan,
                        width: 1.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _cyan.withValues(alpha: 0.35),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.network(
                        'https://github.com/zerabyte88.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Image.asset(
                          'assets/developer_avatar.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.person_rounded,
                            color: _cyan,
                            size: 24,
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
                          '${context.tr.developerLabel}: zerabyte88',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          context.tr.creatorMaintainer,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _openUrl(_githubProfileUrl),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _cyan.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _cyan.withValues(alpha: 0.35),
                            width: 0.9,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.open_in_new_rounded,
                              size: 13,
                              color: _cyan,
                            ),
                            SizedBox(width: 5),
                            Text(
                              'GitHub',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: _cyan,
                              ),
                            ),
                          ],
                        ),
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
                      ? _cyan
                      : theme.colorScheme.onSurface,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: _cyan,
                ),
              ],
            ],
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: rowContent,
      );
    }

    return rowContent;
  }
}
