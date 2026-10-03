import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Bootstraps the media_kit / MPV engine.
///
/// Call [MediaKitSetup.init()] once inside [main()] before [runApp()].
class MediaKitSetup {
  MediaKitSetup._();

  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    _initialized = true;

    // Initialise media_kit – this wires up the native MPV/FFmpeg bridge.
    MediaKit.ensureInitialized();

    if (kDebugMode) {
      debugPrint('[MediaKit] Engine initialised.');
    }
  }
}
