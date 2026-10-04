import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../data/models/playlist.dart';
import '../../providers/audio_providers.dart';
import '../../providers/navigation_providers.dart';
import '../../providers/playlist_providers.dart';
import '../../shared_widgets/cover_art.dart';
import '../../shared_widgets/empty_state.dart';
import '../library/widgets/song_tile.dart';
import 'widgets/add_songs_dialog.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  final int playlistId;
  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final playlists = ref.watch(playlistsNotifierProvider);
    final playlist = playlists.where((p) => p.id == playlistId).firstOrNull;

    if (playlist == null) {
      // A playlist foi apagada enquanto estava aberta.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(selectedPlaylistIdProvider.notifier).state = null;
      });
      return const SizedBox.shrink();
    }

    final notifier = ref.read(playlistsNotifierProvider.notifier);
    final songs = notifier.songsFor(playlist);
    final queueState = ref.watch(queueControllerProvider);
    final isPlaying = ref.watch(playerPlayingProvider).value ?? false;
    final coverSong = songs.isNotEmpty
        ? songs.firstWhere(
            (s) => s.coverPath != null || s.coverUrl != null,
            orElse: () => songs.first,
          )
        : null;
    final cover = coverSong?.coverPath;
    final coverUrl = coverSong?.coverUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () =>
                    ref.read(selectedPlaylistIdProvider.notifier).state = null,
              ),
              const SizedBox(width: 4),
              CoverArt(
                path: cover,
                imageUrl: coverUrl,
                size: 76,
                borderRadius: 8,
                placeholderIcon: Icons.queue_music_rounded,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      playlist.name,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${songs.length} música${songs.length == 1 ? '' : 's'}',
                      style: TextStyle(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Adicionar músicas da biblioteca',
                icon: const Icon(Icons.playlist_add_rounded, size: 22),
                onPressed: () =>
                    showAddSongsToPlaylistDialog(context, ref, playlist),
              ),
              IconButton(
                tooltip: 'Renomear',
                icon: const Icon(Icons.edit_rounded, size: 20),
                onPressed: () => _rename(context, ref, playlist),
              ),
              IconButton(
                tooltip: 'Apagar playlist',
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                onPressed: () => _delete(context, ref, playlist),
              ),
            ],
          ),
        ),
        if (songs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                FilledButton.icon(
                  onPressed: () => ref
                      .read(queueControllerProvider.notifier)
                      .setQueueAndPlay(songs, startIndex: 0),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Tocar'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    final queueNotifier = ref.read(queueControllerProvider.notifier);
                    if (!queueState.shuffleEnabled) queueNotifier.toggleShuffle();
                    queueNotifier.setQueueAndPlay(songs, startIndex: 0);
                  },
                  icon: const Icon(Icons.shuffle_rounded, size: 18),
                  label: const Text('Aleatório'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Expanded(
          child: songs.isEmpty
              ? EmptyState(
                  icon: Icons.music_off_rounded,
                  title: 'Playlist vazia',
                  message: 'Adicione músicas a partir da Biblioteca, de um álbum ou artista.',
                  action: FilledButton.icon(
                    onPressed: () =>
                        showAddSongsToPlaylistDialog(context, ref, playlist),
                    icon: const Icon(Icons.playlist_add_rounded, size: 18),
                    label: const Text('Adicionar músicas da biblioteca'),
                  ),
                )
              : ExcludeSemantics(
                  // Mesmo motivo do queue_panel.dart: ReorderableListView
                  // tem um bug conhecido no motor do Flutter no Windows que
                  // corrompe a árvore de acessibilidade durante o arraste.
                  child: ReorderableListView.builder(
                    itemCount: songs.length,
                    onReorderItem: (oldIndex, newIndex) {
                      final ids = songs.map((s) => s.id).toList();
                      final item = ids.removeAt(oldIndex);
                      ids.insert(newIndex, item);
                      notifier.reorder(playlist.id, ids);
                    },
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      return Container(
                        key: ValueKey('playlist_${playlist.id}_song_${song.id}'),
                        child: SongTile(
                          song: song,
                          index: index,
                          contextList: songs,
                          isCurrent: queueState.currentSong?.id == song.id,
                          isPlaying: isPlaying,
                          removeLabel: 'Remover da playlist',
                          onRemove: () => notifier.removeSong(playlist.id, song.id),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  void _rename(BuildContext context, WidgetRef ref, Playlist playlist) {
    final controller = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.palette.surfaceVariant,
        title: const Text('Renomear playlist'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(playlistsNotifierProvider.notifier).rename(playlist.id, name);
              }
              Navigator.of(context).pop();
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  void _delete(BuildContext context, WidgetRef ref, Playlist playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.palette.surfaceVariant,
        title: const Text('Apagar playlist?'),
        content: Text('"${playlist.name}" será apagada permanentemente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.palette.error),
            onPressed: () {
              ref.read(playlistsNotifierProvider.notifier).delete(playlist.id);
              ref.read(selectedPlaylistIdProvider.notifier).state = null;
              Navigator.of(context).pop();
            },
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
