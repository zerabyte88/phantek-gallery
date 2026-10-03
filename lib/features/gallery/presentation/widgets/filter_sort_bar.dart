import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/enums/filter_option.dart';
import '../../../../core/enums/sort_option.dart';
import '../../../../core/providers/settings_provider.dart';

/// Compact row showing filter chips + sort dropdown.
class FilterSortBar extends ConsumerWidget {
  const FilterSortBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: FilterOption.values.map((f) {
                final selected = settings.defaultFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
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
                      fontSize: 13,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<SortOption>(
                value: settings.defaultSort,
                icon: const Icon(Icons.sort, size: 18),
                isDense: true,
                borderRadius: BorderRadius.circular(12),
                items: SortOption.values
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s.label, style: const TextStyle(fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (s) {
                  if (s == null) return;
                  ref
                      .read(settingsNotifierProvider.notifier)
                      .update((st) => st.copyWith(defaultSort: s));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
