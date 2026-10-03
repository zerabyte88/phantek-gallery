import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/enums/filter_option.dart';
import '../../../../core/enums/sort_option.dart';
import '../../../../core/providers/settings_provider.dart';

/// Row showing centered enlarged filter chips + compact 3-dots sort popup menu.
class FilterSortBar extends ConsumerWidget {
  const FilterSortBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: 48,
      child: Row(
        children: [
          // Left spacer matching the width of the 3-dots button to ensure true centering
          const SizedBox(width: 48),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: FilterOption.values.map((f) {
                    final selected = settings.defaultFilter == f;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        label: Text(f.label),
                        selected: selected,
                        onSelected: (_) => ref
                            .read(settingsNotifierProvider.notifier)
                            .update((s) => s.copyWith(defaultFilter: f)),
                        showCheckmark: false,
                        selectedColor: cs.primaryContainer,
                        labelStyle: TextStyle(
                          color: selected ? cs.onPrimaryContainer : cs.onSurface,
                          fontSize: 14,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: PopupMenuButton<SortOption>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Sort options',
              initialValue: settings.defaultSort,
              onSelected: (s) {
                ref
                    .read(settingsNotifierProvider.notifier)
                    .update((st) => st.copyWith(defaultSort: s));
              },
              itemBuilder: (context) => SortOption.values
                  .map(
                    (s) => CheckedPopupMenuItem<SortOption>(
                      value: s,
                      checked: settings.defaultSort == s,
                      child: Text(s.label),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
