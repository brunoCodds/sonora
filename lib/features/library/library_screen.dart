import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../data/models/song_source.dart';
import '../../providers/audio_providers.dart';
import '../../providers/download_providers.dart';
import '../../providers/library_providers.dart';
import '../../shared_widgets/empty_state.dart';
import 'widgets/song_list_header.dart';
import 'widgets/song_tile.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final state = ref.watch(libraryNotifierProvider);
    final queueState = ref.watch(queueControllerProvider);
    final isPlaying = ref.watch(playerPlayingProvider).value ?? false;
    final songs = state.filteredSortedSongs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Biblioteca',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    ref.read(libraryNotifierProvider.notifier).importFiles(),
                icon: const Icon(Icons.audio_file_rounded, size: 18),
                label: const Text('Adicionar arquivos'),
              ),
              FilledButton.icon(
                onPressed: () =>
                    ref.read(libraryNotifierProvider.notifier).importFolder(),
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('Adicionar pasta'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            onChanged: (value) =>
                ref.read(libraryNotifierProvider.notifier).setSearchQuery(value),
            decoration: const InputDecoration(
              hintText: 'Pesquisar músicas, artistas ou álbuns...',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
            ),
          ),
        ),
        if (state.isImporting)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Importando ${state.importCurrent}/${state.importTotal}...',
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: state.importTotal == 0
                      ? null
                      : state.importCurrent / state.importTotal,
                  backgroundColor: palette.surfaceHighlight,
                  color: palette.accent,
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        if (songs.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => ref
                      .read(queueControllerProvider.notifier)
                      .setQueueAndPlay(songs, startIndex: 0),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Tocar tudo'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    final notifier = ref.read(queueControllerProvider.notifier);
                    if (!queueState.shuffleEnabled) notifier.toggleShuffle();
                    notifier.setQueueAndPlay(songs, startIndex: 0);
                  },
                  icon: const Icon(Icons.shuffle_rounded, size: 18),
                  label: const Text('Aleatório'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SongListHeader(count: songs.length),
        ],
        Expanded(
          child: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : songs.isEmpty
                  ? EmptyState(
                      icon: Icons.library_music_outlined,
                      title: state.searchQuery.isEmpty
                          ? 'Sua biblioteca está vazia'
                          : 'Nenhum resultado encontrado',
                      message: state.searchQuery.isEmpty
                          ? 'Adicione arquivos ou uma pasta com suas músicas para começar.'
                          : 'Tente pesquisar por outro termo.',
                      action: state.searchQuery.isEmpty
                          ? FilledButton.icon(
                              onPressed: () => ref
                                  .read(libraryNotifierProvider.notifier)
                                  .importFolder(),
                              icon: const Icon(Icons.folder_open_rounded, size: 18),
                              label: const Text('Adicionar pasta'),
                            )
                          : null,
                    )
                  : ListView.builder(
                      itemCount: songs.length,
                      itemBuilder: (context, index) {
                        final song = songs[index];
                        // Música da web instalada: "remover" apaga o arquivo
                        // baixado e a música volta a existir só como
                        // streaming (segue nos favoritos/playlists). Apagar
                        // a linha do banco, como se faz com uma música
                        // local, deixaria o arquivo órfão no disco e tiraria
                        // a música de favoritos e playlists.
                        final isWebSong = song.source == SongSource.youtube;
                        return SongTile(
                          song: song,
                          index: index,
                          contextList: songs,
                          isCurrent: queueState.currentSong?.id == song.id,
                          isPlaying: isPlaying,
                          removeLabel: isWebSong
                              ? 'Remover download (apaga o arquivo)'
                              : 'Remover da biblioteca',
                          onRemove: () {
                            if (isWebSong) {
                              ref
                                  .read(downloadNotifierProvider.notifier)
                                  .removeDownload(song);
                            } else {
                              ref
                                  .read(libraryNotifierProvider.notifier)
                                  .removeSong(song.id);
                            }
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
