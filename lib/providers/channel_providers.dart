import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/youtube_channel.dart';
import '../data/models/youtube_search_result.dart';
import '../services/youtube/channel_json_parser.dart';
import '../services/youtube/ytdlp_process.dart';
import 'service_providers.dart';

/// Estado de UMA aba de conteúdo do canal (Músicas, Álbuns, Ao vivo ou
/// Shows). Cada aba carrega só quando o usuário abre ela pela primeira vez
/// e fica em cache enquanto o canal estiver aberto.
class ChannelTabState {
  final bool isLoading;
  final bool loaded;
  final String? errorMessage;

  /// Conteúdo das abas Músicas, Ao vivo e Shows.
  final List<YoutubeSearchResult> videos;

  /// Conteúdo da aba Álbuns.
  final List<YoutubeAlbumRef> albums;

  const ChannelTabState({
    this.isLoading = false,
    this.loaded = false,
    this.errorMessage,
    this.videos = const [],
    this.albums = const [],
  });
}

/// Faixas do álbum aberto no momento (a "tela" de detalhe de um álbum,
/// dentro da aba Álbuns).
class AlbumTracksState {
  final bool isLoading;
  final String? errorMessage;
  final List<YoutubeSearchResult> tracks;

  const AlbumTracksState({
    this.isLoading = false,
    this.errorMessage,
    this.tracks = const [],
  });
}

/// Tudo o que a área de canal da tela Buscar precisa: qual canal está
/// aberto (`null` = nenhum, a tela mostra os resultados normais), qual aba
/// está selecionada, o estado de cada aba e o álbum aberto, se houver.
class ChannelBrowserState {
  final YoutubeChannelRef? channel;
  final ChannelTab tab;
  final Map<ChannelTab, ChannelTabState> tabs;
  final YoutubeAlbumRef? openAlbum;
  final AlbumTracksState album;

  const ChannelBrowserState({
    this.channel,
    this.tab = ChannelTab.songs,
    this.tabs = const {},
    this.openAlbum,
    this.album = const AlbumTracksState(),
  });

  ChannelTabState tabState(ChannelTab tab) =>
      tabs[tab] ?? const ChannelTabState();

  ChannelBrowserState copyWith({
    YoutubeChannelRef? channel,
    ChannelTab? tab,
    Map<ChannelTab, ChannelTabState>? tabs,
    YoutubeAlbumRef? openAlbum,
    bool clearOpenAlbum = false,
    AlbumTracksState? album,
  }) {
    return ChannelBrowserState(
      channel: channel ?? this.channel,
      tab: tab ?? this.tab,
      tabs: tabs ?? this.tabs,
      openAlbum: clearOpenAlbum ? null : (openAlbum ?? this.openAlbum),
      album: album ?? this.album,
    );
  }
}

/// Controla a área de canal que se abre DENTRO da tela Buscar (não é uma
/// rota nova): abrir um canal, trocar de aba, abrir um álbum.
///
/// Tudo é só leitura — nada daqui grava no banco nem baixa arquivo (isso é
/// do `AlbumInstallNotifier`, só quando o usuário pede).
class ChannelBrowserNotifier extends StateNotifier<ChannelBrowserState> {
  final Ref _ref;

  /// Aumentam a cada canal/álbum aberto ou fechado — uma resposta que
  /// chega depois de o usuário já ter ido para outro canal (ou fechado)
  /// compara com o valor de quando foi pedida e se descarta.
  int _channelGeneration = 0;
  int _albumGeneration = 0;

  /// Quantas capas de álbum são lidas ao mesmo tempo. Cada uma é um
  /// processo do yt-dlp; poucos de cada vez para não martelar o YouTube
  /// (nem a máquina) numa aba com muitos álbuns.
  static const _maxConcurrentCoverFetches = 2;

  final List<YoutubeAlbumRef> _coverQueue = [];
  final Set<String> _coverRequested = {};
  int _coverFetchesInFlight = 0;

  /// Ligado quando o YouTube começa a limitar: as capas que faltam param de
  /// ser pedidas (insistir só piora o bloqueio, e capa é só enfeite).
  bool _coverFetchingStopped = false;

  ChannelBrowserNotifier(this._ref) : super(const ChannelBrowserState());

  void openChannel(YoutubeChannelRef channel) {
    _channelGeneration++;
    _albumGeneration++;
    _resetCoverFetching();
    state = ChannelBrowserState(channel: channel);
    _loadTab(ChannelTab.songs);
  }

