import 'package:flutter/services.dart';

/// Service to pick directory path directly via Android's native File Manager.
class FolderPickerService {
  FolderPickerService._();
  static final FolderPickerService instance = FolderPickerService._();

  static const MethodChannel _channel =
      MethodChannel('com.phantek.gallery/folder_picker');

  /// Opens Android's native file manager (SAF Document Tree picker)
  /// and returns the absolute directory path (e.g. `/storage/emulated/0/DCIM/Camera`),
  /// or null if cancelled.
  Future<String?> pickFolder() async {
    try {
      final path = await _channel.invokeMethod<String>('pickFolder');
      if (path != null && path.trim().isNotEmpty) {
        return path.trim();
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
