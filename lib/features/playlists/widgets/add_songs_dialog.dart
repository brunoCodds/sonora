import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../data/models/playlist.dart';
import '../../../data/models/song.dart';
import '../../../providers/library_providers.dart';
import '../../../providers/playlist_providers.dart';
import '../../../shared_widgets/app_list_tile.dart';

/// Mostra um diálogo para escolher músicas da Biblioteca (arquivos locais
/// e músicas da web já instaladas — a mesma lista que alimenta a tela de
/// Biblioteca, via [LibraryState.songs]) e adicioná-las a [playlist].
///
/// Complementa `showAddToPlaylistDialog` (que parte de UMA música e
/// escolhe a playlist); aqui o ponto de partida é a playlist já aberta em
/// `PlaylistDetailScreen`, com seleção múltipla de músicas.
void showAddSongsToPlaylistDialog(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) {
  showDialog(
    context: context,
    builder: (context) => _AddSongsDialog(playlist: playlist),
  );
}

class _AddSongsDialog extends ConsumerStatefulWidget {
  final Playlist playlist;
  const _AddSongsDialog({required this.playlist});

  @override
  ConsumerState<_AddSongsDialog> createState() => _AddSongsDialogState();
}

class _AddSongsDialogState extends ConsumerState<_AddSongsDialog> {
  final _searchController = TextEditingController();
  final Set<int> _selectedIds = {};
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Direto de LibraryState.songs — todas as músicas conhecidas (locais +
    // web instalada), sem o filtro/ordenação da tela de Biblioteca: a
    // busca aqui é própria deste diálogo.
    final allSongs = ref.watch(libraryNotifierProvider).songs;
    final alreadyInPlaylist = widget.playlist.songIds.toSet();
    final available =
        allSongs.where((s) => !alreadyInPlaylist.contains(s.id));

    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? available.toList()
        : available
            .where((s) =>
                s.title.toLowerCase().contains(query) ||
                s.artist.toLowerCase().contains(query))
            .toList();

    return AlertDialog(
      backgroundColor: palette.surfaceVariant,
      title: Text('Adicionar músicas a "${widget.playlist.name}"'),
      content: SizedBox(
        width: 420,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Buscar na biblioteca...',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildList(allSongs, filtered, query)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _selectedIds.isEmpty ? null : _addSelected,
          child: Text(
            _selectedIds.isEmpty
                ? 'Adicionar'
                : 'Adicionar (${_selectedIds.length})',
          ),
        ),
      ],
    );
  }

  Widget _buildList(List<Song> allSongs, List<Song> filtered, String query) {
    final palette = context.palette;
    if (allSongs.isEmpty) {
      return Center(
        child: Text(
          'Sua biblioteca está vazia.',
          style: TextStyle(color: palette.textSecondary),
        ),
      );
    }
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          query.isEmpty
              ? 'Todas as músicas da biblioteca já estão nessa playlist.'
              : 'Nenhuma música encontrada.',
          style: TextStyle(color: palette.textSecondary),
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final song = filtered[index];
        final selected = _selectedIds.contains(song.id);
        return AppListTile(
          dense: true,
          leading: Checkbox(
            value: selected,
            onChanged: (_) => _toggle(song),
          ),
          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.textSecondary),
          ),
          onTap: () => _toggle(song),
        );
      },
    );
  }

  void _toggle(Song song) {
    setState(() {
      if (!_selectedIds.remove(song.id)) {
        _selectedIds.add(song.id);
      }
    });
  }

  void _addSelected() {
    final count = _selectedIds.length;
    final playlistName = widget.playlist.name;
    ref
        .read(playlistsNotifierProvider.notifier)
        .addSongs(widget.playlist.id, _selectedIds);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$count música${count == 1 ? '' : 's'} '
          'adicionada${count == 1 ? '' : 's'} a "$playlistName"',
        ),
      ),
    );
  }
}
