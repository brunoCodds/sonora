import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../data/models/youtube_channel.dart';
import '../../../providers/channel_providers.dart';
import '../../../shared_widgets/cover_art.dart';
import '../../../shared_widgets/empty_state.dart';
import 'album_detail_view.dart';
import 'web_result_tile.dart';

/// A área do canal que substitui a lista de resultados DENTRO da tela
/// Buscar (não é uma rota nova): cabeçalho com o logo do canal, abas
/// Músicas / Álbuns / Ao vivo / Shows e a lista da aba escolhida. Dentro da
/// aba Álbuns, tocar num álbum troca a área pelo detalhe dele
/// ([AlbumDetailView]).
///
/// O estado vive em `channelBrowserProvider`; esta view só desenha.
class ChannelBrowserView extends ConsumerWidget {
  const ChannelBrowserView({super.key});

  static String tabLabel(ChannelTab tab) {
    switch (tab) {
      case ChannelTab.songs:
        return 'Músicas';
      case ChannelTab.albums:
        return 'Álbuns';
      case ChannelTab.live:
        return 'Ao vivo';
      case ChannelTab.shows:
        return 'Shows';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(channelBrowserProvider);
    final channel = state.channel;
    if (channel == null) return const SizedBox.shrink();

    final openAlbum = state.openAlbum;
    if (state.tab == ChannelTab.albums && openAlbum != null) {
      return AlbumDetailView(
        key: ValueKey(openAlbum.id),
        channel: channel,
        album: openAlbum,
      );
    }

    final notifier = ref.read(channelBrowserProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChannelHeader(channel: channel, onBack: notifier.closeChannel),
        _TabsRow(selected: state.tab, onSelected: notifier.selectTab),
        const SizedBox(height: 4),
        Expanded(child: _TabContent(state: state)),
      ],
    );
  }
}

class _ChannelHeader extends StatelessWidget {
  final YoutubeChannelRef channel;
  final VoidCallback onBack;

  const _ChannelHeader({required this.channel, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final banner = channel.bannerUrl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (banner != null && banner.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 96,
                  child: Image.network(
                    banner,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) => DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: palette.coverGradient,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Voltar aos resultados',
                onPressed: onBack,
              ),
              const SizedBox(width: 4),
              CoverArt(
                path: null,
                imageUrl: channel.avatarUrl,
                size: 72,
                borderRadius: 36, // metade do tamanho = círculo.
                placeholderIcon: Icons.person_rounded,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      channel.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Canal do YouTube',
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TabsRow extends StatelessWidget {
  final ChannelTab selected;
  final ValueChanged<ChannelTab> onSelected;

  const _TabsRow({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Rola na horizontal se a janela estiver estreita — nunca estoura.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          for (final tab in ChannelTab.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(ChannelBrowserView.tabLabel(tab)),
                selected: tab == selected,
                showCheckmark: false,
                onSelected: (_) => onSelected(tab),
                selectedColor: palette.accent,
                backgroundColor: palette.surfaceVariant,
                side: BorderSide.none,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: tab == selected ? palette.labelOnAccent : palette.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabContent extends ConsumerWidget {
  final ChannelBrowserState state;

  const _TabContent({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = state.tab;
    final tabState = state.tabState(tab);
    final notifier = ref.read(channelBrowserProvider.notifier);

    if (tabState.errorMessage != null) {
      return EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Não foi possível carregar',
        message: tabState.errorMessage!,
        action: OutlinedButton(
          onPressed: () => notifier.reloadTab(tab),
          child: const Text('Tentar de novo'),
        ),
      );
    }

    if (tabState.isLoading || !tabState.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (tab == ChannelTab.albums) {
      final albums = tabState.albums;
      if (albums.isEmpty) return _emptyFor(tab);
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: albums.length,
        itemBuilder: (context, index) {
          final album = albums[index];
          return _AlbumTile(
            key: ValueKey(album.id),
            album: album,
            onTap: () => notifier.openAlbum(album),
          );
        },
      );
    }

    final videos = tabState.videos;
    if (videos.isEmpty) return _emptyFor(tab);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        return WebResultTile(
          result: videos[index],
          index: index,
          contextList: videos,
          // Na aba Músicas a ordem é "mais tocadas primeiro": o número
          // de visualizações explica essa ordem.
          showViewCount: tab == ChannelTab.songs,
        );
      },
    );
  }

  Widget _emptyFor(ChannelTab tab) {
    switch (tab) {
      case ChannelTab.songs:
        return const EmptyState(
          icon: Icons.music_off_rounded,
          title: 'Nenhuma música encontrada',
          message: 'Este canal não tem vídeos públicos para listar.',
        );
      case ChannelTab.albums:
        return const EmptyState(
          icon: Icons.album_outlined,
          title: 'Nenhum álbum encontrado',
          message: 'Este canal não publica álbuns, ou o YouTube não os listou.',
        );
      case ChannelTab.live:
        return const EmptyState(
          icon: Icons.sensors_off_rounded,
          title: 'Nenhuma transmissão ao vivo',
          message: 'Este canal não tem transmissões ao vivo para listar.',
        );
      case ChannelTab.shows:
        return const EmptyState(
          icon: Icons.theaters_rounded,
          title: 'Nenhum show encontrado',
          message: 'Não achei gravações de show neste canal.',
        );
    }
  }
}

/// Linha de um álbum na aba Álbuns. Ao aparecer na tela, pede a capa do
/// álbum (a do 1º vídeo dele) se a listagem não trouxe nenhuma — como a
/// lista é preguiçosa, só os álbuns visíveis fazem esse pedido. Enquanto a
/// capa não chega, mostra o ícone de álbum.
class _AlbumTile extends ConsumerStatefulWidget {
  final YoutubeAlbumRef album;
  final VoidCallback onTap;

  const _AlbumTile({super.key, required this.album, required this.onTap});

  @override
  ConsumerState<_AlbumTile> createState() => _AlbumTileState();
}

class _AlbumTileState extends ConsumerState<_AlbumTile> {
  @override
  void initState() {
    super.initState();
    // Seguro de chamar daqui: não muda estado de forma síncrona (ver
    // `ChannelBrowserNotifier.requestAlbumCover`).
    ref.read(channelBrowserProvider.notifier).requestAlbumCover(widget.album);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final album = widget.album;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Row(
            children: [
              CoverArt(
                path: null,
                imageUrl: album.thumbnailUrl,
                size: 56,
                borderRadius: 6,
                placeholderIcon: Icons.album_rounded,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      album.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Álbum',
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: palette.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
