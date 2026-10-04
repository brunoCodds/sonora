import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../data/models/youtube_channel.dart';
import '../../../providers/album_install_providers.dart';
import '../../../providers/channel_providers.dart';
import '../../../shared_widgets/cover_art.dart';
import '../../../shared_widgets/empty_state.dart';
import 'web_result_tile.dart';

/// Detalhe de um álbum de um canal, dentro da mesma área do canal (ver
/// `ChannelBrowserView`): capa, título, as faixas e duas ações —
///
/// - **Instalar álbum**: baixa todas as faixas para o PC (ver
///   `AlbumInstallNotifier.install`); elas passam a fazer parte da
///   Biblioteca, agrupadas em Álbuns.
/// - **Salvar como playlist**: só guarda o álbum como uma playlist do
///   Sonora, tocando por streaming, sem baixar nada.
///
/// Ver as faixas é só leitura; nada é baixado nem gravado até o usuário
/// tocar num desses dois botões.
class AlbumDetailView extends ConsumerStatefulWidget {
  final YoutubeChannelRef channel;
  final YoutubeAlbumRef album;

  const AlbumDetailView({
    super.key,
    required this.channel,
    required this.album,
  });

  @override
  ConsumerState<AlbumDetailView> createState() => _AlbumDetailViewState();
}

class _AlbumDetailViewState extends ConsumerState<AlbumDetailView> {
  /// Evita salvar o mesmo álbum duas vezes como playlist por clique
  /// repetido. A view é recriada por álbum (`key` em `ChannelBrowserView`),
  /// então isto começa `false` a cada álbum aberto.
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final browser = ref.watch(channelBrowserProvider);
    final install = ref.watch(albumInstallProvider);
    final album = widget.album;
    final channel = widget.channel;

    final tracksState = browser.album;
    final tracks = tracksState.tracks;
    final canAct = !tracksState.isLoading && tracks.isNotEmpty;

    final installingThis = install.isRunning && install.albumId == album.id;
    final installingOther = install.isRunning && install.albumId != album.id;
    final showResult = !install.isRunning &&
        install.albumId == album.id &&
        install.resultMessage != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Voltar aos álbuns',
                onPressed: ref.read(channelBrowserProvider.notifier).closeAlbum,
              ),
              const SizedBox(width: 4),
              CoverArt(
                path: null,
                imageUrl: album.thumbnailUrl,
                size: 96,
                borderRadius: 10,
                placeholderIcon: Icons.album_rounded,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      album.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Álbum • ${channel.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                    if (canAct) ...[
                      const SizedBox(height: 2),
                      Text(
                        tracks.length == 1 ? '1 faixa' : '${tracks.length} faixas',
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Tooltip(
                message: 'Baixa todas as faixas para o PC — elas ficam na '
                    'Biblioteca, em Álbuns',
                child: FilledButton.icon(
                  onPressed: (canAct && !install.isRunning) ? _install : null,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Instalar álbum'),
                ),
              ),
              Tooltip(
                message: 'Guarda o álbum como uma playlist, sem baixar — toca '
                    'por streaming',
                child: OutlinedButton.icon(
                  onPressed: (canAct && !_saved) ? _save : null,
                  icon: Icon(
                    _saved ? Icons.check_rounded : Icons.playlist_add_rounded,
                    size: 18,
                  ),
                  label: Text(_saved ? 'Salvo nas playlists' : 'Salvar como playlist'),
                ),
              ),
            ],
          ),
        ),
        if (installingThis)
          _InstallProgress(install: install)
        else if (showResult)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              install.resultMessage!,
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          )
        else if (installingOther)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Outro álbum está sendo instalado — espere ele terminar para '
              'instalar este.',
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ),
        Expanded(child: _buildTracks(tracksState)),
      ],
    );
  }

  Widget _buildTracks(AlbumTracksState tracksState) {
    if (tracksState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = tracksState.errorMessage;
    if (error != null) {
      return EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Não foi possível carregar o álbum',
        message: error,
        action: OutlinedButton(
          onPressed: ref.read(channelBrowserProvider.notifier).reloadAlbum,
          child: const Text('Tentar de novo'),
        ),
      );
    }

    final tracks = tracksState.tracks;
    if (tracks.isEmpty) {
      return const EmptyState(
        icon: Icons.album_outlined,
        title: 'Álbum vazio',
        message: 'O YouTube não listou nenhuma faixa neste álbum.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        return WebResultTile(
          result: tracks[index],
          index: index,
          contextList: tracks,
        );
      },
    );
  }

  void _install() {
    final tracks = ref.read(channelBrowserProvider).album.tracks;
    ref.read(albumInstallProvider.notifier).install(
          album: widget.album,
          artistName: widget.channel.name,
          tracks: tracks,
        );
  }

  void _save() {
    final tracks = ref.read(channelBrowserProvider).album.tracks;
    final count = ref.read(albumInstallProvider.notifier).saveAsPlaylist(
          album: widget.album,
          artistName: widget.channel.name,
          tracks: tracks,
        );
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '"${widget.album.title}" salvo como playlist ($count '
          '${count == 1 ? 'faixa' : 'faixas'})',
        ),
      ),
    );
  }
}

class _InstallProgress extends ConsumerWidget {
  final AlbumInstallState install;

  const _InstallProgress({required this.install});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final current = (install.done + install.failed + 1).clamp(1, install.total);
    final title = install.currentTitle;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title == null || title.isEmpty
                      ? 'Instalando faixa $current de ${install.total}...'
                      : 'Instalando faixa $current de ${install.total} — $title',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: ref.read(albumInstallProvider.notifier).cancel,
                child: const Text('Cancelar'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: install.progress,
              minHeight: 4,
              color: palette.accent,
              backgroundColor: palette.surfaceHighlight,
            ),
          ),
        ],
      ),
    );
  }
}
