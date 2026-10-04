import 'dart:io';
import 'package:flutter/services.dart';

/// Lightweight native Android sharing service via MethodChannel.
class ShareService {
  ShareService._();
  static const MethodChannel _channel = MethodChannel('com.phantek.gallery/share');

  /// Shares one or multiple media files using Android native share sheet.
  static Future<bool> shareFiles(
    List<String> paths, {
    String mimeType = '*/*',
  }) async {
    if (paths.isEmpty) return false;
    try {
      if (!Platform.isAndroid) return false;
      await _channel.invokeMethod('shareFiles', {
        'paths': paths,
        'mimeType': mimeType,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Convenience method to share a single media file.
  static Future<bool> shareSingle(String path, {bool isVideo = false}) {
    return shareFiles(
      [path],
      mimeType: isVideo ? 'video/*' : 'image/*',
    );
  }

  /// Opens Android native "Set as" (Wallpaper, Contact Photo, Lock Screen) via ACTION_ATTACH_DATA.
  static Future<bool> setAsWallpaper(String path, {String mimeType = 'image/*'}) async {
    try {
      if (!Platform.isAndroid) return false;
      await _channel.invokeMethod('setAsWallpaper', {
        'path': path,
        'mimeType': mimeType,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Triggers Android MediaScannerConnection to index new or updated files.
  static Future<void> scanFiles(List<String> paths) async {
    try {
      if (!Platform.isAndroid || paths.isEmpty) return;
      await _channel.invokeMethod('scanFile', {'paths': paths});
    } catch (_) {}
  }
}
