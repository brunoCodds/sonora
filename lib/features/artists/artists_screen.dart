import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../data/models/artist.dart';
import '../../providers/library_providers.dart';
import '../../providers/navigation_providers.dart';
import '../../shared_widgets/app_list_tile.dart';
import '../../shared_widgets/cover_art.dart';
import '../../shared_widgets/empty_state.dart';
import 'artist_detail_screen.dart';

class ArtistsScreen extends ConsumerWidget {
  const ArtistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final selectedName = ref.watch(selectedArtistNameProvider);
    if (selectedName != null) {
      return ArtistDetailScreen(artistName: selectedName);
    }

    final songs = ref.watch(libraryNotifierProvider).songs;
    final artists = Artist.groupSongs(songs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Text('Artistas', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        ),
        Expanded(
          child: artists.isEmpty
              ? const EmptyState(
                  icon: Icons.person_outline_rounded,
                  title: 'Nenhum artista encontrado',
                  message: 'Importe músicas na Biblioteca para ver seus artistas aqui.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: artists.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 78),
                  itemBuilder: (context, index) {
                    final artist = artists[index];
                    return AppListTile(
                      leading: CoverArt(
                        path: artist.coverPath,
                        size: 52,
                        borderRadius: 26,
                        placeholderIcon: Icons.person_rounded,
                      ),
                      title: Text(
                        artist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${artist.songs.length} música${artist.songs.length == 1 ? '' : 's'} • '
                        '${artist.albums.length} ${artist.albums.length == 1 ? 'álbum' : 'álbuns'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.textSecondary, fontSize: 12),
                      ),
                      onTap: () =>
                          ref.read(selectedArtistNameProvider.notifier).state = artist.name,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
