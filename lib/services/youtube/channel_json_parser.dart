import '../../data/models/youtube_channel.dart';
import '../../data/models/youtube_search_result.dart';

/// Funções puras (sem rede, sem processo) que convertem o JSON do yt-dlp
/// nos modelos do app. Ficam separadas de `YoutubeClient` justamente para
/// poderem ser testadas só com um JSON de exemplo (ver
/// `test/channel_json_parser_test.dart`).
///
/// Todos os formatos de JSON assumidos aqui vêm de como o `yt-dlp
/// --flat-playlist --dump-single-json` costuma se comportar — nenhum foi
/// conferido contra o YouTube de verdade (ver "Limitações de ambiente" no
/// pedido original). Os pontos mais incertos estão marcados com
/// `ASSUNÇÃO NÃO TESTADA`.

/// Converte uma entrada de vídeo do yt-dlp (entrada de `--flat-playlist`, ou
/// o dump completo de um vídeo — os dois usam os mesmos nomes de campo) num
/// [YoutubeSearchResult].
///
/// Lança se a entrada não tiver `id` (string) — quem lê listas inteiras deve
/// usar [parseChannelVideoEntries], que ignora entradas assim.
YoutubeSearchResult youtubeSearchResultFromJson(Map<String, dynamic> data) {
  return YoutubeSearchResult(
    videoId: data['id'] as String,
    title: (data['title'] as String?) ?? '(sem título)',
    channelName: (data['channel'] ?? data['uploader']) as String? ?? '',
    thumbnailUrl: bestThumbnail(data),
    duration: durationOf(data['duration']),
    channelId: _nonEmptyString(data['channel_id']),
    // `uploader_url` como alternativa: em alguns extratores só ele vem.
    channelUrl:
        _nonEmptyString(data['channel_url']) ?? _nonEmptyString(data['uploader_url']),
    viewCount: _intOrNull(data['view_count']),
  );
}

String? bestThumbnail(Map<String, dynamic> data) {
  final single = data['thumbnail'];
  if (single is String && single.isNotEmpty) return single;

  final thumbnails = data['thumbnails'];
  if (thumbnails is List && thumbnails.isNotEmpty) {
    final last = thumbnails.last;
    if (last is Map && last['url'] is String) return last['url'] as String;
  }
  return null;
}

Duration durationOf(Object? raw) {
  if (raw is num) return Duration(milliseconds: (raw * 1000).round());
  return Duration.zero;
}

/// Lê a lista de vídeos de um dump de aba de canal (`/videos`, `/streams`,
/// `/search?query=...`). Entradas sem `id` de texto são ignoradas em vez de
/// derrubar a lista toda. Entradas sem nome de canal herdam
/// [fallbackChannelName] — na aba de um canal, o canal é sabidamente o dono
/// da aba.
List<YoutubeSearchResult> parseChannelVideoEntries(
  Map<String, dynamic> dump, {
  required String fallbackChannelName,
}) {
  final entries = _entriesOf(dump);
  final results = <YoutubeSearchResult>[];
  for (final entry in entries) {
    if (entry['id'] is! String) continue;
    final result = youtubeSearchResultFromJson(entry);
    results.add(
      result.channelName.isEmpty
          ? result.copyWith(channelName: fallbackChannelName)
          : result,
    );
  }
  return results;
}

/// Lê a lista de álbuns (playlists) de um dump de aba de canal
/// (`/releases` ou `/playlists`).
///
/// ASSUNÇÃO NÃO TESTADA: em modo flat, cada álbum vem como uma entrada
/// "url" apontando para uma playlist (`ie_key: YoutubeTab`, `id` da
/// playlist, `url` `https://www.youtube.com/playlist?list=...`, `title`,
/// e `thumbnails`). Entradas que parecem vídeos soltos (a aba
/// `/releases` de um canal que não é de música pode listar vídeos) são
/// ignoradas.
List<YoutubeAlbumRef> parseChannelAlbumEntries(Map<String, dynamic> dump) {
  final seen = <String>{};
  final albums = <YoutubeAlbumRef>[];

  for (final entry in _entriesOf(dump)) {
    final id = entry['id'];
    if (id is! String || id.isEmpty) continue;
    if (!_looksLikePlaylistEntry(entry)) continue;
    if (!seen.add(id)) continue;

    final rawUrl = entry['url'];
    final url = (rawUrl is String && rawUrl.startsWith('http'))
        ? rawUrl
        : 'https://www.youtube.com/playlist?list=$id';

    albums.add(
      YoutubeAlbumRef(
        id: id,
        title: (entry['title'] as String?) ?? '(sem título)',
        url: url,
        thumbnailUrl: bestThumbnail(entry),
      ),
    );
  }
  return albums;
}

