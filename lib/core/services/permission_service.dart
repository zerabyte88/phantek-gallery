import 'package:permission_handler/permission_handler.dart';

/// Centralises runtime permission requests for media access.
class PermissionService {
  PermissionService._();
  static final PermissionService instance = PermissionService._();

  /// Request all standard media/storage permissions appropriate for the current
  /// Android version.
  Future<bool> requestMediaPermissions() async {
    final results = await [
      Permission.photos,
      Permission.videos,
      Permission.storage,
    ].request();

    final photosGranted = results[Permission.photos]?.isGranted ?? false;
    final videosGranted = results[Permission.videos]?.isGranted ?? false;
    final storageGranted = results[Permission.storage]?.isGranted ?? false;
    final manageGranted = await Permission.manageExternalStorage.isGranted;

    return (photosGranted && videosGranted) || storageGranted || manageGranted;
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

  /// Check if basic media access is granted without prompting.
  Future<bool> hasMediaPermission() async {
    final photos  = await Permission.photos.isGranted;
    final videos  = await Permission.videos.isGranted;
    final storage = await Permission.storage.isGranted;
    final manage  = await Permission.manageExternalStorage.isGranted;
    return (photos && videos) || storage || manage;
  }

  /// Open app system settings so user can grant denied permissions.
  Future<void> openSettings() => openAppSettings();
}
