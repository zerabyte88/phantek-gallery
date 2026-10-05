import 'package:flutter/services.dart';

/// Thin service to keep the device screen on during media playback/viewing.
/// Uses native Android WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON.
class ScreenKeeperService {
  ScreenKeeperService._();

  static const _channel = MethodChannel('com.phantek.gallery/screen_keeper');

  /// Toggles the screen keep-on flag on the native window.
  static Future<void> setKeepScreenOn(bool keepOn) async {
    try {
      if (keepOn) {
        await _channel.invokeMethod('keepOn');
      } else {
        await _channel.invokeMethod('clearKeepOn');
      }
    } catch (_) {}
  }
}
