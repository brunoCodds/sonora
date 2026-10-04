import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../providers/playlist_providers.dart';
import '../../../shared_widgets/app_list_tile.dart';

void showAddToPlaylistDialog(BuildContext context, WidgetRef ref, int songId) {
  showDialog(
    context: context,
    builder: (context) => _AddToPlaylistDialog(songId: songId),
  );
}

class _AddToPlaylistDialog extends ConsumerStatefulWidget {
  final int songId;
  const _AddToPlaylistDialog({required this.songId});

  @override
  ConsumerState<_AddToPlaylistDialog> createState() =>
      _AddToPlaylistDialogState();
}

class _AddToPlaylistDialogState extends ConsumerState<_AddToPlaylistDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final playlists = ref.watch(playlistsNotifierProvider);

    return AlertDialog(
      backgroundColor: palette.surfaceVariant,
      title: const Text('Adicionar à playlist'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Você ainda não tem playlists.',
                  style: TextStyle(color: palette.textSecondary),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    return AppListTile(
                      dense: true,
                      leading: const Icon(Icons.queue_music_rounded),
                      title: Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        ref
                            .read(playlistsNotifierProvider.notifier)
                            .addSong(playlist.id, widget.songId);
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Adicionada a "${playlist.name}"'),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            const Divider(height: 24),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'Nova playlist...',
              ),
              onSubmitted: (_) => _createAndAdd(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _createAndAdd,
          child: const Text('Criar e adicionar'),
        ),
      ],
    );
  }

  void _createAndAdd() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    final playlist =
        ref.read(playlistsNotifierProvider.notifier).create(name);
    ref
        .read(playlistsNotifierProvider.notifier)
        .addSong(playlist.id, widget.songId);
    Navigator.of(context).pop();
  }
}
