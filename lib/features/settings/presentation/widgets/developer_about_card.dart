import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/widgets/bouncy_tap.dart';

/// Developer & About card placed at the bottom of the Settings screen.
class DeveloperAboutCard extends StatelessWidget {
  const DeveloperAboutCard({super.key});

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
                  'v1.1.2',
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
          _buildInfoRow('App Version', 'v1.1.2'),
          const SizedBox(height: 10),
          _buildInfoRow('Build', '11004 (Release APK)'),
          const SizedBox(height: 10),
          _buildInfoRow('Architecture', 'ARM64-v8a (MediaKit)'),
          const SizedBox(height: 10),
          _buildInfoRow('License', 'GPLv3'),
          const SizedBox(height: 22),

          // ── Developer Profile Row ───────────────────────────────
          Row(
            children: [
              // Avatar with glowing cyan circular border
              BouncyTap(
                key: const ValueKey('developer_avatar'),
                onTap: () => _openUrl(_githubProfileUrl),
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
