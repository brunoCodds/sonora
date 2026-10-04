import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_palette.dart';
import '../data/models/song.dart';
import '../providers/library_providers.dart';
import 'app_icon_button.dart';

/// Coração de favoritar, usado tanto na `PlayerBar` do app completo
/// quanto no `MiniPlayerScreen` — um widget só, pra manter os dois
/// lugares sincronizados sem duplicar a lógica de alternar.
class FavoriteButton extends ConsumerWidget {
  final Song song;
  final double size;

  const FavoriteButton({super.key, required this.song, this.size = 20});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return AppIconButton(
      icon: song.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      tooltip: song.isFavorite ? 'Remover dos favoritos' : 'Favoritar',
      active: song.isFavorite,
      activeColor: palette.favorite,
      size: size,
      onPressed: () => ref.read(libraryNotifierProvider.notifier).toggleFavorite(song),
    );
  }
}
