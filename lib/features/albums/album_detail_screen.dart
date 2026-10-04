import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/utils/duration_formatter.dart';
import '../../data/models/album.dart';
import '../../providers/audio_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/navigation_providers.dart';
import '../../shared_widgets/cover_art.dart';
import '../library/widgets/song_tile.dart';

class AlbumDetailScreen extends ConsumerWidget {
  final String albumKey;
  const AlbumDetailScreen({super.key, required this.albumKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final songs = ref.watch(libraryNotifierProvider).songs;
    final albums = Album.groupSongs(songs);
    Album? album;
    for (final a in albums) {
      if (a.key == albumKey) {
        album = a;
        break;
      }
    }

    if (album == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(selectedAlbumKeyProvider.notifier).state = null;
      });
      return const SizedBox.shrink();
    }

    final albumSongs = album.sortedSongs;
    final queueState = ref.watch(queueControllerProvider);
    final isPlaying = ref.watch(playerPlayingProvider).value ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () =>
                    ref.read(selectedAlbumKeyProvider.notifier).state = null,
              ),
              const SizedBox(width: 4),
              CoverArt(
                path: album.coverPath,
                size: 110,
                borderRadius: 10,
                placeholderIcon: Icons.album_rounded,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      album.name,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(album.artist, style: TextStyle(color: palette.textSecondary)),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (album.year != null) album.year.toString(),
                        '${albumSongs.length} música${albumSongs.length == 1 ? '' : 's'}',
                        DurationFormatter.format(album.totalDuration),
                      ].join(' • '),
                      style: TextStyle(fontSize: 12, color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: () => ref
                    .read(queueControllerProvider.notifier)
                    .setQueueAndPlay(albumSongs, startIndex: 0),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Tocar álbum'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () {
                  final notifier = ref.read(queueControllerProvider.notifier);
                  if (!queueState.shuffleEnabled) notifier.toggleShuffle();
                  notifier.setQueueAndPlay(albumSongs, startIndex: 0);
                },
                icon: const Icon(Icons.shuffle_rounded, size: 18),
                label: const Text('Aleatório'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: albumSongs.length,
            itemBuilder: (context, index) {
              final song = albumSongs[index];
              return SongTile(
                song: song,
                index: index,
                contextList: albumSongs,
                showAlbum: false,
                isCurrent: queueState.currentSong?.id == song.id,
                isPlaying: isPlaying,
              );
            },
          ),
        ),
      ],
    );
  }
}
