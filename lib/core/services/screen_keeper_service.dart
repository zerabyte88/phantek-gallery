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

  /// Toggles maximum brightness override for media viewing.
  static Future<void> setMaxBrightness(bool max) async {
    try {
      if (max) {
        await _channel.invokeMethod('setMaxBrightness');
      } else {
        await _channel.invokeMethod('restoreBrightness');
      }
    } catch (_) {}
  }

  /// Toggles FLAG_SECURE on the native Android window to prevent screenshots and screen recordings.
  static Future<void> setSecure(bool secure) async {
    try {
      await _channel.invokeMethod('setSecure', {'enabled': secure});
    } catch (_) {}
  }
}
