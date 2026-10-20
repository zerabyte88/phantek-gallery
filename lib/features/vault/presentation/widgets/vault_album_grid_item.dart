import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/router.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/providers/vault_provider.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/widgets/bouncy_tap.dart';

/// Specialized album tile for the Locked Vault shown at the top of the Albums tab.
class VaultAlbumGridItem extends ConsumerWidget {
  const VaultAlbumGridItem({super.key});

  Future<void> _onTap(BuildContext context) async {
    final canAuth = await AuthService.instance.canAuthenticate();
    if (!context.mounted) return;

    if (!canAuth) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.shield_outlined, color: Color(0xFFFFB74D)),
              const SizedBox(width: 8),
              Expanded(child: Text(context.tr.deviceLockRequired, style: const TextStyle(fontSize: 18))),
            ],
          ),
          content: Text(context.tr.deviceLockRequiredDesc),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(context.tr.ok),
            ),
          ],
        ),
      );
      return;
    }

    final reason = context.tr.authenticateToOpenVault;
    final success = await AuthService.instance.authenticate(
      localizedReason: reason,
    );

    if (success && context.mounted) {
      Navigator.of(context).openVault();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final vaultAsync = ref.watch(vaultProvider);
    final count = vaultAsync.value?.length ?? 0;

    return BouncyTap(
      scaleDown: 0.94,
      onTap: () => _onTap(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF262118),
                    Color(0xFF171512),
                  ],
                ),
                border: Border.all(
                  color: const Color(0xFFFFB74D).withValues(alpha: 0.25),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Subtle lock pattern background
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFFB74D).withValues(alpha: 0.1),
                        border: Border.all(
                          color: const Color(0xFFFFB74D).withValues(alpha: 0.2),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        size: 36,
                        color: Color(0xFFFFB74D),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fingerprint_rounded, size: 12, color: Color(0xFFFFB74D)),
                          SizedBox(width: 3),
                          Text(
                            'PIN',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFFB74D),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              context.tr.lockedVault,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                letterSpacing: 0.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 1),
            child: Text(
              context.tr.itemsCount(count),
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant.withValues(alpha: 0.75),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
