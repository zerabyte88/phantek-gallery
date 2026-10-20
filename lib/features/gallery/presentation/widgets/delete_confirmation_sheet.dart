import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';

Future<bool> showDeleteConfirmationSheet(
  BuildContext context, {
  required String title,
  required String contentText,
  required bool isTrash,
  String? actionLabel,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final btnLabel =
          actionLabel ?? (isTrash ? context.tr.moveToTrash : context.tr.delete);
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (contentText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                contentText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      isTrash ? cs.primary : const Color(0xFFF03D3D),
                  foregroundColor: isTrash ? cs.onPrimary : Colors.white,
                  shape: const StadiumBorder(),
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  btnLabel,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                style: TextButton.styleFrom(
                  shape: const StadiumBorder(),
                ),
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  context.tr.cancel,
                  style: TextStyle(
                    fontSize: 15,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  return result ?? false;
}
