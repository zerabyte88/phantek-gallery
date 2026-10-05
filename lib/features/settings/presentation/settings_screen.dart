import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/settings_model.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/services/thumbnail_service.dart';
import '../../../core/widgets/bouncy_tap.dart';
import '../../../features/update/data/update_provider.dart';
import 'widgets/developer_about_card.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _cacheSizeStr = 'Calculating...';

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final sizeStr = await ThumbnailService.instance.getFormattedCacheSize();
    if (mounted) {
      setState(() => _cacheSizeStr = sizeStr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider);
    final update = ref.watch(updateNotifierProvider);

    void patch(SettingsModel Function(SettingsModel) fn) {
      ref.read(settingsNotifierProvider.notifier).update(fn);
    }

    final availableThemeModes = [
      AppThemeMode.system,
      AppThemeMode.light,
      AppThemeMode.dark,
      AppThemeMode.amoled,
      if (settings.isSakuraUnlocked) AppThemeMode.amoledSakura,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
        ),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            // ══ Appearance ══════════════════════════════════════
            const _SectionHeader('Appearance'),
            _SettingsCard(
              children: [
                _ModernTile(
                  icon: Icons.palette_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  title: 'Theme',
                  subtitle: settings.themeMode.label,
                  onTap: () async {
                    final chosen = await _showModernThemeDialog(
                      context,
                      settings.themeMode,
                      availableThemeModes,
                    );
                    if (chosen != null) {
                      patch((s) => s.copyWith(themeMode: chosen));
                    }
                  },
                ),
                const _CardDivider(),
                _ModernTile(
                  icon: Icons.grid_view_rounded,
                  iconColor: const Color(0xFF3B82F6),
                  title: 'Grid Columns',
                  subtitle: '${settings.gridColumns} columns',
                  onTap: () async {
                    final chosen = await _showModernGridColumnsDialog(
                      context,
                      settings.gridColumns,
                      isAlbum: false,
                    );
                    if (chosen != null) {
                      patch((s) => s.copyWith(gridColumns: chosen));
                    }
                  },
                ),
                const _CardDivider(),
                _ModernTile(
                  icon: Icons.photo_library_rounded,
                  iconColor: const Color(0xFF6366F1),
                  title: 'Albums Grid Columns',
                  subtitle: '${settings.albumGridColumns} columns',
                  onTap: () async {
                    final chosen = await _showModernGridColumnsDialog(
                      context,
                      settings.albumGridColumns,
                      isAlbum: true,
                    );
                    if (chosen != null) {
                      patch((s) => s.copyWith(albumGridColumns: chosen));
                    }
                  },
                ),
                const _CardDivider(),
                _ModernSwitchTile(
                  icon: Icons.badge_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  title: 'Show Duration Badges',
                  subtitle: 'Video duration overlay on thumbnails',
                  value: settings.showBadges,
                  onChanged: (v) => patch((s) => s.copyWith(showBadges: v)),
                ),
              ],
            ),

            // ══ Thumbnail Cache ══════════════════════════════════
            const _SectionHeader('Cache'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: _ModernActionButton(
                icon: Icons.cleaning_services_rounded,
                iconColor: const Color(0xFFF97316),
                title: 'Clear Thumbnail Cache',
                subtitle: 'Disk size: $_cacheSizeStr',
                onTap: () async {
                  await ThumbnailService.instance.clearAll();
                  await _loadCacheSize();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Thumbnail cache cleared',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                },
              ),
            ),

            // ══ Storage ═════════════════════════════════════════
            const _SectionHeader('Storage'),
            _SettingsCard(
              children: [
                _ModernSwitchTile(
                  icon: Icons.delete_outline_rounded,
                  iconColor: const Color(0xFF14B8A6),
                  title: 'Trash Bin',
                  subtitle: 'Move to trash instead of deleting',
                  value: settings.enableTrash,
                  onChanged: (v) => patch((s) => s.copyWith(enableTrash: v)),
                ),
                const _CardDivider(),
                _ModernTile(
                  icon: Icons.folder_off_rounded,
                  iconColor: const Color(0xFF64748B),
                  title: 'Excluded Folders',
                  subtitle: settings.excludedFolders.isEmpty
                      ? 'None'
                      : settings.excludedFolders.join('\n'),
                  onTap: () =>
                      _showExcludedFoldersDialog(context, ref, settings),
                ),
                const _CardDivider(),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _ModernActionButton(
                    icon: Icons.security_rounded,
                    iconColor: const Color(0xFFEF4444),
                    title: 'All Files Access (Android 11+)',
                    subtitle:
                        'Enables complete trash and deletion across storage',
                    onTap: () async {
                      final granted = await PermissionService.instance
                          .requestManageStorage();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              granted
                                  ? 'All Files Access granted'
                                  : 'Manage All Files permission is not granted',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),

            // ══ Playback ═════════════════════════════════════════
            const _SectionHeader('Playback'),
            _SettingsCard(
              children: [
                _ModernSwitchTile(
                  icon: Icons.memory_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: 'Hardware Acceleration',
                  subtitle: 'Use GPU decoding for video',
                  value: settings.hardwareAcceleration,
                  onChanged: (v) =>
                      patch((s) => s.copyWith(hardwareAcceleration: v)),
                ),
                const _CardDivider(),
                _ModernSwitchTile(
                  icon: Icons.play_circle_outline_rounded,
                  iconColor: const Color(0xFF06B6D4),
                  title: 'Auto-Play Video',
                  subtitle: 'Start playback automatically',
                  value: settings.autoPlayVideo,
                  onChanged: (v) => patch((s) => s.copyWith(autoPlayVideo: v)),
                ),
              ],
            ),

            // ══ Updates ══════════════════════════════════════════
            const _SectionHeader('Updates'),
            _SettingsCard(
              children: [
                _ModernSwitchTile(
                  icon: Icons.update_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: 'Auto-check for Updates',
                  subtitle: 'Check GitHub Releases on launch',
                  value: settings.autoCheckUpdate,
                  onChanged: (v) =>
                      patch((s) => s.copyWith(autoCheckUpdate: v)),
                ),
                const _CardDivider(),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _ModernActionButton(
                    icon: Icons.system_update_alt_rounded,
                    iconColor: const Color(0xFF8B5CF6),
                    title: 'Check for Updates Now',
                    subtitle: 'Check GitHub for newer APK releases',
                    isLoading: update.isLoading,
                    enabled: !update.isLoading,
                    onTap: () => ref
                        .read(updateNotifierProvider.notifier)
                        .checkForUpdate(silent: false),
                  ),
                ),
              ],
            ),

            // ══ Developer Card ══════════════════════════════════
            const DeveloperAboutCard(),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cs.outline.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }
}

class _ModernActionButton extends StatelessWidget {
  const _ModernActionButton({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.isLoading = false,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool isLoading;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isClickable = enabled && !isLoading && onTap != null;

    return BouncyTap(
      scaleDown: isClickable ? 0.96 : 1.0,
      onTap: isClickable ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: iconColor.withValues(alpha: 0.28),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: iconColor,
                    ),
                  )
                else
                  Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: enabled
                        ? (cs.brightness == Brightness.dark
                            ? Colors.white
                            : cs.onSurface)
                        : cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModernTile extends StatelessWidget {
  const _ModernTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BouncyTap(
      scaleDown: onTap != null ? 0.98 : 1.0,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModernSwitchTile extends StatelessWidget {
  const _ModernSwitchTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BouncyTap(
      scaleDown: 0.99,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: value,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 1,
      indent: 68,
      endIndent: 16,
      color: cs.outline.withValues(alpha: 0.08),
    );
  }
}

Future<void> _showExcludedFoldersDialog(
  BuildContext context,
  WidgetRef ref,
  SettingsModel settings,
) async {
  final controller = TextEditingController();
  final current = List<String>.from(settings.excludedFolders);
  final cs = Theme.of(context).colorScheme;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF64748B).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.folder_off_rounded,
                color: Color(0xFF64748B),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Excluded Folders',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: '/storage/emulated/0/DCIM/...',
                  prefixIcon: const Icon(Icons.folder_open),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: BouncyTap(
                  scaleDown: 0.96,
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      final path = controller.text.trim();
                      if (path.isNotEmpty && !current.contains(path)) {
                        setSt(() => current.add(path));
                        controller.clear();
                      }
                    },
                    child: const Text(
                      'Add',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              if (current.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Divider(),
                ...current.map(
                  (p) => ListTile(
                    dense: true,
                    title: Text(p, style: const TextStyle(fontSize: 13)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setSt(() => current.remove(p)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          BouncyTap(
            scaleDown: 0.95,
            child: TextButton(
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', textAlign: TextAlign.center),
            ),
          ),
          BouncyTap(
            scaleDown: 0.95,
            child: FilledButton(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onPressed: () {
                ref
                    .read(settingsNotifierProvider.notifier)
                    .update((s) => s.copyWith(excludedFolders: current));
                Navigator.pop(ctx);
              },
              child: const Text('Save', textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
}

Future<AppThemeMode?> _showModernThemeDialog(
  BuildContext context,
  AppThemeMode currentTheme,
  List<AppThemeMode> availableThemeModes,
) {
  final cs = Theme.of(context).colorScheme;
  return showDialog<AppThemeMode>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.palette_rounded,
                        color: cs.primary, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Select Theme',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Choose visual mode and contrast',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ...availableThemeModes.map(
                (m) => _ThemeOptionCard(
                  mode: m,
                  selected: currentTheme == m,
                  onTap: () async {
                    await Future.delayed(const Duration(milliseconds: 140));
                    if (ctx.mounted) Navigator.pop(ctx, m);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ThemeOptionCard extends StatelessWidget {
  const _ThemeOptionCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final AppThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final (icon, iconColor, bgPreview, description) = switch (mode) {
      AppThemeMode.system => (
          Icons.brightness_auto_rounded,
          const Color(0xFF6B48FF),
          LinearGradient(
            colors: [Colors.grey.shade300, Colors.grey.shade900],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          'Follows device system settings',
        ),
      AppThemeMode.light => (
          Icons.wb_sunny_rounded,
          const Color(0xFFF59E0B),
          const LinearGradient(
            colors: [Color(0xFFFAFAFA), Color(0xFFE2E8F0)],
          ),
          'Clean & bright daytime palette',
        ),
      AppThemeMode.dark => (
          Icons.dark_mode_rounded,
          const Color(0xFF818CF8),
          const LinearGradient(
            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          ),
          'Sleek charcoal dark mode',
        ),
      AppThemeMode.amoled => (
          Icons.phone_android_rounded,
          const Color(0xFF38BDF8),
          const LinearGradient(
            colors: [Color(0xFF000000), Color(0xFF0A0A0A)],
          ),
          'Pure pitch black for OLED displays',
        ),
      AppThemeMode.amoledSakura => (
          Icons.local_florist_rounded,
          const Color(0xFFFF7597),
          const LinearGradient(
            colors: [Color(0xFF000000), Color(0xFF1E0F16)],
          ),
          'Pure black with cherry sakura pink \u{1F338}',
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BouncyTap(
        scaleDown: 0.96,
        onTap: onTap,
        child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: selected
                    ? cs.primary.withValues(alpha: 0.12)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? cs.primary
                      : cs.outline.withValues(alpha: 0.15),
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: bgPreview,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? cs.primary
                            : Colors.white.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mode.label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                selected ? FontWeight.bold : FontWeight.w600,
                            color: selected ? cs.primary : cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? cs.primary : Colors.transparent,
                      border: Border.all(
                        color: selected
                            ? cs.primary
                            : cs.outline.withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                    child: selected
                        ? Icon(Icons.check, size: 14, color: cs.onPrimary)
                        : null,
                  ),
                ],
          ),
        ),
      ),
    );
  }
}

Future<int?> _showModernGridColumnsDialog(
  BuildContext context,
  int currentCols, {
  required bool isAlbum,
}) {
  final cs = Theme.of(context).colorScheme;
  final title =
      isAlbum ? 'Select Albums Grid Columns' : 'Select Grid Columns';
  final subtitle = isAlbum
      ? 'Choose album cards density'
      : 'Choose media thumbnail density';

  return showDialog<int>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isAlbum
                          ? Icons.photo_library_rounded
                          : Icons.grid_view_rounded,
                      color: cs.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ...[2, 3, 4, 5].map(
                (c) => _ColumnOptionCard(
                  columns: c,
                  selected: currentCols == c,
                  isAlbum: isAlbum,
                  onTap: () async {
                    await Future.delayed(const Duration(milliseconds: 140));
                    if (ctx.mounted) Navigator.pop(ctx, c);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ColumnOptionCard extends StatelessWidget {
  const _ColumnOptionCard({
    required this.columns,
    required this.selected,
    required this.onTap,
    required this.isAlbum,
  });

  final int columns;
  final bool selected;
  final VoidCallback onTap;
  final bool isAlbum;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final subtitle = switch (columns) {
      2 => 'Large comfortable view',
      3 => 'Standard balanced (Default)',
      4 => 'Compact detailed view',
      5 => 'Dense high-capacity overview',
      _ => '$columns columns layout',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BouncyTap(
        scaleDown: 0.96,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? cs.primary.withValues(alpha: 0.12)
                : cs.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? cs.primary
                  : cs.outline.withValues(alpha: 0.15),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // Mini visual grid preview
              Container(
                width: 48,
                height: 38,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? cs.primary.withValues(alpha: 0.5)
                        : cs.outline.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: List.generate(
                    columns,
                    (index) => Expanded(
                      child: Container(
                        margin: EdgeInsets.only(
                          left: index == 0 ? 0 : 2,
                          right: index == columns - 1 ? 0 : 2,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? cs.primary
                              : cs.onSurface.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$columns columns',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.w600,
                        color: selected ? cs.primary : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? cs.primary : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? cs.primary
                        : cs.outline.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check, size: 14, color: cs.onPrimary)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

