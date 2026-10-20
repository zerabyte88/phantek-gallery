import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows a floating feedback pill notification matching the video player's
/// loop/speed pill style, positioned safely above footers and bottom bars.
void showFeedbackPill(
  BuildContext context, {
  required String message,
  required IconData icon,
  double? bottomOffset,
}) {
  FeedbackPill.show(
    context,
    message: message,
    icon: icon,
    bottomOffset: bottomOffset,
  );
}

class FeedbackPill {
  static OverlayEntry? _entry;
  static Timer? _timer;
  static GlobalKey<_FeedbackPillOverlayState>? _pillKey;

  static void show(
    BuildContext context, {
    required String message,
    required IconData icon,
    double? bottomOffset,
  }) {
    HapticFeedback.lightImpact();

    if (_entry != null && _pillKey?.currentState != null) {
      _timer?.cancel();
      _pillKey!.currentState!.update(
        message: message,
        icon: icon,
        bottomOffset: bottomOffset,
      );
      _timer = Timer(const Duration(milliseconds: 1350), () {
        dismiss();
      });
      return;
    }

    _timer?.cancel();
    _entry?.remove();
    _entry = null;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _pillKey = GlobalKey<_FeedbackPillOverlayState>();
    final entry = OverlayEntry(
      builder: (ctx) => _FeedbackPillWidget(
        key: _pillKey,
        initialMessage: message,
        initialIcon: icon,
        initialBottomOffset: bottomOffset,
        onDismissed: () {
          _entry?.remove();
          _entry = null;
          _pillKey = null;
        },
      ),
    );

    _entry = entry;
    overlay.insert(entry);

    _timer = Timer(const Duration(milliseconds: 1350), () {
      dismiss();
    });
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _pillKey?.currentState?.hide();
  }
}

class _FeedbackPillWidget extends StatefulWidget {
  const _FeedbackPillWidget({
    super.key,
    required this.initialMessage,
    required this.initialIcon,
    this.initialBottomOffset,
    required this.onDismissed,
  });

  final String initialMessage;
  final IconData initialIcon;
  final double? initialBottomOffset;
  final VoidCallback onDismissed;

  @override
  State<_FeedbackPillWidget> createState() => _FeedbackPillOverlayState();
}

class _FeedbackPillOverlayState extends State<_FeedbackPillWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late String _message;
  late IconData _icon;
  double? _bottomOffset;

  @override
  void initState() {
    super.initState();
    _message = widget.initialMessage;
    _icon = widget.initialIcon;
    _bottomOffset = widget.initialBottomOffset;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _animController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        widget.onDismissed();
      }
    });
    _animController.forward();
  }

  void update({
    required String message,
    required IconData icon,
    double? bottomOffset,
  }) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _icon = icon;
      _bottomOffset = bottomOffset;
    });
    if (!_animController.isAnimating && !_animController.isCompleted) {
      _animController.forward();
    }
  }

  void hide() {
    if (mounted) {
      _animController.reverse();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final bottomPos = _bottomOffset ??
        (isLandscape ? (bottomInset + 84.0) : (bottomInset + 100.0));

    return Positioned(
      bottom: bottomPos,
      left: 20,
      right: 20,
      child: Material(
        type: MaterialType.transparency,
        child: IgnorePointer(
          child: Align(
            alignment: Alignment.center,
            child: FadeTransition(
              opacity: _animController.drive(
                CurveTween(curve: Curves.easeOut),
              ),
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.2),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: _animController,
                    curve: Curves.easeOutCubic,
                  ),
                ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xEE1E1E1E),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                      width: 0.8,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x44000000),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _icon,
                        size: 18,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          _message,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
