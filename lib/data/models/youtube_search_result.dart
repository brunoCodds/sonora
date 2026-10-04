/// Um vídeo do YouTube, como devolvido pela busca ou pela leitura de
/// uma playlist — antes de virar uma [Song] de verdade no banco.
///
/// Efêmero de propósito: não é persistido diretamente. Vira uma [Song]
/// (`source: SongSource.youtube`) só no momento em que o usuário toca,
/// favorita ou adiciona à fila/playlist — ver
/// `LibraryRepository.upsertWebSong`. Isso evita que o simples ato de
/// rolar pelos resultados de busca já encha o banco de linhas que
/// ninguém nunca vai tocar.
class YoutubeSearchResult {
  final String videoId;
  final String title;

  /// Nome do canal — ocupa o papel de "artista" quando isto virar uma
  /// [Song].
  final String channelName;

  final String? thumbnailUrl;
  final Duration duration;

  /// ID do canal (`UC...`), quando o yt-dlp informou. É o que permite
  /// abrir o canal a partir deste resultado (ver `YoutubeChannelRef`).
  ///
  /// ASSUNÇÃO NÃO TESTADA: em modo `--flat-playlist` cada entrada de
  /// busca/playlist traz `channel_id` e `channel_url` sem custo extra.
  /// Se não vierem, os três campos abaixo ficam `null` e a tela só não
  /// mostra o card de canal — nada mais quebra. Conferir com
  /// `tools/verificar_canal_ytdlp.ps1`.
  final String? channelId;
  final String? channelUrl;

  /// Visualizações, quando o yt-dlp informou (`view_count`). Usado para
  /// ordenar a aba Músicas de um canal da mais para a menos tocada.
  /// `null` = desconhecido (e não "zero").
  final int? viewCount;

  const YoutubeSearchResult({
    required this.videoId,
    required this.title,
    required this.channelName,
    required this.thumbnailUrl,
    required this.duration,
    this.channelId,
    this.channelUrl,
    this.viewCount,
  });

  YoutubeSearchResult copyWith({
    String? channelName,
    String? channelId,
    String? channelUrl,
  }) {
    return YoutubeSearchResult(
      videoId: videoId,
      title: title,
      channelName: channelName ?? this.channelName,
      thumbnailUrl: thumbnailUrl,
      duration: duration,
      channelId: channelId ?? this.channelId,
      channelUrl: channelUrl ?? this.channelUrl,
      viewCount: viewCount,
    );
  }
}
