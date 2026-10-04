import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../core/models/media_item.dart';
import '../../../../core/providers/media_provider.dart';
import '../../../../core/services/permission_service.dart';
import '../../../../core/services/share_service.dart';

/// Shows an alert dialog allowing the user to rename [item].
///
/// Renames the actual file on storage, updates Android MediaStore via
/// [ShareService.scanFiles], updates [mediaListProvider], and returns
/// the updated [MediaItem] on success or `null` if cancelled/failed.
Future<MediaItem?> showRenameMediaDialog(
  BuildContext context,
  MediaItem item,
  WidgetRef ref,
) async {
  final ext = p.extension(item.path);
  final initialName = p.basenameWithoutExtension(item.path);
  final controller = TextEditingController(text: initialName);
  String? errorMessage;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Rename File'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'File Name',
                    suffixText: ext,
                    errorText: errorMessage,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    if (errorMessage != null) {
                      setDialogState(() => errorMessage = null);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final newBaseName = controller.text.trim();
                  if (newBaseName.isEmpty) {
                    setDialogState(() => errorMessage = 'Name cannot be empty');
                    return;
                  }
                  if (newBaseName == initialName) {
                    Navigator.pop(dialogCtx, false);
                    return;
                  }
                  final invalidChars = RegExp(r'[\\/:*?"<>|]');
                  if (invalidChars.hasMatch(newBaseName)) {
                    setDialogState(
                        () => errorMessage = 'Contains invalid characters');
                    return;
                  }

                  final parentDir = File(item.path).parent.path;
                  final newPath = p.join(parentDir, '$newBaseName$ext');
                  if (await File(newPath).exists()) {
                    setDialogState(
                        () => errorMessage = 'A file with this name already exists');
                    return;
                  }

                  if (dialogCtx.mounted) {
                    Navigator.pop(dialogCtx, true);
                  }
                },
                child: const Text('Rename'),
              ),
            ],
          );
        },
      );
    },
  );

  if (confirmed != true) return null;

  final hasPerm = await PermissionService.instance.ensureManageStorage();
  if (!hasPerm) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Manage All Files permission is required to rename files.'),
        ),
      );
    }
    return null;
  }

  try {
    final newBaseName = controller.text.trim();
    final parentDir = File(item.path).parent.path;
    final newPath = p.join(parentDir, '$newBaseName$ext');
    final oldFile = File(item.path);

    await oldFile.rename(newPath);

    final newItem = item.copyWith(
      name: '$newBaseName$ext',
      path: newPath,
    );

    // Notify Android MediaStore of both the old and new paths
    await ShareService.scanFiles([item.path, newPath]);

    // Update global state immediately
    ref.read(mediaListProvider.notifier).updateItem(newItem);
    ref.read(mediaListProvider.notifier).refresh();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Renamed to "${newItem.name}"')),
      );
    }

    return newItem;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to rename: $e')),
      );
    }
    return null;
  }
}
