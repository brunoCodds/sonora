import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../data/models/album.dart';
import '../../providers/library_providers.dart';
import '../../providers/navigation_providers.dart';
import '../../shared_widgets/cover_art.dart';
import '../../shared_widgets/empty_state.dart';
import 'album_detail_screen.dart';

class AlbumsScreen extends ConsumerWidget {
  const AlbumsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedKey = ref.watch(selectedAlbumKeyProvider);
    if (selectedKey != null) {
      return AlbumDetailScreen(albumKey: selectedKey);
    }

    final songs = ref.watch(libraryNotifierProvider).songs;
    final albums = Album.groupSongs(songs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Text('Álbuns', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        ),
        Expanded(
          child: albums.isEmpty
              ? const EmptyState(
                  icon: Icons.album_outlined,
                  title: 'Nenhum álbum encontrado',
                  message: 'Importe músicas na Biblioteca para ver seus álbuns aqui.',
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: albums.length,
                  itemBuilder: (context, index) {
                    final album = albums[index];
                    return _AlbumCard(
                      album: album,
                      onTap: () =>
                          ref.read(selectedAlbumKeyProvider.notifier).state = album.key,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final Album album;
  final VoidCallback onTap;
  const _AlbumCard({required this.album, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: CoverArt(
                  path: album.coverPath,
                  size: double.infinity,
                  borderRadius: 8,
                  placeholderIcon: Icons.album_rounded,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                album.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
