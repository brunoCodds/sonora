import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/utils/duration_formatter.dart';
import '../../data/models/song.dart';
import '../../data/models/song_source.dart';
import '../../shared_widgets/cover_art.dart';

void showSongDetailsSheet(BuildContext context, Song song) {
  showModalBottomSheet(
    context: context,
    backgroundColor: context.palette.surfaceVariant,
    // Sem isso, a folha usa uma altura fixa baseada no conteúdo e nunca
    // aprende sobre o teclado/redimensionamento; com conteúdo longo (ex.:
    // caminho de arquivo grande, todos os metadados presentes) ela estoura
    // a altura disponível. isScrollControlled + o SingleChildScrollView
    // abaixo permitem que a folha cresça até um teto e role o resto.
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _SongDetailsSheet(song: song),
  );
}

class _SongDetailsSheet extends StatelessWidget {
  final Song song;
  const _SongDetailsSheet({required this.song});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Teto de altura: 90% da tela disponível. Abaixo disso o conteúdo
    // ainda decide sua própria altura (mainAxisSize: min), então em
    // metadados curtos a folha continua compacta como antes.
    final maxHeight = MediaQuery.of(context).size.height * 0.9;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: CoverArt(
                path: song.coverPath,
                imageUrl: song.coverUrl,
                size: 160,
                borderRadius: 10,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              song.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              song.artist.isEmpty ? 'Artista desconhecido' : song.artist,
              style: TextStyle(color: palette.textSecondary),
            ),
            const SizedBox(height: 20),
            if (song.source == SongSource.youtube) ...[
              _row(context, 'Origem', 'YouTube'),
              _row(context, 'Canal', song.artist.isEmpty ? '—' : song.artist),
              _row(context, 'Duração', DurationFormatter.formatMs(song.durationMs)),
              _row(
                context,
                'Instalado no PC',
                song.localPath != null ? 'Sim' : 'Não (tocando via streaming)',
              ),
            ] else ...[
              _row(context, 'Álbum', song.album.isEmpty ? '—' : song.album),
              _row(context, 'Artista do álbum',
                  song.albumArtist.isEmpty ? '—' : song.albumArtist),
              _row(context, 'Gênero', song.genre.isEmpty ? '—' : song.genre),
              _row(context, 'Ano', song.year?.toString() ?? '—'),
              _row(context, 'Faixa', song.trackNumber?.toString() ?? '—'),
              _row(context, 'Duração', DurationFormatter.formatMs(song.durationMs)),
              _row(context, 'Arquivo', song.path),
            ],
            _row(
              context,
              'Adicionado em',
              '${song.dateAdded.day.toString().padLeft(2, '0')}/'
                  '${song.dateAdded.month.toString().padLeft(2, '0')}/'
                  '${song.dateAdded.year}',
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(color: context.palette.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
