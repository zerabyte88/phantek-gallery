import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/settings_model.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/services/thumbnail_service.dart';
import '../../../features/update/data/update_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final update = ref.watch(updateNotifierProvider);

    void patch(SettingsModel Function(SettingsModel) fn) {
      ref.read(settingsNotifierProvider.notifier).update(fn);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // ══ Appearance ══════════════════════════════════════
          _SectionHeader('Appearance'),

          ListTile(
            title: const Text('Theme'),
            subtitle: Text(settings.themeMode.name),
            leading: const Icon(Icons.palette_outlined),
            onTap: () async {
              final chosen = await showDialog<AppThemeMode>(
                context: context,
                builder: (_) => SimpleDialog(
                  title: const Text('Select Theme'),
                  children: AppThemeMode.values
                      .map((m) => SimpleDialogOption(
                            onPressed: () => Navigator.pop(context, m),
                            child: Text(m.name),
                          ))
                      .toList(),
                ),
              );
              if (chosen != null) {
                patch((s) => s.copyWith(themeMode: chosen));
              }
            },
          ),

          ListTile(
            title: const Text('Grid Columns'),
            subtitle: Text('${settings.gridColumns} columns'),
            leading: const Icon(Icons.grid_view_outlined),
            trailing: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 3, label: Text('3')),
                ButtonSegment(value: 4, label: Text('4')),
                ButtonSegment(value: 5, label: Text('5')),
              ],
              selected: {settings.gridColumns},
              onSelectionChanged: (s) =>
                  patch((st) => st.copyWith(gridColumns: s.first)),
              style: SegmentedButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
          ),

          SwitchListTile(
            title: const Text('Show Duration Badges'),
            subtitle: const Text('Video duration overlay on thumbnails'),
            secondary: const Icon(Icons.badge_outlined),
            value: settings.showBadges,
            onChanged: (v) => patch((s) => s.copyWith(showBadges: v)),
          ),

          // ══ Thumbnail Cache ══════════════════════════════════
          _SectionHeader('Cache'),

          ListTile(
            title: const Text('Clear Thumbnail Cache'),
            subtitle: const Text('Frees memory from cached thumbs'),
            leading: const Icon(Icons.cleaning_services_outlined),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ThumbnailService.instance.clearAll();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Thumbnail cache cleared')),
              );
            },
          ),

          // ══ Storage ═════════════════════════════════════════
          _SectionHeader('Storage'),

          SwitchListTile(
            title: const Text('Trash Bin'),
            subtitle: const Text('Move to trash instead of deleting'),
            secondary: const Icon(Icons.delete_outline),
            value: settings.enableTrash,
            onChanged: (v) => patch((s) => s.copyWith(enableTrash: v)),
          ),

          ListTile(
            title: const Text('Excluded Folders'),
            subtitle: settings.excludedFolders.isEmpty
                ? const Text('None')
                : Text(settings.excludedFolders.join('\n'),
                    style: const TextStyle(fontSize: 12)),
            leading: const Icon(Icons.folder_off_outlined),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showExcludedFoldersDialog(context, ref, settings),
          ),

          ListTile(
            title: const Text('All Files Access (Android 11+)'),
            subtitle: const Text('Enables complete trash and deletion across storage'),
            leading: const Icon(Icons.security_outlined),
            trailing: const Icon(Icons.open_in_new),
            onTap: () async {
              final granted = await PermissionService.instance.requestManageStorage();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(granted
                        ? 'All Files Access granted \u2705'
                        : 'Manage All Files permission is not granted'),
                  ),
                );
              }
            },
          ),

          // ══ Playback ═════════════════════════════════════════
          _SectionHeader('Playback'),

          SwitchListTile(
            title: const Text('Hardware Acceleration'),
            subtitle: const Text('Use GPU decoding for video'),
            secondary: const Icon(Icons.memory_outlined),
            value: settings.hardwareAcceleration,
            onChanged: (v) =>
                patch((s) => s.copyWith(hardwareAcceleration: v)),
          ),

          SwitchListTile(
            title: const Text('Auto-Play Video'),
            subtitle: const Text('Start playback automatically'),
            secondary: const Icon(Icons.play_circle_outline),
            value: settings.autoPlayVideo,
            onChanged: (v) => patch((s) => s.copyWith(autoPlayVideo: v)),
          ),

          // ══ Updates ══════════════════════════════════════════
          _SectionHeader('Updates'),

          SwitchListTile(
            title: const Text('Auto-check for Updates'),
            subtitle: const Text('Check GitHub Releases on launch'),
            secondary: const Icon(Icons.update),
            value: settings.autoCheckUpdate,
            onChanged: (v) =>
                patch((s) => s.copyWith(autoCheckUpdate: v)),
          ),

          ListTile(
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
