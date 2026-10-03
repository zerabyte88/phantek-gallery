import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/update_provider.dart';
import '../data/update_service.dart';

/// Listens to [updateNotifierProvider] and shows the update dialog /
/// progress sheet automatically when a new version is found.
class UpdateListener extends ConsumerWidget {
  const UpdateListener({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(updateNotifierProvider, (_, next) {
      final state = next.value;
      if (state is UpdateFound) {
        _showUpdateDialog(context, ref, state.info);
      }
      // Show snackbar for error / already up-to-date.
      if (next.hasError) {
        final msg = next.error == 'already_up_to_date'
            ? 'Already up to date ✅'
            : 'Update check failed: ${next.error}';
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(msg)));
      }
    });
    return child;
  }
}

Future<void> _showUpdateDialog(
  BuildContext context,
  WidgetRef ref,
  UpdateInfo info,
) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(info: info, ref: ref),
  );
}

class _UpdateDialog extends ConsumerStatefulWidget {
  const _UpdateDialog({required this.info, required this.ref});
  final UpdateInfo info;
  final WidgetRef ref;

  @override
  ConsumerState<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;

  Future<void> _startDownload() async {
    setState(() => _downloading = true);
    final apkFile = await ref
        .read(updateNotifierProvider.notifier)
        .downloadAndInstall(widget.info, context);
    if (!mounted) return;

    if (apkFile != null && await apkFile.exists()) {
      await _launchInstaller(apkFile);
    } else {
      setState(() => _downloading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download failed. Please try again.')),
        );
      }
    }
  }

  Future<void> _launchInstaller(File apkFile) async {
    // Use Android Intent to trigger system package installer.
    // We rely on the platform channel exposed by the OS; no extra plugin needed.
    // The FileProvider authority must match AndroidManifest.
    try {
      // ignore: deprecated_member_use
      await _installApk(apkFile.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Install failed: $e')),
        );
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Track download progress from provider.
    final state = ref.watch(updateNotifierProvider).value;
    if (state is UpdateDownloading) {
      _progress = state.progress;
    }

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.system_update_alt, color: Colors.green),
          const SizedBox(width: 8),
          Text('Update v${widget.info.version}'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('A new version of Phantek Gallery is available.',
              style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          if (widget.info.releaseNotes.isNotEmpty) ...[
            const Text('What\u2019s new:',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150),
              child: SingleChildScrollView(
                child: Text(
                  widget.info.releaseNotes,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text(
              '${(_progress * 100).toStringAsFixed(0)}% downloaded',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ),
      actions: [
        if (!_downloading) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.download),
            label: const Text('Download & Install'),
          ),
        ] else
          const TextButton(
            onPressed: null,
            child: Text('Downloading…'),
          ),
      ],
    );
  }
}

// ── Platform channel helper for APK install ───────────────────────────────

Future<void> _installApk(String apkPath) async {
  // Delegates to Android's ACTION_VIEW intent via MethodChannel.
  // This requires FileProvider authority: com.phantek.virgo.spica.fileprovider
  // and android.permission.REQUEST_INSTALL_PACKAGES (already in manifest).
  const channel = MethodChannel('com.phantek.gallery/install');
  await channel.invokeMethod<void>('installApk', {'path': apkPath});
}

