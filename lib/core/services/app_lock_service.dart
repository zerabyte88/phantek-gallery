import 'package:flutter/services.dart';

/// Biometric and device PIN/pattern authentication bridge via Android native channel.
class AppLockService {
  AppLockService._();
  static final AppLockService instance = AppLockService._();

  static const MethodChannel _channel =
      MethodChannel('com.phantek.gallery/app_lock');

  bool _promptActive = false;

  /// Whether a native biometric/PIN prompt is currently displayed.
  bool get isPromptActive => _promptActive;

  /// Returns true if the device has biometric or PIN/pattern lock configured.
  Future<bool> isDeviceAuthAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('canAuthenticate');
      return result == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Prompts the user to authenticate using device biometrics or PIN/pattern.
  Future<bool> authenticate({
    required String title,
    required String subtitle,
  }) async {
    if (_promptActive) return false;
    _promptActive = true;
    try {
      final result = await _channel.invokeMethod<bool>(
        'authenticate',
        {
          'title': title,
          'subtitle': subtitle,
        },
      );
      return result == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } finally {
      _promptActive = false;
    }
  }
}
