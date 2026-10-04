import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../core/utils/view_count_formatter.dart';
import '../../../data/models/youtube_search_result.dart';
import '../../../providers/audio_providers.dart';
import '../../../providers/library_providers.dart';
import '../../../shared_widgets/cover_art.dart';
import '../../playlists/widgets/add_to_playlist_dialog.dart';
import '../../song_details/song_details_sheet.dart';

/// Linha de um resultado de busca na web (YouTube) — o equivalente ao
/// `SongTile` da biblioteca, mas para um `YoutubeSearchResult` ainda
/// não persistido.
///
/// Nenhuma ação lê/escreve no banco até o momento em que é usada:
/// simplesmente rolar pelos resultados não grava nada. Assim que
/// alguma ação é executada (tocar, adicionar à fila/playlist,
/// favoritar), o resultado correspondente é gravado como uma `Song` de
/// verdade (ver `LibraryNotifier.materializeWebSong`).
class WebResultTile extends ConsumerWidget {
  final YoutubeSearchResult result;
  final int index;

  /// Lista completa dos resultados atualmente exibidos — usada para
  /// montar a fila ao tocar (toca este e continua pelos seguintes,
  /// igual ao comportamento da Biblioteca).
  final List<YoutubeSearchResult> contextList;

  /// Mostra a contagem de visualizações ao lado do nome do canal (quando
  /// o yt-dlp informou). Ligado só nas listas de um canal, onde a ordem é
  /// "mais tocadas primeiro" e o número explica a ordem.
  final bool showViewCount;

  const WebResultTile({
    super.key,
    required this.result,
    required this.index,
    required this.contextList,
    this.showViewCount = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _playFrom(ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Row(
            children: [
              CoverArt(
                path: null,
                imageUrl: result.thumbnailUrl,
                size: 44,
                borderRadius: 5,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      result.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              Text(
                DurationFormatter.formatMs(result.duration.inMilliseconds),
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded,
                    size: 18, color: palette.textSecondary),
                color: palette.surfaceVariant,
                onSelected: (value) => _onMenuSelected(context, ref, value),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'play', child: Text('Tocar agora')),
                  PopupMenuItem(value: 'queue', child: Text('Adicionar à fila')),
                  PopupMenuItem(value: 'favorite', child: Text('Favoritar')),
                  PopupMenuItem(value: 'playlist', child: Text('Adicionar à playlist')),
                  PopupMenuItem(value: 'details', child: Text('Detalhes')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    final views = result.viewCount;
    if (!showViewCount || views == null) return result.channelName;
    final formatted = ViewCountFormatter.format(views);
    return result.channelName.isEmpty
        ? formatted
        : '${result.channelName} • $formatted';
  }

  void _playFrom(WidgetRef ref) {
    final notifier = ref.read(libraryNotifierProvider.notifier);
    final songs = contextList.map(notifier.materializeWebSong).toList();
    ref
        .read(queueControllerProvider.notifier)
        .setQueueAndPlay(songs, startIndex: index);
  }

  void _onMenuSelected(BuildContext context, WidgetRef ref, String value) {
    final notifier = ref.read(libraryNotifierProvider.notifier);
    switch (value) {
      case 'play':
        _playFrom(ref);
        break;
      case 'queue':
        final song = notifier.materializeWebSong(result);
        ref.read(queueControllerProvider.notifier).addToQueue(song);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${song.title}" adicionada à fila')),
        );
        break;
      case 'favorite':
        final song = notifier.materializeAndFavorite(result);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${song.title}" favoritada')),
        );
        break;
      case 'playlist':
        final song = notifier.materializeWebSong(result);
        showAddToPlaylistDialog(context, ref, song.id);
        break;
      case 'details':
        final song = notifier.materializeWebSong(result);
        showSongDetailsSheet(context, song);
        break;
    }
  }
}
