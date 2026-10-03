import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

/// Centralises runtime permission requests for media access.
class PermissionService {
  PermissionService._();
  static final PermissionService instance = PermissionService._();

  /// Request media permissions suitable for the active Android version:
  /// - Android 14, 15, 16+ (API 34+): full access or user-selected partial access
  /// - Android 13 (API 33): granular photos & videos
  /// - Android 12 and below (API <= 32): storage (READ/WRITE_EXTERNAL_STORAGE)
  ///
  /// Uses [PhotoManager.requestPermissionExtend], which delegates directly to
  /// native Android platform code checking Build.VERSION.SDK_INT and handling
  /// all OS versions correctly.
  Future<bool> requestMediaPermissions() async {
    try {
      if (await Permission.manageExternalStorage.isGranted) {
        return true;
      }

      final state = await PhotoManager.requestPermissionExtend();
      return state.hasAccess;
    } catch (_) {
      return false;
    }
  }

  /// Request "All Files Access" (MANAGE_EXTERNAL_STORAGE) on Android 11+ (API 30+).
  /// Required for deep trash operations and direct file deletion across arbitrary folders.
  Future<bool> requestManageStorage() async {
    final status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;
    final res = await Permission.manageExternalStorage.request();
    return res.isGranted;
  }

  /// Check whether Manage External Storage is granted.
  Future<bool> hasManageStoragePermission() async {
    return Permission.manageExternalStorage.isGranted;
  }

  /// Ensures All Files Access is granted if on Android, requesting it if needed.
  Future<bool> ensureManageStorage() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    return requestManageStorage();
  }

  /// Check if basic media access is granted without prompting.
  Future<bool> hasMediaPermission() async {
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }
    // PhotoManager has hasPermissionToRead / requestPermissionExtend
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.common,
          mediaLocation: false,
        ),
      ),
    );
    return state.hasAccess;
  }

  /// Open app system settings so user can grant denied permissions.
  Future<void> openSettings() => PhotoManager.openSetting();
}
