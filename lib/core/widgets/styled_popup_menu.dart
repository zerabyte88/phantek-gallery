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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = forceDark || theme.brightness == Brightness.dark;

    final backgroundColor =
        isDark ? const Color(0xFF1D1F24) : colorScheme.surfaceContainerHigh;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : colorScheme.outlineVariant;
    final defaultFg = isDark ? Colors.white : colorScheme.onSurface;

    final int dividerCount = actions.length > 1 ? actions.length - 1 : 0;
    final double estimatedHeight =
        actions.length * _itemHeight + dividerCount + (_menuVerticalPadding * 2);
    final PopupMenuPosition menuPosition = placement == StyledMenuPlacement.topBar
        ? PopupMenuPosition.under
        : PopupMenuPosition.over;
    final Offset menuOffset = placement == StyledMenuPlacement.topBar
        ? const Offset(0, 6)
        : Offset(0, -(estimatedHeight + 8.0));

    return PopupMenuButton<T>(
      splashRadius: splashRadius,
      tooltip: tooltip,
      color: backgroundColor,
      elevation: 10,
      shadowColor: Colors.black54,
      menuPadding: const EdgeInsets.symmetric(vertical: _menuVerticalPadding),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor, width: 0.9),
      ),
      constraints: const BoxConstraints(minWidth: 144, maxWidth: 232),
      position: menuPosition,
      offset: menuOffset,
      icon: icon,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (int i = 0; i < actions.length; i++) ...[
          _buildMenuItem(actions[i], colorScheme, defaultFg, borderColor),
          if (i < actions.length - 1) _StyledMenuDivider<T>(color: borderColor),
        ],
      ],
      child: child,
    );
  }

  PopupMenuItem<T> _buildMenuItem(
    StyledMenuAction<T> action,
    ColorScheme colorScheme,
    Color defaultFg,
    Color dividerColor,
  ) {
    final Color fg = action.color ??
        (action.isDestructive
            ? Colors.redAccent
            : (action.isActive ? colorScheme.primary : defaultFg));

    return PopupMenuItem<T>(
      value: action.value,
      height: _itemHeight,
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
            color: dividerColor,
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
    );
  }
}

class _StyledMenuDivider<T> extends PopupMenuEntry<T> {
  const _StyledMenuDivider({required this.color});

  final Color color;

  @override
  double get height => 1.0;

  @override
  bool represents(T? value) => false;

  @override
  State<_StyledMenuDivider<T>> createState() => _StyledMenuDividerState<T>();
}

class _StyledMenuDividerState<T> extends State<_StyledMenuDivider<T>> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1.0,
      color: widget.color,
    );
  }
}
