import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../providers/audio_providers.dart';
import '../../providers/favorites_providers.dart';
import '../../shared_widgets/empty_state.dart';
import '../library/widgets/song_tile.dart';

/// Aba Favoritos: mostra todas as músicas favoritadas, separadas em
/// duas seções — as que estão na biblioteca local ("de verdade" no
/// disco) e as que só existem na web (podem ou não já ter sido
/// baixadas via o botão de instalar no player, ver `DownloadButton`).
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesNotifierProvider);
    final notifier = ref.read(favoritesNotifierProvider.notifier);
    final queueState = ref.watch(queueControllerProvider);
    final isPlaying = ref.watch(playerPlayingProvider).value ?? false;

    final local = notifier.localFavorites;
    final web = notifier.webFavorites;

    if (favorites.isEmpty) {
      return const EmptyState(
        icon: Icons.favorite_border_rounded,
        title: 'Nenhum favorito ainda',
        message:
            'Toque no coração de uma música — da sua biblioteca ou de uma '
            'busca na web — para ela aparecer aqui.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Favoritos',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ),
        if (local.isNotEmpty) ...[
          _SectionHeader('Na sua biblioteca', count: local.length),
          for (var i = 0; i < local.length; i++)
            SongTile(
              song: local[i],
              index: i,
              contextList: local,
              isCurrent: queueState.currentSong?.id == local[i].id,
              isPlaying: isPlaying,
            ),
          const SizedBox(height: 20),
        ],
        if (web.isNotEmpty) ...[
          _SectionHeader('Só na web', count: web.length),
          for (var i = 0; i < web.length; i++)
            SongTile(
              song: web[i],
              index: i,
              contextList: web,
              showAlbum: false,
              isCurrent: queueState.currentSong?.id == web[i].id,
              isPlaying: isPlaying,
            ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader(this.title, {required this.count});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: palette.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}
