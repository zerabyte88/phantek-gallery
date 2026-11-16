import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Placement hint for [StyledMoreMenuButton] to position its popup cleanly
/// relative to either a top AppBar or a bottom control bar.
enum StyledMenuPlacement {
  topBar,
  bottomBar,
}

/// Action descriptor rendered inside [StyledMoreMenuButton].
class StyledMenuAction<T> {
  const StyledMenuAction({
    required this.value,
    required this.icon,
    required this.label,
    this.color,
    this.isDestructive = false,
    this.isActive = false,
  });

  final T value;
  final IconData icon;
  final String label;
  final Color? color;
  final bool isDestructive;
  final bool isActive;
}

/// Shared 3-dot ("more") popup menu button with consistent surface, hairline
/// border, compact content-hugging rows, and bar-aware placement.
class StyledMoreMenuButton<T> extends StatelessWidget {
  const StyledMoreMenuButton({
    super.key,
    required this.actions,
    required this.onSelected,
    this.tooltip,
    this.icon,
    this.child,
    this.splashRadius,
    this.placement = StyledMenuPlacement.topBar,
    this.forceDark = false,
  }) : assert(
          icon == null || child == null,
          'Cannot specify both icon and child on StyledMoreMenuButton.',
        );

  final List<StyledMenuAction<T>> actions;
  final ValueChanged<T> onSelected;
  final String? tooltip;
  final Widget? icon;
  final Widget? child;
  final double? splashRadius;
  final StyledMenuPlacement placement;
  final bool forceDark;

  static const double _itemHeight = 40.0;
  static const double _menuVerticalPadding = 6.0;

  @override
  Widget build(BuildContext context) {
    if (icon != null) {
      return IconButton(
        icon: icon!,
        tooltip: tooltip,
        splashRadius: splashRadius,
        onPressed: () => _openMenu(context),
      );
    }

    final Widget inkWell = InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _openMenu(context),
      child: child ?? const Icon(Icons.more_vert),
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(
        message: tooltip!,
        child: inkWell,
      );
    }

    return inkWell;
  }

  Future<void> _openMenu(BuildContext context) async {
    final navigator = Navigator.of(context);
    final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
    final button = context.findRenderObject()! as RenderBox;
    final anchorTopLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
    final anchorRect = anchorTopLeft & button.size;

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = forceDark || theme.brightness == Brightness.dark;

    final backgroundColor =
        isDark ? const Color(0xFF1D1F24) : colorScheme.surfaceContainerHigh;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : colorScheme.outlineVariant;
    final defaultFg = isDark ? Colors.white : colorScheme.onSurface;

    final result = await navigator.push<T>(
      _StyledPopupMenuRoute<T>(
        anchorRect: anchorRect,
        placement: placement,
        actions: actions,
        backgroundColor: backgroundColor,
        borderColor: borderColor,
        defaultFg: defaultFg,
        activeColor: colorScheme.primary,
        barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      ),
    );

    if (result != null) {
      onSelected(result);
    }
  }
}

class _StyledPopupMenuRoute<T> extends PopupRoute<T> {
  _StyledPopupMenuRoute({
    required this.anchorRect,
    required this.placement,
    required this.actions,
    required this.backgroundColor,
    required this.borderColor,
    required this.defaultFg,
    required this.activeColor,
    required this.barrierLabel,
  });

  final Rect anchorRect;
  final StyledMenuPlacement placement;
  final List<StyledMenuAction<T>> actions;
  final Color backgroundColor;
  final Color borderColor;
  final Color defaultFg;
  final Color activeColor;

  @override
  final String? barrierLabel;

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => null;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 160);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    final menuCard = Material(
      color: backgroundColor,
      elevation: 10,
      shadowColor: Colors.black54,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor, width: 0.9),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 144, maxWidth: 232),
        child: IntrinsicWidth(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: StyledMoreMenuButton._menuVerticalPadding,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < actions.length; i++) ...[
                  _buildMenuItem(context, actions[i]),
                  if (i < actions.length - 1)
                    Container(
                      height: 1.0,
                      color: borderColor,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    final isTopBar = placement == StyledMenuPlacement.topBar;

    return CustomSingleChildLayout(
      delegate: _StyledMenuLayoutDelegate(
        anchorRect: anchorRect,
        placement: placement,
      ),
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: isTopBar ? const Offset(0, -0.2) : const Offset(0, 0.2),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            alignment: isTopBar ? Alignment.topRight : Alignment.bottomRight,
            child: menuCard,
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext routeContext,
    StyledMenuAction<T> action,
  ) {
    final Color fg = action.color ??
        (action.isDestructive
            ? Colors.redAccent
            : (action.isActive ? activeColor : defaultFg));

    return InkWell(
      onTap: () => Navigator.of(routeContext).pop(action.value),
      child: SizedBox(
        height: StyledMoreMenuButton._itemHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                child: Center(
                  child: Icon(action.icon, size: 18, color: fg),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 1,
                height: 16,
                color: borderColor,
              ),
              const SizedBox(width: 10),
              Flexible(
                fit: FlexFit.loose,
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StyledMenuLayoutDelegate extends SingleChildLayoutDelegate {
  _StyledMenuLayoutDelegate({
    required this.anchorRect,
    required this.placement,
  });

  final Rect anchorRect;
  final StyledMenuPlacement placement;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return constraints.loosen();
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double maxLeft = math.max(8.0, size.width - childSize.width - 8.0);
    final double left =
        (anchorRect.right - childSize.width).clamp(8.0, maxLeft);

    final double maxTop = math.max(8.0, size.height - childSize.height - 8.0);
    final double rawTop = placement == StyledMenuPlacement.topBar
        ? anchorRect.bottom + 6.0
        : anchorRect.top - childSize.height - 8.0;
    final double top = rawTop.clamp(8.0, maxTop);

    return Offset(left, top);
  }

  @override
  bool shouldRelayout(covariant _StyledMenuLayoutDelegate oldDelegate) {
    return anchorRect != oldDelegate.anchorRect ||
        placement != oldDelegate.placement;
  }
}
