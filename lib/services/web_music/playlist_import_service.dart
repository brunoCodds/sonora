import '../../data/models/youtube_search_result.dart';
import '../spotify/spotify_client.dart';
import '../youtube/youtube_client.dart';

enum PlaylistLinkType { youtube, spotify, unknown }

/// Liga/desliga a importação de playlist do Spotify. Desligada desde
/// set/2026: em fevereiro a Spotify trocou `GET /playlists/{id}/tracks`
/// por `GET /playlists/{id}/items`, que só devolve o conteúdo de uma
/// playlist para quem está autenticado como dono ou colaborador dela —
/// impossível com Client Credentials (a forma como o Sonora se
/// autentica hoje, sem login de usuário nenhum; não é algo que dê pra
/// contornar por playlist, é estrutural ao tipo de credencial).
/// Reativar exige implementar login de verdade em [SpotifyClient]
/// (Authorization Code + PKCE, com redirect local em 127.0.0.1) e trocar
/// `getPlaylistTracks` pro endpoint novo — decisão de deixar isso de
/// lado por enquanto e manter só a importação do YouTube. `getPlaylistName`,
/// `extractPlaylistId` e o resto de [SpotifyClient] continuam intactos.
bool spotifyPlaylistImportEnabled = false;

/// Resultado de uma importação: quantas faixas viraram músicas
/// tocáveis, e os títulos das que não foi possível encontrar (relevante
/// principalmente para importação do Spotify, onde cada faixa depende
/// de achar uma correspondência no YouTube).
class PlaylistImportResult {
  final String? playlistName;
  final List<YoutubeSearchResult> matched;
  final List<String> notFoundTitles;

  const PlaylistImportResult({
    required this.playlistName,
    required this.matched,
    required this.notFoundTitles,
  });
}

/// Orquestra a importação de uma playlist colada pelo usuário. Hoje só o
/// YouTube está ativo (lido direto); o caminho do Spotify (metadados via
/// Spotify, faixa tocável encontrada com uma busca correspondente no
/// YouTube) existe mas está desligado — ver [spotifyPlaylistImportEnabled].
class PlaylistImportService {
  final YoutubeClient _youtube;
  final SpotifyClient _spotify;

  PlaylistImportService(this._youtube, this._spotify);

  static PlaylistLinkType detectLinkType(String text) {
    final trimmed = text.trim();
    if (trimmed.contains('spotify.com/playlist')) return PlaylistLinkType.spotify;
    if (trimmed.contains('youtube.com/playlist') || trimmed.contains('list=')) {
      return PlaylistLinkType.youtube;
    }
    return PlaylistLinkType.unknown;
  }

  /// [onProgress] é chamado com (processadas, total) — só tem sentido
  /// para importação do Spotify, onde cada faixa exige uma busca
  /// separada no YouTube; para uma playlist do YouTube a leitura já vem
  /// pronta de uma vez.
  Future<PlaylistImportResult> importFromLink(
    String link, {
    void Function(int done, int total)? onProgress,
  }) async {
    final type = detectLinkType(link);

    switch (type) {
      case PlaylistLinkType.youtube:
        return _importYoutubePlaylist(link);
      case PlaylistLinkType.spotify:
        if (!spotifyPlaylistImportEnabled) {
          throw StateError(
            'A importação de playlists do Spotify está temporariamente '
            'desativada. Desde fevereiro de 2026 a Spotify exige login do '
            'usuário para ler o conteúdo de uma playlist — fica para uma '
            'próxima versão. Importar do YouTube continua funcionando.',
          );
        }
        return _importSpotifyPlaylist(link, onProgress: onProgress);
      case PlaylistLinkType.unknown:
        throw ArgumentError(
          'Não reconheci esse link como uma playlist do YouTube.',
        );
    }
  }

  Future<PlaylistImportResult> _importYoutubePlaylist(String link) async {
    final name = await _youtube.getPlaylistTitle(link);
    final videos = await _youtube.getPlaylistVideos(link);
    return PlaylistImportResult(
      playlistName: name,
      matched: videos,
      notFoundTitles: const [],
    );
  }

  Future<PlaylistImportResult> _importSpotifyPlaylist(
    String link, {
    void Function(int done, int total)? onProgress,
  }) async {
    final playlistId = SpotifyClient.extractPlaylistId(link);
    if (playlistId == null) {
      throw ArgumentError('Link de playlist do Spotify inválido.');
    }

    final name = await _spotify.getPlaylistName(playlistId);
    final tracks = await _spotify.getPlaylistTracks(playlistId);

    final matched = <YoutubeSearchResult>[];
    final notFound = <String>[];

    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      try {
        final results = await _youtube.search(track.searchQuery, limit: 5);
        final best = _pickBestMatch(results, track.duration);
        if (best != null) {
          matched.add(best);
        } else {
          notFound.add('${track.name} — ${track.artistsJoined}');
        }
      } catch (_) {
        notFound.add('${track.name} — ${track.artistsJoined}');
      }
      onProgress?.call(i + 1, tracks.length);
    }

    return PlaylistImportResult(
      playlistName: name,
      matched: matched,
      notFoundTitles: notFound,
    );
  }

  /// Entre os primeiros resultados de busca para uma faixa do Spotify,
  /// prefere o de duração mais próxima da faixa original (quando ela é
  /// conhecida) — um jeito simples de evitar pegar um remix/cover muito
  /// mais longo ou curto que a faixa de verdade. Sem duração de
  /// referência, ou sem resultados, cai para "o primeiro resultado" /
  /// `null`.
  YoutubeSearchResult? _pickBestMatch(
    List<YoutubeSearchResult> results,
    Duration? referenceDuration,
  ) {
    if (results.isEmpty) return null;
    if (referenceDuration == null) return results.first;

    YoutubeSearchResult? best;
    var bestDiff = const Duration(days: 9999);
    for (final result in results) {
      final diff = (result.duration - referenceDuration).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = result;
      }
    }
    return best ?? results.first;
  }
}