  void closeChannel() {
    if (state.channel == null) return;
    _channelGeneration++;
    _albumGeneration++;
    _resetCoverFetching();
    state = const ChannelBrowserState();
  }

  void _resetCoverFetching() {
    _coverQueue.clear();
    _coverRequested.clear();
    _coverFetchingStopped = false;
  }

  void selectTab(ChannelTab tab) {
    if (state.channel == null) return;
    state = state.copyWith(tab: tab);
    final tabState = state.tabState(tab);
    if (!tabState.loaded && !tabState.isLoading) _loadTab(tab);
  }

  /// "Tentar de novo" depois de um erro.
  void reloadTab(ChannelTab tab) {
    if (state.channel == null) return;
    _loadTab(tab);
  }

  void openAlbum(YoutubeAlbumRef album) {
    _albumGeneration++;
    state = state.copyWith(
      openAlbum: album,
      album: const AlbumTracksState(isLoading: true),
    );
    _loadAlbum(album);
  }

  void closeAlbum() {
    _albumGeneration++;
    state = state.copyWith(
      clearOpenAlbum: true,
      album: const AlbumTracksState(),
    );
  }

  void reloadAlbum() {
    final album = state.openAlbum;
    if (album == null) return;
    state = state.copyWith(album: const AlbumTracksState(isLoading: true));
    _loadAlbum(album);
  }

  Future<void> _loadTab(ChannelTab tab) async {
    final channel = state.channel;
    if (channel == null) return;
    final generation = _channelGeneration;

    _setTab(tab, const ChannelTabState(isLoading: true));

    try {
      final youtube = await _ref.read(youtubeClientProvider.future);

      final ChannelTabState loaded;
      final String? avatarUrl;
      final String? bannerUrl;
      if (tab == ChannelTab.albums) {
        final data = await youtube.getChannelAlbums(channel);
        loaded = ChannelTabState(loaded: true, albums: data.items);
        avatarUrl = data.avatarUrl;
        bannerUrl = data.bannerUrl;
      } else {
        final data = await youtube.getChannelVideos(channel, tab);
        loaded = ChannelTabState(loaded: true, videos: data.items);
        avatarUrl = data.avatarUrl;
        bannerUrl = data.bannerUrl;
      }

      if (!mounted || generation != _channelGeneration) return;
      _setTab(tab, loaded);
      _applyChannelArt(avatarUrl: avatarUrl, bannerUrl: bannerUrl);
    } catch (e) {
      if (!mounted || generation != _channelGeneration) return;
      // ignore: avoid_print
      print('Sonora [canal]: falha ao carregar a aba ${tab.name} de '
          '"${channel.name}": $e');
      _setTab(tab, ChannelTabState(errorMessage: _friendlyError(e)));
    }
  }

  Future<void> _loadAlbum(YoutubeAlbumRef album) async {
    final generation = _albumGeneration;
    try {
      final youtube = await _ref.read(youtubeClientProvider.future);
      final tracks = await youtube.getAlbumTracks(album);
      if (!mounted || generation != _albumGeneration) return;
      state = state.copyWith(album: AlbumTracksState(tracks: tracks));

      // As faixas já estão aqui: a capa do álbum (a do 1º vídeo) sai de
      // graça, sem nenhuma leitura a mais.
      final cover = albumCoverFromTracks(tracks);
      if (cover != null) _setAlbumCover(album.id, cover);
    } catch (e) {
      if (!mounted || generation != _albumGeneration) return;
      // ignore: avoid_print
      print('Sonora [canal]: falha ao carregar o álbum "${album.title}": $e');
      state = state.copyWith(
        album: AlbumTracksState(errorMessage: _friendlyError(e)),
      );
    }
  }

  /// Pede a capa de [album] — a miniatura do PRIMEIRO vídeo dele — quando a
  /// listagem não trouxe nenhuma. Chamado por cada linha de álbum ao
  /// aparecer na tela (a lista é preguiçosa, então só os álbuns visíveis
  /// pedem), e seguro de chamar várias vezes: cada álbum é lido no máximo
  /// uma vez por canal aberto.
  ///
  /// Não muda o estado de forma síncrona (pode ser chamado durante a
  /// construção de um widget): o trabalho só começa no próximo microtask.
  void requestAlbumCover(YoutubeAlbumRef album) {
    final known = album.thumbnailUrl;
    if (known != null && known.isNotEmpty) return;
    if (_coverFetchingStopped) return;
    if (!_coverRequested.add(album.id)) return;

    _coverQueue.add(album);
    scheduleMicrotask(_pumpCoverQueue);
  }

