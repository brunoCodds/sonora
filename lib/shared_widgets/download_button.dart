import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_palette.dart';
import '../data/models/song.dart';
import '../data/models/song_source.dart';
import '../providers/download_providers.dart';
import 'app_icon_button.dart';

/// Botão de "instalar/sincronizar no PC", ao lado do [FavoriteButton]
/// na barra do player e no mini player.
///
/// Só existe para músicas da web ([SongSource.youtube]) — uma música
/// local já é, por definição, um arquivo no PC, então o botão não
/// aparece para ela. Ao tocar, baixa o áudio para
/// `Documentos/Sonora/Músicas baixadas/`; tocando de novo numa que já
/// foi baixada, remove o arquivo (volta a depender de streaming).
class DownloadButton extends ConsumerWidget {
  final Song song;
  final double size;

  const DownloadButton({super.key, required this.song, this.size = 20});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    if (song.source == SongSource.local) return const SizedBox.shrink();

    final downloadState = ref.watch(downloadNotifierProvider);
    final isDownloadingThis = downloadState.downloadingSongId == song.id;
    final isInstalled = song.localPath != null;

    if (isDownloadingThis) {
      return SizedBox(
        width: size + 12,
        height: size + 12,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Tooltip(
            message:
                'Baixando... ${(downloadState.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: downloadState.progress > 0 ? downloadState.progress : null,
              color: palette.accent,
            ),
          ),
        ),
      );
    }

    return AppIconButton(
      icon: isInstalled ? Icons.download_done_rounded : Icons.download_rounded,
      tooltip: isInstalled
          ? 'Instalada no PC — toque para remover o download'
          : 'Baixar para o PC',
      active: isInstalled,
      activeColor: palette.accent,
      size: size,
      onPressed: downloadState.downloadingSongId != null
          ? null
          : () {
              final notifier = ref.read(downloadNotifierProvider.notifier);
              if (isInstalled) {
                notifier.removeDownload(song);
              } else {
                notifier.download(song);
              }
            },
    );
  }
}
