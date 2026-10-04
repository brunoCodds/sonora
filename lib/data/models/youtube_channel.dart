import 'youtube_search_result.dart';

/// Abas de conteúdo de um canal, na ordem em que aparecem na tela de
/// busca. O mapeamento de cada uma para um endereço do YouTube mora em
/// `YoutubeClient` (ver `getChannelVideos`/`getChannelAlbums`) — aqui só
/// há o identificador.
enum ChannelTab { songs, albums, live, shows }

/// Um canal do YouTube (o "artista" de uma música da web), com o mínimo
/// necessário para abri-lo: de onde ele veio ([id]/[url]) e como mostrá-lo
/// ([name], [avatarUrl], [bannerUrl]).
///
/// Efêmero, como [YoutubeSearchResult]: nunca é gravado no banco.
class YoutubeChannelRef {
  /// ID do canal (`UC...`), ou vazio se o yt-dlp não informou.
  final String id;
  final String name;

  /// URL do canal como o yt-dlp devolveu (pode ser `/channel/UC...` ou
  /// `/@handle`), ou vazia. Para montar o endereço de uma aba use
  /// [baseUrl], não este campo direto.
  final String url;

  /// Logo do canal. Só costuma ser conhecido depois que uma aba do canal
  /// é lida (a busca em si não traz o avatar) — por isso nasce `null` e é
  /// preenchido por `ChannelBrowserNotifier`.
  final String? avatarUrl;
  final String? bannerUrl;

  const YoutubeChannelRef({
    required this.id,
    required this.name,
    required this.url,
    this.avatarUrl,
    this.bannerUrl,
  });

  /// Identificador estável para comparar canais entre si.
  String get key => id.isNotEmpty ? id : url;

  /// Endereço base do canal, sem nenhuma aba no final — é a ele que se
  /// acrescenta `/videos`, `/streams`, `/releases` etc.
  ///
  /// Prefere o formato `/channel/<id>` (estável, não depende de handle)
  /// quando o ID é conhecido; senão, usa [url] limpando barra e aba finais.
  String get baseUrl {
    if (id.startsWith('UC')) return 'https://www.youtube.com/channel/$id';
    var clean = url.trim();
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    return clean.replaceFirst(_trailingTab, '');
  }

  static final _trailingTab = RegExp(
    r'/(videos|streams|releases|playlists|shorts|featured|community|about|search)$',
  );

  YoutubeChannelRef copyWith({
    String? name,
    String? avatarUrl,
    String? bannerUrl,
  }) {
    return YoutubeChannelRef(
      id: id,
      name: name ?? this.name,
      url: url,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
    );
  }

  /// Monta o canal a partir de um resultado de busca. Devolve `null` se o
  /// resultado não trouxe o suficiente para abrir o canal (sem ID válido
  /// nem URL, ou sem nome) — nesse caso a tela simplesmente não mostra o
  /// card, em vez de mostrar um que não abre nada.
  static YoutubeChannelRef? fromResult(YoutubeSearchResult result) {
    final id = result.channelId ?? '';
    final url = result.channelUrl ?? '';
    final name = result.channelName.trim();
    if (name.isEmpty) return null;
    if (!id.startsWith('UC') && url.isEmpty) return null;
    return YoutubeChannelRef(id: id, name: name, url: url);
  }
}

/// Um álbum de um canal — no YouTube, uma playlist (as da aba
/// "Lançamentos"/`releases` de um canal de artista).
class YoutubeAlbumRef {
  /// ID da playlist (geralmente `OLAK5uy_...` para álbuns do YouTube Music).
  final String id;
  final String title;

  /// Endereço da playlist, pronto pra `YoutubeClient.getPlaylistVideos`.
  final String url;
  final String? thumbnailUrl;

  const YoutubeAlbumRef({
    required this.id,
    required this.title,
    required this.url,
    this.thumbnailUrl,
  });

  /// Cópia com a capa preenchida — usada quando a capa só é descoberta
  /// depois que a lista de álbuns já foi mostrada (ver
  /// `ChannelBrowserNotifier.requestAlbumCover`).
  YoutubeAlbumRef copyWith({String? thumbnailUrl}) {
    return YoutubeAlbumRef(
      id: id,
      title: title,
      url: url,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    );
  }
}

/// O que uma aba de canal devolve: a lista em si, mais a arte do canal
/// (avatar/banner) que vem de graça no mesmo comando — assim a tela
/// consegue mostrar o logo sem uma requisição só pra isso.
class ChannelTabData<T> {
  final List<T> items;
  final String? avatarUrl;
  final String? bannerUrl;

  const ChannelTabData({
    required this.items,
    this.avatarUrl,
    this.bannerUrl,
  });
}

/// Escolhe o canal do card que aparece abaixo das 2 músicas do topo.
///
/// Regra: entre os primeiros [sample] resultados, vence o canal que mais
/// aparece; no empate, o que apareceu primeiro (ou seja, o do resultado
/// mais relevante). Isso evita que o card vire o canal de um upload de
/// fã só porque ele calhou de ser o 1º resultado — o canal oficial de um
/// artista costuma aparecer em mais de um resultado da própria busca.
///
/// Resultados sem informação suficiente de canal (ver
/// [YoutubeChannelRef.fromResult]) são ignorados. Devolve `null` se
/// nenhum serve.
YoutubeChannelRef? pickChannelForResults(
  List<YoutubeSearchResult> results, {
  int sample = 10,
}) {
  // Map literal preserva a ordem de inserção — o desempate abaixo depende
  // disso (percorre na ordem da 1ª aparição de cada canal).
  final counts = <String, int>{};
  final refs = <String, YoutubeChannelRef>{};

  final limit = results.length < sample ? results.length : sample;
  for (var i = 0; i < limit; i++) {
    final ref = YoutubeChannelRef.fromResult(results[i]);
    if (ref == null) continue;
    counts[ref.key] = (counts[ref.key] ?? 0) + 1;
    refs.putIfAbsent(ref.key, () => ref);
  }

  String? bestKey;
  var bestCount = 0;
  for (final entry in counts.entries) {
    if (entry.value > bestCount) {
      bestKey = entry.key;
      bestCount = entry.value;
    }
  }
  return bestKey == null ? null : refs[bestKey];
}
