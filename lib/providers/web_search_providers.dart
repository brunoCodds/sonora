import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/youtube_channel.dart';
import '../data/models/youtube_search_result.dart';
import '../services/youtube/youtube_client.dart';
import 'service_providers.dart';

class WebSearchState {
  final String query;
  final List<YoutubeSearchResult> results;
  final bool isLoading;
  final String? errorMessage;

  /// Canal do card que aparece abaixo das 2 músicas do topo (ver
  /// `pickChannelForResults`), ou `null` se nenhum resultado trouxe dados
  /// de canal suficientes. Nasce sem logo e ganha [YoutubeChannelRef.avatarUrl]
  /// logo depois, quando a leitura leve do canal termina (ver
  /// `WebSearchNotifier._loadChannelArt`).
  final YoutubeChannelRef? channel;

  const WebSearchState({
    this.query = '',
    this.results = const [],
    this.isLoading = false,
    this.errorMessage,
    this.channel,
  });

  WebSearchState copyWith({
    String? query,
    List<YoutubeSearchResult>? results,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    YoutubeChannelRef? channel,
    bool clearChannel = false,
  }) {
    return WebSearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      channel: clearChannel ? null : (channel ?? this.channel),
    );
  }
}

/// Estado da aba Buscar. Debounça a digitação (400ms) antes de
/// disparar uma busca de verdade, para não martelar o YouTube a cada
/// tecla.
class WebSearchNotifier extends StateNotifier<WebSearchState> {
  final Ref _ref;
  Timer? _debounce;

  WebSearchNotifier(this._ref) : super(const WebSearchState());

  void setQuery(String query) {
    state = state.copyWith(query: query);
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      state = state.copyWith(
        results: const [],
        isLoading: false,
        clearError: true,
        clearChannel: true,
      );
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final youtube = await _ref.read(youtubeClientProvider.future);
      final results = await youtube.search(query);
      // O texto pode ter mudado de novo enquanto a busca rodava — não
      // aplica um resultado que já não corresponde ao que está no campo.
      if (state.query != query) return;

      final channel = pickChannelForResults(results);
      state = state.copyWith(
        results: results,
        isLoading: false,
        channel: channel,
        clearChannel: channel == null,
      );

      // Não espera: a lista aparece na hora e o logo entra quando chegar.
      if (channel != null) _loadChannelArt(query, channel, youtube);
    } catch (_) {
      if (state.query != query) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Não foi possível buscar agora. Confira sua conexão com a internet.',
      );
    }
  }

  /// Busca o logo/banner do canal do card em segundo plano — a busca em si
  /// não traz o avatar, só a leitura de uma aba do canal (ver
  /// `YoutubeClient.getChannelArt`, uma requisição leve e com cache).
  ///
  /// `getChannelArt` nunca lança (devolve "sem arte" em qualquer falha), e
  /// aqui nada é mostrado de erro: sem logo, o card só fica com o ícone.
  Future<void> _loadChannelArt(
    String query,
    YoutubeChannelRef channel,
    YoutubeClient youtube,
  ) async {
    final art = await youtube.getChannelArt(channel);
    if (art.avatarUrl == null && art.bannerUrl == null) return;

    // Já foi para outra busca, ou outro canal ocupa o card: descarta.
    if (!mounted) return;
    final current = state.channel;
    if (state.query != query || current == null) return;
    if (current.key != channel.key) return;

    state = state.copyWith(
      channel: current.copyWith(
        avatarUrl: art.avatarUrl,
        bannerUrl: art.bannerUrl,
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final webSearchNotifierProvider =
    StateNotifierProvider.autoDispose<WebSearchNotifier, WebSearchState>((ref) {
  return WebSearchNotifier(ref);
});
