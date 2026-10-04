import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../data/models/song.dart';
import '../../../providers/audio_providers.dart';
import '../../../shared_widgets/cover_art.dart';
import '../../playlists/widgets/add_to_playlist_dialog.dart';
import '../../song_details/song_details_sheet.dart';

class SongTile extends ConsumerWidget {
  final Song song;
  final int index;

  /// Lista completa de onde essa música faz parte (biblioteca filtrada,
  /// músicas de um álbum, de uma playlist, etc). Usada para montar a
  /// fila de reprodução ao clicar em "tocar".
  final List<Song> contextList;

  final bool showAlbum;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback? onRemove;
  final String? removeLabel;

  const SongTile({
    super.key,
    required this.song,
    required this.index,
    required this.contextList,
    this.showAlbum = true,
    this.isCurrent = false,
    this.isPlaying = false,
    this.onRemove,
    this.removeLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ref
            .read(queueControllerProvider.notifier)
            .setQueueAndPlay(contextList, startIndex: index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Row(
            children: [
              CoverArt(
                path: song.coverPath,
                imageUrl: song.coverUrl,
                size: 44,
                borderRadius: 5,
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isCurrent ? palette.accentVariant : palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artist.isEmpty ? 'Artista desconhecido' : song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              if (showAlbum)
                Expanded(
                  flex: 2,
                  child: Text(
                    song.album.isEmpty ? '—' : song.album,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: palette.textSecondary),
                  ),
                ),
              if (isCurrent)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    isPlaying ? Icons.equalizer_rounded : Icons.pause_rounded,
                    size: 16,
                    color: palette.accentVariant,
                  ),
                ),
              Text(
                DurationFormatter.formatMs(song.durationMs),
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded,
                    size: 18, color: palette.textSecondary),
                color: palette.surfaceVariant,
                onSelected: (value) => _onMenuSelected(context, ref, value),
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'play', child: Text('Tocar agora')),
                  const PopupMenuItem(value: 'queue', child: Text('Adicionar à fila')),
                  const PopupMenuItem(value: 'playlist', child: Text('Adicionar à playlist')),
                  const PopupMenuItem(value: 'details', child: Text('Detalhes')),
                  if (onRemove != null)
                    PopupMenuItem(
                      value: 'remove',
                      child: Text(removeLabel ?? 'Remover'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onMenuSelected(BuildContext context, WidgetRef ref, String value) {
    switch (value) {
      case 'play':
        ref
            .read(queueControllerProvider.notifier)
            .setQueueAndPlay(contextList, startIndex: index);
        break;
      case 'queue':
        ref.read(queueControllerProvider.notifier).addToQueue(song);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${song.title}" adicionada à fila')),
        );
        break;
      case 'playlist':
        showAddToPlaylistDialog(context, ref, song.id);
        break;
      case 'details':
        showSongDetailsSheet(context, song);
        break;
      case 'remove':
        onRemove?.call();
        break;
    }
  }
}
