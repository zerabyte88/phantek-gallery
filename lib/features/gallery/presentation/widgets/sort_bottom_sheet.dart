import 'package:flutter/material.dart';
import '../../../../core/enums/sort_option.dart';

/// Modal bottom sheet for selecting media sorting criteria and direction.
/// Matches Image 2 layout with radio indicators, custom direction pills on ALL options,
/// and "Restore defaults" action.
class SortBottomSheet extends StatefulWidget {
  const SortBottomSheet({
    super.key,
    required this.currentSort,
    required this.onSortChanged,
  });

  final SortOption currentSort;
  final ValueChanged<SortOption> onSortChanged;

  @override
  State<SortBottomSheet> createState() => _SortBottomSheetState();
}

class _SortBottomSheetState extends State<SortBottomSheet> {
  late SortCriterion _criterion;
  late Map<SortCriterion, SortDirection> _directions;

  @override
  void initState() {
    super.initState();
    _criterion = widget.currentSort.criterion;
    _directions = {
      SortCriterion.shootingTime: SortDirection.descending,
      SortCriterion.timeAdded: SortDirection.descending,
      SortCriterion.name: SortDirection.ascending,
      SortCriterion.size: SortDirection.descending,
    };
    // Initialize active criterion with the current sort direction
    _directions[_criterion] = widget.currentSort.direction;
  }

  void _update(SortCriterion criterion, SortDirection direction) {
    setState(() {
      _criterion = criterion;
      _directions[criterion] = direction;
    });
    final newOption =
        SortOption.fromCriterionAndDirection(criterion, direction);
    widget.onSortChanged(newOption);
  }

  void _toggleDirection(SortCriterion criterion) {
    final current = _directions[criterion] ?? criterion.defaultDirection;
    _update(criterion, current.toggled);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = theme.dialogTheme.backgroundColor ??
        (isDark
            ? (theme.scaffoldBackgroundColor == Colors.black
                ? const Color(0xFF161616)
                : const Color(0xFF222222))
            : cs.surface);
    final accentColor = cs.primary;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Header: Title "Sort" & Close button "X"
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
              child: Row(
                children: [
                  const SizedBox(width: 36),
                  const Expanded(
                    child: Text(
                      'Sort',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // Criteria Options (All 4 options have their direction button & subtitle)
            ...SortCriterion.values.map((c) {
              final isSelected = _criterion == c;
              final currentDirection = _directions[c] ?? c.defaultDirection;
              final isAscending = currentDirection == SortDirection.ascending;

              return InkWell(
                onTap: () {
                  if (isSelected) {
                    _toggleDirection(c);
                  } else {
                    _update(c, currentDirection);
                  }
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      // Radio circle indicator
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? accentColor
                                : (isDark ? Colors.white38 : Colors.black38),
                            width: isSelected ? 4 : 2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Label + Subtitle
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              c.label,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              c.directionLabel(currentDirection),
                              style: TextStyle(
                                fontSize: 13,
                                color: isSelected
                                    ? (isDark ? Colors.white70 : Colors.black87)
                                    : (isDark ? Colors.white38 : Colors.black45),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Right direction toggle pill (always present on all options)
                      Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDark
                                  ? Colors.white.withValues(alpha: 0.14)
                                  : Colors.black.withValues(alpha: 0.08))
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.04)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Ascending (↑)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _update(c, SortDirection.ascending),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isAscending
                                      ? (isDark
                                          ? Colors.white.withValues(alpha: 0.28)
                                          : Colors.black.withValues(alpha: 0.18))
                                      : Colors.transparent,
                                ),
                                child: Icon(
                                  Icons.arrow_upward,
                                  size: 16,
                                  color: isAscending
                                      ? (isDark ? Colors.white : Colors.black)
                                      : (isDark ? Colors.white38 : Colors.black38),
                                ),
                              ),
                            ),

                            // Descending (↓)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _update(c, SortDirection.descending),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: !isAscending
                                      ? (isDark
                                          ? Colors.white.withValues(alpha: 0.28)
                                          : Colors.black.withValues(alpha: 0.18))
                                      : Colors.transparent,
                                ),
                                child: Icon(
                                  Icons.arrow_downward,
                                  size: 16,
                                  color: !isAscending
                                      ? (isDark ? Colors.white : Colors.black)
                                      : (isDark ? Colors.white38 : Colors.black38),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 8),

            // Bottom action: "Restore defaults"
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 20),
              child: Center(
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: accentColor,
                  ),
                  onPressed: () {
                    setState(() {
                      _directions = {
                        SortCriterion.shootingTime: SortDirection.descending,
                        SortCriterion.timeAdded: SortDirection.descending,
                        SortCriterion.name: SortDirection.ascending,
                        SortCriterion.size: SortDirection.descending,
                      };
                    });
                    _update(SortCriterion.timeAdded, SortDirection.descending);
                  },
                  child: Text(
                    'Restore defaults',
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper to display the SortBottomSheet.
Future<void> showSortBottomSheet(
  BuildContext context, {
  required SortOption currentSort,
  required ValueChanged<SortOption> onSortChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SortBottomSheet(
      currentSort: currentSort,
      onSortChanged: onSortChanged,
    ),
  );
}
