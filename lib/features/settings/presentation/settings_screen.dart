import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/settings_model.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/services/thumbnail_service.dart';
import '../../../core/utils/easter_egg_handler.dart';
import '../../../core/widgets/bouncy_tap.dart';
import '../../../features/update/data/update_provider.dart';
import 'widgets/developer_about_card.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _easterEggHandler = EasterEggTapHandler();
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: BouncyTap(
                key: const ValueKey('settings_appbar_badge_easter_egg'),
                scaleDown: 0.92,
                onTap: () => _easterEggHandler.handleTap(context, ref),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00382B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF00E676).withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                  child: const Text(
                    'v1.2.0',
                    style: TextStyle(
                      color: Color(0xFF00E676),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          // ══ Appearance ══════════════════════════════════════
          _SectionHeader('Appearance'),

          BouncyTap(
            scaleDown: 0.98,
            child: ListTile(
              title: const Text('Theme'),
              subtitle: Text(settings.themeMode.label),
              leading: const Icon(Icons.palette_outlined),
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
          ),

          BouncyTap(
            scaleDown: 0.98,
            child: ListTile(
              title: const Text('Grid Columns'),
              subtitle: Text('${settings.gridColumns} columns'),
              leading: const Icon(Icons.grid_view_outlined),
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
          ),

          BouncyTap(
            scaleDown: 0.98,
            child: ListTile(
              title: const Text('Albums Grid Columns'),
              subtitle: Text('${settings.albumGridColumns} columns'),
              leading: const Icon(Icons.photo_library_outlined),
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
          ),

          BouncyTap(
            scaleDown: 0.99,
            child: SwitchListTile(
              title: const Text('Show Duration Badges'),
              subtitle: const Text('Video duration overlay on thumbnails'),
              secondary: const Icon(Icons.badge_outlined),
              value: settings.showBadges,
              onChanged: (v) => patch((s) => s.copyWith(showBadges: v)),
            ),
          ),

          // ══ Thumbnail Cache ══════════════════════════════════
          _SectionHeader('Cache'),

          BouncyTap(
            scaleDown: 0.98,
            child: ListTile(
              title: const Text('Clear Thumbnail Cache'),
              subtitle: Text('Disk size: $_cacheSizeStr • Frees cached previews'),
              leading: const Icon(Icons.cleaning_services_outlined),
              trailing: const Icon(Icons.delete_outline),
              onTap: () async {
                await ThumbnailService.instance.clearAll();
                await _loadCacheSize();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Thumbnail cache cleared', textAlign: TextAlign.center),
                    ),
                  );
                }
              },
            ),
          ),

          // ══ Storage ═════════════════════════════════════════
          _SectionHeader('Storage'),

          BouncyTap(
            scaleDown: 0.99,
            child: SwitchListTile(
              title: const Text('Trash Bin'),
              subtitle: const Text('Move to trash instead of deleting'),
              secondary: const Icon(Icons.delete_outline),
              value: settings.enableTrash,
              onChanged: (v) => patch((s) => s.copyWith(enableTrash: v)),
            ),
          ),

          BouncyTap(
            scaleDown: 0.98,
            child: ListTile(
              title: const Text('Excluded Folders'),
              subtitle: settings.excludedFolders.isEmpty
                  ? const Text('None')
                  : Text(settings.excludedFolders.join('\n'),
                      style: const TextStyle(fontSize: 12)),
              leading: const Icon(Icons.folder_off_outlined),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showExcludedFoldersDialog(context, ref, settings),
            ),
          ),

          BouncyTap(
            scaleDown: 0.98,
            child: ListTile(
              title: const Text('All Files Access (Android 11+)'),
              subtitle: const Text('Enables complete trash and deletion across storage'),
              leading: const Icon(Icons.security_outlined),
              trailing: const Icon(Icons.open_in_new),
              onTap: () async {
                final granted = await PermissionService.instance.requestManageStorage();
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

          // ══ Playback ═════════════════════════════════════════
          _SectionHeader('Playback'),

          BouncyTap(
            scaleDown: 0.99,
            child: SwitchListTile(
              title: const Text('Hardware Acceleration'),
              subtitle: const Text('Use GPU decoding for video'),
              secondary: const Icon(Icons.memory_outlined),
              value: settings.hardwareAcceleration,
              onChanged: (v) =>
                  patch((s) => s.copyWith(hardwareAcceleration: v)),
            ),
          ),

          BouncyTap(
            scaleDown: 0.99,
            child: SwitchListTile(
              title: const Text('Auto-Play Video'),
              subtitle: const Text('Start playback automatically'),
              secondary: const Icon(Icons.play_circle_outline),
              value: settings.autoPlayVideo,
              onChanged: (v) => patch((s) => s.copyWith(autoPlayVideo: v)),
            ),
          ),

          // ══ Updates ══════════════════════════════════════════
          _SectionHeader('Updates'),

          BouncyTap(
            scaleDown: 0.99,
            child: SwitchListTile(
              title: const Text('Auto-check for Updates'),
              subtitle: const Text('Check GitHub Releases on launch'),
              secondary: const Icon(Icons.update),
              value: settings.autoCheckUpdate,
              onChanged: (v) =>
                  patch((s) => s.copyWith(autoCheckUpdate: v)),
            ),
          ),

          BouncyTap(
            scaleDown: 0.98,
            child: ListTile(
              title: const Text('Check for Updates Now'),
              leading: const Icon(Icons.system_update_alt_outlined),
              trailing: update.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chevron_right),
              enabled: !update.isLoading,
              onTap: () => ref
                  .read(updateNotifierProvider.notifier)
                  .checkForUpdate(silent: false),
            ),
          ),

          // ══ Developer Card ══════════════════════════════════
          const DeveloperAboutCard(),
        ],
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
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
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

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: const Text('Excluded Folders'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: '/storage/emulated/0/DCIM/...',
                  prefixIcon: Icon(Icons.folder_open),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () {
                  final path = controller.text.trim();
                  if (path.isNotEmpty && !current.contains(path)) {
                    setSt(() => current.add(path));
                    controller.clear();
                  }
                },
                child: const Text('Add'),
              ),
              const Divider(),
              ...current.map(
                (p) => ListTile(
                  dense: true,
                  title:
                      Text(p, style: const TextStyle(fontSize: 13)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setSt(() => current.remove(p)),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              ref
                  .read(settingsNotifierProvider.notifier)
                  .update((s) => s.copyWith(excludedFolders: current));
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SimpleDialogOption(
            padding: EdgeInsets.zero,
            onPressed: onTap,
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