bool _looksLikePlaylistEntry(Map<String, dynamic> entry) {
  final ieKey = entry['ie_key'];
  if (ieKey == 'YoutubeTab') return true;
  if (ieKey == 'Youtube') return false; // um vídeo, não uma playlist.
  final url = entry['url'];
  return url is String && url.contains('list=');
}

/// Miniatura que o YouTube mantém para QUALQUER vídeo, montada só a partir
/// do ID — não depende de o yt-dlp ter devolvido `thumbnails`. É o plano B
/// da capa de um álbum (ver [albumCoverFromTracks]).
String thumbnailForVideoId(String videoId) =>
    'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

/// Capa de um álbum = capa do PRIMEIRO vídeo dele. Em vez de procurar uma
/// capa "de verdade" (que muitas vezes não existe na listagem), usa a
/// miniatura da primeira faixa — num álbum do YouTube Music, a 1ª faixa é
/// um vídeo gerado com a própria arte do álbum.
///
/// Se o yt-dlp não devolveu miniatura para a faixa, monta a URL a partir do
/// ID do vídeo ([thumbnailForVideoId]); só devolve `null` se o álbum não
/// tem nenhuma faixa.
String? albumCoverFromTracks(List<YoutubeSearchResult> tracks) {
  if (tracks.isEmpty) return null;
  final first = tracks.first;
  final thumbnail = first.thumbnailUrl;
  if (thumbnail != null && thumbnail.isNotEmpty) return thumbnail;
  return thumbnailForVideoId(first.videoId);
}

/// Avatar e banner de um canal, lidos do nível de cima do dump de uma aba.
class ChannelArt {
  final String? avatarUrl;
  final String? bannerUrl;

  const ChannelArt({this.avatarUrl, this.bannerUrl});

  static const none = ChannelArt();
}

/// ASSUNÇÃO NÃO TESTADA: o dump de uma aba de canal traz, em
/// `thumbnails` (nível de cima, não nas entradas), itens com `id`
/// `avatar_uncropped` e `banner_uncropped`. Se não vierem, a tela usa um
/// ícone no lugar do logo — não quebra nada.
ChannelArt parseChannelArt(Map<String, dynamic> dump) {
  final thumbnails = dump['thumbnails'];
  if (thumbnails is! List) return ChannelArt.none;

  String? avatar;
  String? banner;
  for (final item in thumbnails) {
    if (item is! Map) continue;
    final id = item['id'];
    final url = item['url'];
    if (id is! String || url is! String || url.isEmpty) continue;
    if (id.contains('avatar')) avatar ??= url;
    if (id.contains('banner')) banner ??= url;
  }
  return ChannelArt(avatarUrl: avatar, bannerUrl: banner);
}

/// Ordena da mais para a menos vista. Entradas sem `viewCount` vão para o
/// fim; empates (e as sem contagem entre si) mantêm a ordem original — não
/// dependemos de `List.sort` ser estável (não é garantido).
List<YoutubeSearchResult> sortByViewsDescending(
  List<YoutubeSearchResult> results,
) {
  final indexed = results.asMap().entries.toList();
  indexed.sort((a, b) {
    final aViews = a.value.viewCount;
    final bViews = b.value.viewCount;
    if (aViews == null && bViews == null) return a.key.compareTo(b.key);
    if (aViews == null) return 1;
    if (bViews == null) return -1;
    final byViews = bViews.compareTo(aViews);
    return byViews != 0 ? byViews : a.key.compareTo(b.key);
  });
  return indexed.map((e) => e.value).toList();
}

List<Map<String, dynamic>> _entriesOf(Map<String, dynamic> dump) {
  final entries = dump['entries'];
  if (entries is! List) return const [];
  return entries.whereType<Map<String, dynamic>>().toList();
}

String? _nonEmptyString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int? _intOrNull(Object? value) => value is num ? value.toInt() : null;
