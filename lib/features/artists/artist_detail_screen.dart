import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../data/models/artist.dart';
import '../../providers/audio_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/navigation_providers.dart';
import '../../shared_widgets/cover_art.dart';
import '../library/widgets/song_tile.dart';

class ArtistDetailScreen extends ConsumerWidget {
  final String artistName;
  const ArtistDetailScreen({super.key, required this.artistName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final songs = ref.watch(libraryNotifierProvider).songs;
    final artists = Artist.groupSongs(songs);
    Artist? artist;
    for (final a in artists) {
      if (a.name == artistName) {
        artist = a;
        break;
      }
    }

    if (artist == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(selectedArtistNameProvider.notifier).state = null;
      });
      return const SizedBox.shrink();
    }

    final allArtistSongs = List.of(artist.songs)
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final albums = artist.albums;
    final queueState = ref.watch(queueControllerProvider);
    final isPlaying = ref.watch(playerPlayingProvider).value ?? false;

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
                    ref.read(selectedArtistNameProvider.notifier).state = null,
              ),
              const SizedBox(width: 4),
              CoverArt(
                path: artist.coverPath,
                size: 76,
                borderRadius: 38,
                placeholderIcon: Icons.person_rounded,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(artist.name,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      '${allArtistSongs.length} música${allArtistSongs.length == 1 ? '' : 's'} • '
                      '${albums.length} ${albums.length == 1 ? 'álbum' : 'álbuns'}',
                      style: TextStyle(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => ref
                    .read(queueControllerProvider.notifier)
                    .setQueueAndPlay(allArtistSongs, startIndex: 0),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Tocar'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final album in albums) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(
                    album.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                for (final song in album.sortedSongs)
                  SongTile(
                    song: song,
                    index: album.sortedSongs.indexOf(song),
                    contextList: album.sortedSongs,
                    showAlbum: false,
                    isCurrent: queueState.currentSong?.id == song.id,
                    isPlaying: isPlaying,
                  ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}
