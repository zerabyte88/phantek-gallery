import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/enums/filter_option.dart';
import '../../../../core/enums/sort_option.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/widgets/bouncy_tap.dart';
import 'sort_bottom_sheet.dart';

/// Clean, responsive filter bar with fixed chips + sort bar from screenshot.
/// Fully visible without scrolling or clipping on any screen width.
/// Can be used in main gallery (with Albums tab) or inside an album (without Albums tab).
class FilterSortBar extends ConsumerWidget {
  const FilterSortBar({
    super.key,
    this.isAlbumDetail = false,
    this.currentFilter,
    this.onFilterChanged,
    this.currentSort,
    this.onSortChanged,
  });

  final bool isAlbumDetail;
  final FilterOption? currentFilter;
  final ValueChanged<FilterOption>? onFilterChanged;
  final SortOption? currentSort;
  final ValueChanged<SortOption>? onSortChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final cs = Theme.of(context).colorScheme;

    final activeFilter = currentFilter ?? settings.defaultFilter;
    final activeSort = currentSort ?? settings.defaultSort;

    final options = isAlbumDetail
        ? [
            FilterOption.all,
            FilterOption.photosOnly,
            FilterOption.videosOnly,
          ]
        : FilterOption.values;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 1. Filter Chips Row (Cleanly Centered) ──────────────────────────
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: options.map((f) {
                final selected = activeFilter == f;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: BouncyTap(
                    scaleDown: 0.94,
                    child: Material(
                      color: selected
                          ? cs.primaryContainer
                          : cs.surfaceContainerHighest.withValues(alpha: 0.35),
                      shape: const StadiumBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: () {
                          if (onFilterChanged != null) {
                            onFilterChanged!(f);
                          } else {
                            ref
                                .read(settingsNotifierProvider.notifier)
                                .update((s) => s.copyWith(defaultFilter: f));
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          constraints: const BoxConstraints(minWidth: 72),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: ShapeDecoration(
                            shape: StadiumBorder(
                              side: BorderSide(
                                color: selected
                                    ? cs.primary.withValues(alpha: 0.3)
                                    : cs.outline.withValues(alpha: 0.2),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Text(
                            f.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: selected
                                  ? cs.onPrimaryContainer
                                  : cs.onSurface,
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // ── 2. Sort Bar Row (matching screenshot layout) ────────────────────
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              showSortBottomSheet(
                context,
                currentSort: activeSort,
                onSortChanged: (s) {
                  if (onSortChanged != null) {
                    onSortChanged!(s);
                  } else {
                    ref
                        .read(settingsNotifierProvider.notifier)
                        .update((st) => st.copyWith(defaultSort: s));
                  }
                },
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    activeSort.direction == SortDirection.ascending
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    size: 16,
                    color: cs.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    activeSort.barLabel,
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurface,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
