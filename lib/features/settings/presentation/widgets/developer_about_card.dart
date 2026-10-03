import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/models/settings_model.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/widgets/bouncy_tap.dart';

/// Developer & About card placed at the bottom of the Settings screen.
/// Includes Easter Egg: tapping developer avatar 10 times unlocks AMOLED Sakura theme.
class DeveloperAboutCard extends ConsumerStatefulWidget {
  const DeveloperAboutCard({super.key});

  @override
  ConsumerState<DeveloperAboutCard> createState() => _DeveloperAboutCardState();
}

class _DeveloperAboutCardState extends ConsumerState<DeveloperAboutCard> {
  int _tapCount = 0;
  DateTime? _lastTap;

  static const _cyan = Color(0xFF00C7D7);
  static const _githubRepoUrl = 'https://github.com/zerabyte88/phantek-gallery';
  static const _githubProfileUrl = 'https://github.com/zerabyte88';

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not open $url: $e');
    }
  }

  void _onAvatarTap() {
    final now = DateTime.now();
    if (_lastTap == null || now.difference(_lastTap!) > const Duration(seconds: 2)) {
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

        if (!mounted) return;
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
        if (!mounted) return;
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
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
              content: Text('🌸 Developer: zerabyte88 (Creator & Maintainer)'),
            ),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF131518),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: About Phantek + Version Badge ───────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.info_outline,
                color: _cyan,
                size: 22,
              ),
              const SizedBox(width: 10),
              const Text(
                'About Phantek',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF00382B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.6),
                    width: 1,
                  ),
                ),
                child: const Text(
                  'v1.1.1',
                  style: TextStyle(
                    color: Color(0xFF00E676),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Offline Gallery & Media Player',
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),

          // ── Key-Value Information Rows ──────────────────────────
          _buildInfoRow('App Version', 'v1.1.1'),
          const SizedBox(height: 10),
          _buildInfoRow('Build', '11003 (Release APK)'),
          const SizedBox(height: 10),
          _buildInfoRow('Architecture', 'ARM64-v8a (MediaKit)'),
          const SizedBox(height: 10),
          _buildInfoRow('License', 'GPLv3'),
          const SizedBox(height: 22),

          // ── Developer Profile Row ───────────────────────────────
          Row(
            children: [
              // Avatar with glowing cyan circular border + Easter Egg onTap
              GestureDetector(
                key: const ValueKey('developer_avatar_easter_egg'),
                onTap: _onAvatarTap,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _cyan, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: _cyan.withValues(alpha: 0.4),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.network(
                      'https://github.com/zerabyte88.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Image.asset(
                        'assets/developer_avatar.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Developer: zerabyte88',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Creator & Maintainer',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.open_in_new,
                  color: _cyan,
                  size: 20,
                ),
                tooltip: 'Open GitHub Profile',
                onPressed: () => _openUrl(_githubProfileUrl),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── Bottom Action Button: View Repository on GitHub ─────
          BouncyTap(
            onTap: () => _openUrl(_githubRepoUrl),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: () => _openUrl(_githubRepoUrl),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFF16191D),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.open_in_new,
                      color: _cyan,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'View Repository on GitHub',
                      style: TextStyle(
                        color: _cyan,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
