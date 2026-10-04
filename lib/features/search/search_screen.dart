import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../data/models/youtube_channel.dart';
import '../../data/models/youtube_search_result.dart';
import '../../providers/channel_providers.dart';
import '../../providers/service_providers.dart';
import '../../providers/web_search_providers.dart';
import '../../services/web_music/playlist_import_service.dart';
import '../../shared_widgets/empty_state.dart';
import 'widgets/channel_browser_view.dart';
import 'widgets/channel_card.dart';
import 'widgets/import_playlist_dialog.dart';
import 'widgets/web_result_tile.dart';

/// Aba Buscar — busca de música na web (YouTube), substituindo por
/// completo a antiga busca só-na-biblioteca-local. Colar um link de
/// playlist do YouTube no mesmo campo oferece importar a playlist
/// inteira em vez de buscar. Um link de playlist do Spotify ainda é
/// reconhecido (pra dar uma mensagem clara), mas a importação em si
/// está desativada por enquanto — ver [spotifyPlaylistImportEnabled].
///
/// O resultado de uma busca tem o layout: as 2 músicas mais relevantes no
/// topo, logo abaixo um card do canal (artista/banda) e, depois, o resto
/// dos resultados do YouTube, sem filtrar nada. Tocar no card abre a área
/// do canal AQUI MESMO (não é uma tela nova) — ver [ChannelBrowserView].
class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final searchState = ref.watch(webSearchNotifierProvider);
    final youtubeClientAsync = ref.watch(youtubeClientProvider);
    final linkType = PlaylistImportService.detectLinkType(searchState.query);
    final looksLikePlaylistLink = linkType != PlaylistLinkType.unknown;
    // Só interessa SE há um canal aberto (não o estado todo dele), para a
    // tela inteira não redesenhar a cada aba que carrega.
    final isChannelOpen =
        ref.watch(channelBrowserProvider.select((state) => state.channel != null));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              const Expanded(
                child: Text('Buscar', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              ),
              OutlinedButton.icon(
                onPressed: () => showImportPlaylistDialog(context, ref),
                icon: const Icon(Icons.playlist_add_rounded, size: 18),
                label: const Text('Importar playlist'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            autofocus: true,
            onChanged: (value) {
              // Digitar de novo é buscar outra coisa: sai do canal aberto
              // e volta a mostrar os resultados.
              ref.read(channelBrowserProvider.notifier).closeChannel();
              ref.read(webSearchNotifierProvider.notifier).setQuery(value);
            },
            decoration: const InputDecoration(
              hintText: 'Busque uma música, ou cole um link de playlist do YouTube...',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
            ),
          ),
        ),
        if (youtubeClientAsync.isLoading) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Preparando reprodução da web...',
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: isChannelOpen
              ? const ChannelBrowserView()
              : _buildBody(context, ref, searchState, looksLikePlaylistLink, linkType),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    WebSearchState searchState,
    bool looksLikePlaylistLink,
    PlaylistLinkType linkType,
  ) {
    final palette = context.palette;
    if (looksLikePlaylistLink) {
      final isSpotify = linkType == PlaylistLinkType.spotify;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSpotify ? Icons.block_rounded : Icons.playlist_add_check_rounded,
                size: 56,
                color: palette.textSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                isSpotify
                    ? 'Isso parece um link de playlist do Spotify'
                    : 'Isso parece um link de playlist do YouTube',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isSpotify
                    ? 'A importação de playlists do Spotify está temporariamente '
                        'indisponível (a Spotify passou a exigir login do usuário '
                        'para isso, desde fev/2026). Importar do YouTube continua '
                        'funcionando normalmente.'
                    : 'Quer importar as faixas dela para uma playlist no Sonora?',
                style: TextStyle(color: palette.textSecondary),
                textAlign: TextAlign.center,
              ),
              if (!isSpotify) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => showImportPlaylistDialog(
                    context,
                    ref,
                    initialLink: searchState.query.trim(),
                  ),
                  icon: const Icon(Icons.playlist_add_rounded, size: 18),
                  label: const Text('Importar playlist'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (searchState.query.trim().isEmpty) {
      return const EmptyState(
        icon: Icons.search_rounded,
        title: 'Buscar música na web',
        message: 'Digite para buscar no YouTube, ou cole um link de playlist para importar.',
      );
    }

    if (searchState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (searchState.errorMessage != null) {
      return EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Não foi possível buscar',
        message: searchState.errorMessage!,
      );
    }

    if (searchState.results.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nenhum resultado',
        message: 'Tente pesquisar por outro termo.',
      );
    }

    return _buildResults(ref, searchState.results, searchState.channel);
  }

  /// Quantas músicas ficam no topo, antes do card do canal.
  static const _topSongsCount = 2;

  /// Monta o resultado: [_topSongsCount] músicas mais relevantes, o card do
  /// canal ([channel] — `null` se nenhum resultado trouxe dados suficientes
  /// de canal para abri-lo; ver `WebSearchNotifier`) e o restante, sem
  /// filtrar por tipo.
  ///
  /// Cada linha é um construtor de widget (e não o widget já pronto) para a
  /// lista continuar preguiçosa como antes: só as linhas visíveis criam seu
  /// widget (e carregam a capa da rede).
  Widget _buildResults(
    WidgetRef ref,
    List<YoutubeSearchResult> results,
    YoutubeChannelRef? channel,
  ) {
    final topCount = results.length < _topSongsCount ? results.length : _topSongsCount;

    Widget tile(int index) => WebResultTile(
          result: results[index],
          index: index,
          contextList: results,
        );

    final rows = <Widget Function()>[
      () => const _SectionLabel('Melhores resultados'),
      for (var i = 0; i < topCount; i++) () => tile(i),
      if (channel != null) () => _channelCard(ref, channel),
      if (results.length > topCount) () => const _SectionLabel('Mais resultados'),
      for (var i = topCount; i < results.length; i++) () => tile(i),
    ];

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index](),
    );
  }

  Widget _channelCard(WidgetRef ref, YoutubeChannelRef channel) {
    return ChannelCard(
      key: ValueKey('channel:${channel.key}'),
      channel: channel,
      onTap: () => ref.read(channelBrowserProvider.notifier).openChannel(channel),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: palette.textSecondary,
        ),
      ),
    );
  }
}