  void _pumpCoverQueue() {
    while (mounted &&
        !_coverFetchingStopped &&
        _coverFetchesInFlight < _maxConcurrentCoverFetches &&
        _coverQueue.isNotEmpty) {
      final album = _coverQueue.removeAt(0);
      _coverFetchesInFlight++;
      _fetchAlbumCover(album, _channelGeneration).whenComplete(() {
        _coverFetchesInFlight--;
        _pumpCoverQueue();
      });
    }
  }

  Future<void> _fetchAlbumCover(YoutubeAlbumRef album, int generation) async {
    try {
      final youtube = await _ref.read(youtubeClientProvider.future);
      final cover = await youtube.getAlbumCoverUrl(album);
      if (!mounted || generation != _channelGeneration || cover == null) return;
      _setAlbumCover(album.id, cover);
    } on YoutubeRateLimitException {
      if (generation == _channelGeneration) {
        _coverFetchingStopped = true;
        _coverQueue.clear();
      }
    } catch (_) {
      // Capa é só enfeite: se falhar, o álbum fica com o ícone e nada mais
      // acontece (nenhuma mensagem de erro por causa disto).
    }
  }

  /// Grava a capa de um álbum na lista da aba Álbuns e, se for o álbum
  /// aberto, também no detalhe dele. Não faz nada (e não notifica) se o
  /// álbum já tinha capa ou não está em nenhum dos dois lugares.
  void _setAlbumCover(String albumId, String coverUrl) {
    var tabs = state.tabs;

    final albumsTab = tabs[ChannelTab.albums];
    if (albumsTab != null) {
      var changed = false;
      final updated = <YoutubeAlbumRef>[];
      for (final album in albumsTab.albums) {
        if (album.id == albumId && album.thumbnailUrl == null) {
          updated.add(album.copyWith(thumbnailUrl: coverUrl));
          changed = true;
        } else {
          updated.add(album);
        }
      }
      if (changed) {
        tabs = {
          ...tabs,
          ChannelTab.albums: ChannelTabState(
            isLoading: albumsTab.isLoading,
            loaded: albumsTab.loaded,
            errorMessage: albumsTab.errorMessage,
            videos: albumsTab.videos,
            albums: updated,
          ),
        };
      }
    }

    final open = state.openAlbum;
    final updatedOpen = (open != null &&
            open.id == albumId &&
            open.thumbnailUrl == null)
        ? open.copyWith(thumbnailUrl: coverUrl)
        : null;

    if (identical(tabs, state.tabs) && updatedOpen == null) return;
    state = state.copyWith(tabs: tabs, openAlbum: updatedOpen);
  }

  void _setTab(ChannelTab tab, ChannelTabState tabState) {
    state = state.copyWith(tabs: {...state.tabs, tab: tabState});
  }

  /// Guarda o logo/banner do canal assim que alguma aba o traz — a busca
  /// em si não conhece o avatar, só uma aba lida do canal conhece.
  void _applyChannelArt({String? avatarUrl, String? bannerUrl}) {
    final channel = state.channel;
    if (channel == null) return;
    final needsAvatar = avatarUrl != null && channel.avatarUrl == null;
    final needsBanner = bannerUrl != null && channel.bannerUrl == null;
    if (!needsAvatar && !needsBanner) return;
    state = state.copyWith(
      channel: channel.copyWith(
        avatarUrl: needsAvatar ? avatarUrl : null,
        bannerUrl: needsBanner ? bannerUrl : null,
      ),
    );
  }

  String _friendlyError(Object error) {
    if (error is YoutubeRateLimitException) {
      return 'O YouTube está limitando temporariamente as requisições feitas '
          'deste computador. Espere alguns minutos e tente de novo.';
    }
    return 'Não foi possível carregar isto agora. Confira sua conexão com a '
        'internet e tente de novo.';
  }
}

/// `autoDispose`, como `webSearchNotifierProvider`: a área de canal vive
/// junto com a tela Buscar e some quando o usuário sai dela.
final channelBrowserProvider = StateNotifierProvider.autoDispose<
    ChannelBrowserNotifier, ChannelBrowserState>((ref) {
  return ChannelBrowserNotifier(ref);
});
