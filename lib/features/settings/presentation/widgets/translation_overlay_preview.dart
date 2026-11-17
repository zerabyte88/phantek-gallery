import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/services/translation/translation_models.dart';
import '../../../player/presentation/widgets/manga_translation_overlay.dart';

/// Live side-by-side JP -> EN comic panel mockup previewing [overlayStyle] and [fontScale].
class TranslationOverlayPreview extends StatelessWidget {
  const TranslationOverlayPreview({
    super.key,
    required this.fontScale,
    required this.overlayStyle,
  });

  final double fontScale;
  final TranslationOverlayStyle overlayStyle;

  static const Size _panelSize = Size(200, 260);

  static const TranslationResult _mockResult = TranslationResult(
    imagePath: 'preview://mockup_panel',
    imageSize: _panelSize,
    blocks: [
      MangaTranslatedBlock(
        boundingBox: Rect.fromLTWH(20, 18, 152, 92),
        originalText: 'おはよう！\n今日もいい天気だね！',
        translatedText: 'Good morning! The weather is so nice today!',
        isSpeechBubble: true,
      ),
      MangaTranslatedBlock(
        boundingBox: Rect.fromLTWH(78, 192, 104, 42),
        originalText: 'ドキッ',
        translatedText: 'THUMP!',
        isSpeechBubble: false,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _PreviewPanelCard(
            badge: context.tr.overlayOriginalBadge,
            badgeColor: cs.secondaryContainer,
            badgeTextColor: cs.onSecondaryContainer,
            child: const Stack(
              fit: StackFit.expand,
              children: [
                _MockMangaArtwork(),
                _JapaneseSourceOverlay(),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(
            Icons.arrow_forward_rounded,
            size: 18,
            color: cs.primary,
          ),
        ),
        Expanded(
          child: _PreviewPanelCard(
            badge: context.tr.overlayTranslatedBadge,
            badgeColor: cs.primaryContainer,
            badgeTextColor: cs.onPrimaryContainer,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const _MockMangaArtwork(),
                Positioned.fill(
                  child: MangaTranslationOverlay(
                    result: _mockResult,
                    mode: TranslationRenderMode.fullImageWithSfx,
                    fontScale: fontScale,
                    overlayStyle: overlayStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewPanelCard extends StatelessWidget {
  const _PreviewPanelCard({
    required this.badge,
    required this.badgeColor,
    required this.badgeTextColor,
    required this.child,
  });

  final String badge;
  final Color badgeColor;
  final Color badgeTextColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            badge,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: badgeTextColor,
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 200 / 260,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5),
                width: 1.2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
      ],
    );
  }
}

class _MockMangaArtwork extends StatelessWidget {
  const _MockMangaArtwork();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MockMangaArtworkPainter(),
    );
  }
}

class _MockMangaArtworkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Crisp monochrome manga page backdrop with speed lines and silhouette frame.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF3F4F6),
    );

    final double sx = size.width / 200.0;
    final double sy = size.height / 260.0;

    // Inner comic panel border
    final panelRect = Rect.fromLTWH(8 * sx, 8 * sy, 184 * sx, 244 * sy);
    canvas.drawRect(
      panelRect,
      Paint()..color = const Color(0xFFE5E7EB),
    );
    canvas.drawRect(
      panelRect,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Manga screentone/speed lines
    final linePaint = Paint()
      ..color = const Color(0xFF9CA3AF).withValues(alpha: 0.45)
      ..strokeWidth = 1.0;
    for (int i = 0; i < 10; i++) {
      final y = (120 + i * 12) * sy;
      canvas.drawLine(
        Offset(10 * sx, y),
        Offset(190 * sx, y - 16 * sy),
        linePaint,
      );
    }

    // Stylized character shoulder/head silhouette in lower-left
    final silhouettePaint = Paint()..color = const Color(0xFF374151);
    canvas.drawCircle(
      Offset(56 * sx, 165 * sy),
      22 * mathMin(sx, sy),
      silhouettePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(24 * sx, 188 * sy, 64 * sx, 64 * sy),
        Radius.circular(18 * sx),
      ),
      silhouettePaint,
    );

    // Speech bubble outline
    final bubbleRect = Rect.fromLTWH(20 * sx, 18 * sy, 152 * sx, 92 * sy);
    final bubbleRRect =
        RRect.fromRectAndRadius(bubbleRect, Radius.circular(16 * sx));
    canvas.drawRRect(bubbleRRect, Paint()..color = Colors.white);
    canvas.drawRRect(
      bubbleRRect,
      Paint()
        ..color = const Color(0xFF111827)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  double mathMin(double a, double b) => a < b ? a : b;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _JapaneseSourceOverlay extends StatelessWidget {
  const _JapaneseSourceOverlay();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sx = constraints.maxWidth / 200.0;
        final sy = constraints.maxHeight / 260.0;
        return Stack(
          children: [
            Positioned(
              left: 24 * sx,
              top: 24 * sy,
              width: 144 * sx,
              height: 80 * sy,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'おはよう！\n今日もいい天気だね！',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12 * sx.clamp(0.6, 1.4),
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF111827),
                    height: 1.25,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 78 * sx,
              top: 192 * sy,
              width: 104 * sx,
              height: 42 * sy,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'ドキッ',
                    style: TextStyle(
                      fontSize: 16 * sx.clamp(0.7, 1.5),
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF111827),
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
