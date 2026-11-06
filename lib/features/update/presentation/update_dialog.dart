import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/router.dart' show rootNavigatorKey;
import '../../../core/localization/app_localizations.dart';
import '../data/update_provider.dart';
import '../data/update_service.dart';

bool _isUpdateDialogShowing = false;

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
      if (next.hasError) {
        final targetContext = rootNavigatorKey.currentContext ?? context;
        final msg = next.error == 'already_up_to_date'
            ? targetContext.tr.alreadyUpToDate
            : targetContext.tr.updateCheckFailed('${next.error}');
        final messenger = ScaffoldMessenger.maybeOf(targetContext) ??
            ScaffoldMessenger.of(context);
        messenger
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text(
              msg,
              textAlign: TextAlign.center,
            ),
          ));
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
  if (_isUpdateDialogShowing) return;
  final targetContext = rootNavigatorKey.currentContext ?? context;
  _isUpdateDialogShowing = true;
  try {
    await showDialog<void>(
      context: targetContext,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(info: info, ref: ref),
    );
  } catch (e) {
    debugPrint('[UpdateListener] Failed to show update dialog: $e');
  } finally {
    _isUpdateDialogShowing = false;
  }
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
          SnackBar(content: Text(context.tr.downloadFailed)),
        );
      }
    }
  }

  Future<void> _launchInstaller(File apkFile) async {
    // Trigger system package installer via platform channel.
    try {
      // ignore: deprecated_member_use
      await _installApk(apkFile.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr.installFailed('$e'))),
        );
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updateNotifierProvider).value;
    if (state is UpdateDownloading) {
      _progress = state.progress;
    }

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.system_update_alt, color: Colors.green),
          const SizedBox(width: 8),
          Text(context.tr.updateAvailableVersion(widget.info.version)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr.newVersionAvailable,
              style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          if (widget.info.releaseNotes.isNotEmpty) ...[
            Text(context.tr.whatsNew,
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
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
              context.tr.downloadingPercent((_progress * 100).round()),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ),
      actions: [
        if (!_downloading) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr.later),
          ),
          FilledButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.download),
            label: Text(context.tr.downloadAndInstall),
          ),
        ] else
          TextButton(
            onPressed: null,
            child: Text(context.tr.downloading),
          ),
      ],
    );
  }
}

Future<void> _installApk(String apkPath) async {
  // Delegates to Android ACTION_VIEW intent via MethodChannel.
  const channel = MethodChannel('com.phantek.gallery/install');
  await channel.invokeMethod<void>('installApk', {'path': apkPath});
}
