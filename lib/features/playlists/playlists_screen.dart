import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../providers/navigation_providers.dart';
import '../../providers/playlist_providers.dart';
import '../../shared_widgets/empty_state.dart';
import 'playlist_detail_screen.dart';
import 'widgets/playlist_tile.dart';

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedPlaylistIdProvider);
    if (selectedId != null) {
      return PlaylistDetailScreen(playlistId: selectedId);
    }

    final playlists = ref.watch(playlistsNotifierProvider);
    final playlistsNotifier = ref.read(playlistsNotifierProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              const Text(
                'Playlists',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _createPlaylist(context, ref),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Nova playlist'),
              ),
            ],
          ),
        ),
        Expanded(
          child: playlists.isEmpty
              ? EmptyState(
                  icon: Icons.queue_music_outlined,
                  title: 'Nenhuma playlist ainda',
                  message: 'Crie uma playlist para organizar suas músicas favoritas.',
                  action: FilledButton.icon(
                    onPressed: () => _createPlaylist(context, ref),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Nova playlist'),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    final songs = playlistsNotifier.songsFor(playlist);
                    final coverSong = songs.isNotEmpty
                        ? songs.firstWhere(
                            (s) => s.coverPath != null || s.coverUrl != null,
                            orElse: () => songs.first,
                          )
                        : null;
                    return PlaylistTile(
                      playlist: playlist,
                      coverPath: coverSong?.coverPath,
                      coverUrl: coverSong?.coverUrl,
                      onTap: () => ref
                          .read(selectedPlaylistIdProvider.notifier)
                          .state = playlist.id,
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _createPlaylist(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.palette.surfaceVariant,
        title: const Text('Nova playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nome da playlist'),
          onSubmitted: (_) => _submit(context, ref, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => _submit(context, ref, controller.text),
            child: const Text('Criar'),
          ),
        ],
      ),
    );
  }

  void _submit(BuildContext context, WidgetRef ref, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    ref.read(playlistsNotifierProvider.notifier).create(trimmed);
    Navigator.of(context).pop();
  }
}
