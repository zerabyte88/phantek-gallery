import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Service handling device biometric and screen-lock (PIN/Pattern/Password) authentication.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final LocalAuthentication _auth = LocalAuthentication();

  /// Checks whether the device supports biometric or device-credential security.
  Future<bool> canAuthenticate() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } on PlatformException {
      return false;
    }
  }

  /// Prompts the user with the system biometric / device credential dialog.
  ///
  /// Returns `true` if authentication succeeded, `false` otherwise.
  Future<bool> authenticate({required String localizedReason}) async {
    try {
      final isAvailable = await canAuthenticate();
      if (!isAvailable) {
        return false;
      }

      return await _auth.authenticate(
        localizedReason: localizedReason,
        persistAcrossBackgrounding: true,
        biometricOnly: false,
      );
    } on LocalAuthException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Cancels any in-flight authentication if necessary.
  Future<void> stopAuthentication() async {
    try {
      await _auth.stopAuthentication();
    } catch (_) {}
  }
}
