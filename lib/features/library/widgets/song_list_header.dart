import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../data/models/sort_field.dart';
import '../../../providers/library_providers.dart';

class SongListHeader extends ConsumerWidget {
  final int count;
  const SongListHeader({super.key, required this.count});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final state = ref.watch(libraryNotifierProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '$count música${count == 1 ? '' : 's'}',
            style: TextStyle(color: palette.textSecondary, fontSize: 13),
          ),
          Text('Ordenar por',
              style: TextStyle(color: palette.textSecondary, fontSize: 13)),
          DropdownButtonHideUnderline(
            child: DropdownButton<SortField>(
              value: state.sortField,
              dropdownColor: palette.surfaceVariant,
              style: TextStyle(color: palette.textPrimary, fontSize: 13),
              items: SortField.values
                  .map((f) => DropdownMenuItem(value: f, child: Text(f.label)))
                  .toList(),
              onChanged: (field) {
                if (field != null) {
                  ref.read(libraryNotifierProvider.notifier).setSort(field);
                }
              },
            ),
          ),
          IconButton(
            icon: Icon(
              state.sortAscending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 18,
              color: palette.textSecondary,
            ),
            onPressed: () =>
                ref.read(libraryNotifierProvider.notifier).setSort(state.sortField),
          ),
        ],
      ),
    );
  }
}
