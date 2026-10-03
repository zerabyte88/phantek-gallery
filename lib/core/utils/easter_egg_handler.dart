import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/settings_model.dart';
import '../providers/settings_provider.dart';

/// Helper to handle 10-tap Easter Egg activation for AMOLED Sakura theme.
class EasterEggTapHandler {
  int _tapCount = 0;
  DateTime? _lastTap;

  void handleTap(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    if (_lastTap == null ||
        now.difference(_lastTap!) > const Duration(seconds: 2)) {
      _tapCount = 1;
    } else {
      _tapCount++;
    }
    _lastTap = now;

    final settings = ref.read(settingsNotifierProvider);
    if (!settings.isSakuraUnlocked) {
      if (_tapCount >= 10) {
        _tapCount = 0;
        ref.read(settingsNotifierProvider.notifier).update(
              (s) => s.copyWith(
                isSakuraUnlocked: true,
                themeMode: AppThemeMode.amoledSakura,
              ),
            );

        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF1A0A12),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFFF7597), width: 1.5),
              ),
              content: const Row(
                children: [
                  Text('🌸', style: TextStyle(fontSize: 26)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Easter Egg Unlocked!\nAMOLED Sakura Theme has been activated! 🌸',
                      style: TextStyle(
                        color: Color(0xFFFF85A1),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
      } else if (_tapCount >= 6) {
        final remaining = 10 - _tapCount;
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              duration: const Duration(milliseconds: 600),
              behavior: SnackBarBehavior.floating,
              content: Text('$remaining taps remaining to unlock a secret...'),
            ),
          );
      }
    } else {
      if (_tapCount >= 3) {
        _tapCount = 0;
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
              content: Text('🌸 AMOLED Sakura Theme is already active! 🌸'),
            ),
          );
      }
    }
  }
}
