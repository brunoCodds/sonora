import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/models/youtube_channel.dart';
import '../../data/models/youtube_search_result.dart';
import 'channel_json_parser.dart';
import 'ytdlp_process.dart';

/// URL de streaming de áudio já pronta para tocar, junto dos cabeçalhos
/// HTTP que precisam acompanhá-la.
///
/// O `media_kit` aceita passar headers customizados junto da URL — e a URL
/// resolvida pelo yt-dlp (`googlevideo.com/videoplayback?...`) às vezes só
/// funciona se quem for buscá-la mandar o mesmo `User-Agent` que o yt-dlp
/// usou para resolvê-la. Por isso [getAudioStreamUrl] devolve os dois
/// juntos, em vez de só a URL.
class ResolvedAudioStream {
  final String url;
  final Map<String, String> httpHeaders;

  const ResolvedAudioStream({required this.url, required this.httpHeaders});
}

/// Encapsula toda a interação com o YouTube (busca, playlists, resolução
/// de stream de áudio pra tocar e download) chamando o `yt-dlp.exe`
/// empacotado como processo externo — ver [YtDlpProcess].
///
/// Não usa a Data API v3 (nenhuma chave necessária): busca, leitura de
/// playlist, resolução de stream e download passam todos por aqui.
class YoutubeClient {
  YoutubeClient._();

  /// Preenchido quando uma resolução de stream ou um download leva um
  /// [YoutubeRateLimitException] — ver [_ensureNotInRateLimitCooldown].
  DateTime? _rateLimitedUntil;

  /// Tempo mínimo de espera, dentro desta mesma sessão do app, depois de
  /// um [YoutubeRateLimitException], antes de deixar tentar de novo.
  ///
  /// Esse erro específico é a página de "confirme que você não é um
  /// robô" do próprio Google (ou um HTTP 429) — um bloqueio por
  /// IP/rede, não algo ligado a qual vídeo foi pedido. Repetir a
  /// tentativa em seguida não tem chance real de dar certo e só
  /// arrisca alongar o bloqueio, então preferimos falhar na hora,
  /// localmente, sem gerar mais tráfego para o YouTube.
  static const _rateLimitCooldown = Duration(minutes: 3);

  /// Cria o cliente, garantindo que o `yt-dlp.exe` empacotado existe antes
  /// de devolver — preferível a deixar isso estourar mais tarde, na
  /// primeira busca, com um erro de processo mais difícil de entender.
  static Future<YoutubeClient> create() async {
    YtDlpProcess.resolveExecutable();
    return YoutubeClient._();
  }

  /// Busca vídeos no YouTube. `limit` controla direto quantos resultados o
  /// yt-dlp busca (via `ytsearch<limit>:`), em vez de buscar um tanto fixo
  /// e cortar depois — mais magro, e não gasta à toa o "orçamento" de
  /// requisição que o YouTube dá antes de bloquear.
  Future<List<YoutubeSearchResult>> search(String query, {int limit = 30}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final stdout = await YtDlpProcess.runCapturingJson([
      '--flat-playlist',
      '--dump-single-json',
      'ytsearch$limit:$trimmed',
    ]);
    final data = jsonDecode(stdout) as Map<String, dynamic>;
    final entries = (data['entries'] as List?) ?? const [];
    return entries.cast<Map<String, dynamic>>().map(_toSearchResult).toList();
  }

  Future<YoutubeSearchResult> getVideo(String videoId) async {
    final info = await _fetchVideoInfo(videoId);
    return _toSearchResult(info);
  }

  /// Roda o yt-dlp em modo "flat playlist" (`--dump-single-json`) e
  /// devolve o JSON já decodificado. Usado tanto por [getPlaylistTitle]
  /// quanto por [getPlaylistVideos] — que agora só diferem no valor de
  /// [playlistEnd], nunca no resto dos argumentos.
  Future<Map<String, dynamic>> _dumpFlatPlaylistJson(
    String playlistUrlOrId, {
    int? playlistEnd,
  }) async {
    final stdout = await YtDlpProcess.runCapturingJson([
      '--flat-playlist',
      // Explícito, para não depender do comportamento padrão do yt-dlp
      // quando o link tem `v=` e `list=` juntos (ex.: um link de vídeo
      // copiado de dentro de uma playlist) — isto é sempre para ler a
      // playlist, nunca só o vídeo.
      '--yes-playlist',
      if (playlistEnd != null) ...['--playlist-end', '$playlistEnd'],
      '--dump-single-json',
      playlistUrlOrId,
    ]);
    return jsonDecode(stdout) as Map<String, dynamic>;
  }

  /// Nome da playlist — usado para pré-preencher o nome da playlist
  /// criada no app ao importar. `null` se não conseguir ler (link
  /// inválido, playlist privada, etc.).
  Future<String?> getPlaylistTitle(String playlistUrlOrId) async {
    try {
      // Propositalmente SEM `playlistEnd` aqui (ver sonora-prompt.md,
      // item 1): antes isto passava `playlistEnd: 1` como otimização
      // para não puxar a playlist inteira só pra ler o título, mas essa
      // otimização nunca foi testada contra o YouTube de verdade — era
      // uma aposta de que o JSON "achatado" de um único item ainda viria
      // envelopado no objeto de playlist (com `title`/`entries`), e não
      // há garantia disso. Se a aposta estivesse errada, o sintoma seria
      // silencioso (`data['title']` só retornaria `null`, ou pior, o
      // título do primeiro vídeo em vez do da playlist — nenhum dos dois
      // gera exceção). Sem o limite, o comando fica idêntico ao de
      // [getPlaylistVideos] (só o `playlistEnd` muda), então o formato do
      // JSON não tem como divergir entre os dois — simplicidade antes de
      // otimização prematura, como já era o espírito da migração p/ yt-dlp.
      final data = await _dumpFlatPlaylistJson(playlistUrlOrId);
      return data['title'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Lê os vídeos de uma playlist do YouTube (aceita link completo ou só
  /// o ID). Limitado a [maxItems] por segurança — o próprio yt-dlp já
  /// para de buscar ao chegar nesse limite (`--playlist-end`), em vez de
  /// buscar tudo e cortar depois.
  Future<List<YoutubeSearchResult>> getPlaylistVideos(
    String playlistUrlOrId, {
    int maxItems = 500,
  }) async {
    final data = await _dumpFlatPlaylistJson(
      playlistUrlOrId,
      playlistEnd: maxItems,
    );
    final entries = (data['entries'] as List?) ?? const [];
    return entries
        .cast<Map<String, dynamic>>()
        .take(maxItems)
        .map(_toSearchResult)
        .toList();
  }

  // ---------------------------------------------------------------------
  // Canais (aba Buscar → card do canal → Músicas / Álbuns / Ao vivo / Shows)
  //
  // Tudo aqui é SÓ LEITURA, no mesmo padrão de [getPlaylistVideos]
  // (`--flat-playlist --dump-single-json <url>`, via
  // [_dumpFlatPlaylistJson]). Nenhum endereço de aba abaixo foi conferido
  // contra o YouTube de verdade — rodar `tools/verificar_canal_ytdlp.ps1`
  // no Windows é o primeiro passo antes de confiar nisto.
  // ---------------------------------------------------------------------

  /// Quantos vídeos recentes do canal a aba Músicas lê antes de ordenar
  /// por visualizações. Cada ~30 vídeos custa uma requisição de página ao
  /// YouTube, então isto é um meio-termo entre completude e velocidade.
  static const _songsScanLimit = 90;

  /// Quantos aparecem de fato na aba Músicas (os mais vistos dos lidos).
  static const _songsShown = 50;

  static const _liveLimit = 40;
  static const _showsLimit = 30;
  static const _albumsLimit = 60;

  /// Termos usados para achar gravações de show. Em inglês e português
  /// juntos porque o app é em português mas muitos artistas publicam em
  /// inglês.
  static const _showsQuery = 'full concert show completo';

  /// Lê uma das abas de vídeos de um canal ([ChannelTab.songs],
  /// [ChannelTab.live] ou [ChannelTab.shows]). Para álbuns, use
  /// [getChannelAlbums].
  ///
  /// Uma aba que o canal simplesmente não tem (comum: muitos canais não
  /// têm `/streams`) vira uma lista vazia, não um erro.
  Future<ChannelTabData<YoutubeSearchResult>> getChannelVideos(
    YoutubeChannelRef channel,
    ChannelTab tab,
  ) async {
    switch (tab) {
      case ChannelTab.songs:
        return _getChannelSongs(channel);
      case ChannelTab.live:
        return _getChannelLive(channel);
      case ChannelTab.shows:
        return _getChannelShows(channel);
      case ChannelTab.albums:
        throw ArgumentError('A aba de álbuns usa getChannelAlbums.');
    }
  }

  /// Aba Músicas: as músicas mais famosas do canal, da mais tocada em diante.
  ///
  /// COMO FUNCIONA (e a limitação real): lê os [_songsScanLimit] uploads
  /// MAIS RECENTES de `<canal>/videos` e ordena esses por `view_count`.
  /// Isso é "os mais vistos entre os uploads recentes", não "os mais vistos
  /// do canal inteiro" — para um canal com centenas de vídeos antigos, um
  /// hit de anos atrás pode ficar de fora. Um jeito de pegar o ranking
  /// verdadeiro seria a ordenação "Popular" do próprio YouTube
  /// (`<canal>/videos?view=0&sort=p`), mas NÃO sei se o yt-dlp respeita
  /// esse parâmetro — o script `tools/verificar_canal_ytdlp.ps1` compara
  /// as duas formas; se a segunda funcionar, basta trocar o endereço aqui
  /// e remover a ordenação local.
  ///
  /// ASSUNÇÃO NÃO TESTADA: `view_count` vem preenchido nas entradas em
  /// modo flat. Se não vier, a lista fica na ordem do YouTube (mais
  /// recentes primeiro) e a tela não mostra contagem.
  Future<ChannelTabData<YoutubeSearchResult>> _getChannelSongs(
    YoutubeChannelRef channel,
  ) async {
    final dump = await _dumpChannelTab(
      '${channel.baseUrl}/videos',
      limit: _songsScanLimit,
    );
    if (dump == null) return _emptyVideos();

    final videos = parseChannelVideoEntries(
      dump,
      fallbackChannelName: channel.name,
    );
    final art = parseChannelArt(dump);
    return ChannelTabData(
      items: sortByViewsDescending(videos).take(_songsShown).toList(),
      avatarUrl: art.avatarUrl,
      bannerUrl: art.bannerUrl,
    );
  }

  /// Aba Ao vivo: transmissões ao vivo do canal (as em andamento e as já
  /// encerradas, que ficam como vídeo), da mais recente para a mais antiga
  /// — a ordem do próprio YouTube em `<canal>/streams`.
  Future<ChannelTabData<YoutubeSearchResult>> _getChannelLive(
    YoutubeChannelRef channel,
  ) async {
    final dump = await _dumpChannelTab(
      '${channel.baseUrl}/streams',
      limit: _liveLimit,
    );
    if (dump == null) return _emptyVideos();

    final art = parseChannelArt(dump);
    return ChannelTabData(
      items: parseChannelVideoEntries(dump, fallbackChannelName: channel.name),
      avatarUrl: art.avatarUrl,
      bannerUrl: art.bannerUrl,
    );
  }

  /// Aba Shows: gravações de show do canal.
  ///
  /// ASSUNÇÃO NÃO TESTADA (a mais incerta das quatro abas): usa a busca
  /// DENTRO do canal, `<canal>/search?query=<termos>`. Se o yt-dlp não
  /// aceitar esse endereço (erro do processo), cai para uma busca geral
  /// (`ytsearch`, o mesmo comando que [search] já usa e é sabidamente
  /// suportado) filtrada para ficar só com resultados DESTE canal. O
  /// efeito do plano B: só aparecem shows publicados no próprio canal, e
  /// podem ser poucos.
  Future<ChannelTabData<YoutubeSearchResult>> _getChannelShows(
    YoutubeChannelRef channel,
  ) async {
    final query = Uri.encodeQueryComponent(_showsQuery);
    try {
      final dump = await _dumpChannelTab(
        '${channel.baseUrl}/search?query=$query',
        limit: _showsLimit,
      );
      if (dump != null) {
        final art = parseChannelArt(dump);
        return ChannelTabData(
          items: parseChannelVideoEntries(
            dump,
            fallbackChannelName: channel.name,
          ),
          avatarUrl: art.avatarUrl,
          bannerUrl: art.bannerUrl,
        );
      }
    } on YtDlpProcessException {
      // Cai para o plano B abaixo. (Rate limit NÃO é capturado aqui: um
      // YoutubeRateLimitException sobe direto, sem tentar de novo.)
    }

    final all = await search('${channel.name} $_showsQuery', limit: 40);
    final sameChannel = all.where((result) {
      if (channel.id.isNotEmpty) return result.channelId == channel.id;
      return result.channelName == channel.name;
    }).toList();
    return ChannelTabData(items: sameChannel);
  }

  /// Aba Álbuns: os álbuns do artista.
  ///
  /// ASSUNÇÃO NÃO TESTADA: `<canal>/releases` lista os álbuns/singles de um
  /// canal de artista como playlists. Se o canal não tem essa aba (ou ela
  /// vem vazia), tenta `<canal>/playlists` — que pode incluir playlists que
  /// não são álbuns, mas é melhor que uma aba vazia.
  Future<ChannelTabData<YoutubeAlbumRef>> getChannelAlbums(
    YoutubeChannelRef channel,
  ) async {
    var dump = await _dumpChannelTab(
      '${channel.baseUrl}/releases',
      limit: _albumsLimit,
    );
    var albums = dump == null
        ? const <YoutubeAlbumRef>[]
        : parseChannelAlbumEntries(dump);

    if (albums.isEmpty) {
      final fallback = await _dumpChannelTab(
        '${channel.baseUrl}/playlists',
        limit: _albumsLimit,
      );
      if (fallback != null) {
        dump = fallback;
        albums = parseChannelAlbumEntries(fallback);
      }
    }

    final art = dump == null ? ChannelArt.none : parseChannelArt(dump);
    return ChannelTabData(
      items: albums,
      avatarUrl: art.avatarUrl,
      bannerUrl: art.bannerUrl,
    );
  }

  /// Faixas de um álbum — o mesmo caminho de [getPlaylistVideos] (um álbum
  /// é só uma playlist do YouTube).
  Future<List<YoutubeSearchResult>> getAlbumTracks(YoutubeAlbumRef album) {
    return getPlaylistVideos(album.url, maxItems: 100);
  }

  /// Avatares/banners já lidos nesta sessão, por [YoutubeChannelRef.key].
  /// Só guarda leituras que deram certo — uma falha (rede, bloqueio) não
  /// fica "lembrada" e pode ser tentada de novo na próxima busca.
  final Map<String, ChannelArt> _channelArtCache = {};

  /// Leitura LEVE do logo/banner de um canal, para o card que aparece na
  /// busca: lê só 1 vídeo de `<canal>/videos` (`--playlist-end 1`) e usa o
  /// que vem em `thumbnails` no nível de cima do dump (ver
  /// [parseChannelArt]) — o mesmo lugar de onde as abas já tiram o logo.
  ///
  /// Nunca lança: o logo é um enfeite, e a busca não pode falhar por
  /// causa dele. Qualquer erro (sem rede, bloqueio do YouTube, canal sem
  /// aba de vídeos) devolve [ChannelArt.none], e o card fica com o ícone.
  ///
  /// ASSUNÇÃO NÃO TESTADA: o avatar vem em `thumbnails` do nível de cima
  /// mesmo com `--playlist-end 1`. O script `tools/verificar_canal_ytdlp.ps1`
  /// (etapa 2c) confere exatamente este comando.
  Future<ChannelArt> getChannelArt(YoutubeChannelRef channel) async {
    final cached = _channelArtCache[channel.key];
    if (cached != null) return cached;

    // Em período de bloqueio, nem tenta — e, importante, FORA do `try`
    // abaixo: o `on YoutubeRateLimitException` de lá renova o cooldown, e
    // renová-lo por causa de um logo prolongaria o bloqueio da reprodução
    // e dos downloads sem necessidade.
    try {
      _ensureNotInRateLimitCooldown();
    } on YoutubeRateLimitException {
      return ChannelArt.none;
    }

    try {
      final dump = await _dumpFlatPlaylistJson(
        '${channel.baseUrl}/videos',
        playlistEnd: 1,
      );
      final art = parseChannelArt(dump);
      _channelArtCache[channel.key] = art;
      return art;
    } on YoutubeRateLimitException {
      _rateLimitedUntil = DateTime.now().add(_rateLimitCooldown);
      return ChannelArt.none;
    } catch (_) {
      return ChannelArt.none;
    }
  }

  /// Capa de um álbum: a miniatura do PRIMEIRO vídeo dele (ver
  /// [albumCoverFromTracks]). Lê só 1 item da playlist
  /// (`--playlist-end 1`), então é uma requisição leve — mas é uma por
  /// álbum, por isso quem chama deve limitar quantas rodam ao mesmo tempo
  /// (ver `ChannelBrowserNotifier.requestAlbumCover`).
  ///
  /// Devolve `null` se o álbum não tem faixa nenhuma; lança se a leitura
  /// falhar (quem chama decide ignorar, já que capa é só enfeite).
  Future<String?> getAlbumCoverUrl(YoutubeAlbumRef album) async {
    final known = album.thumbnailUrl;
    if (known != null && known.isNotEmpty) return known;

    _ensureNotInRateLimitCooldown();
    try {
      final first = await getPlaylistVideos(album.url, maxItems: 1);
      return albumCoverFromTracks(first);
    } on YoutubeRateLimitException {
      _rateLimitedUntil = DateTime.now().add(_rateLimitCooldown);
      rethrow;
    }
  }

  /// Lê uma aba de canal em modo flat. Devolve `null` quando o canal não
  /// tem essa aba (ver [_looksLikeMissingTab]) — quem chama trata como
  /// "vazio". Qualquer outro erro sobe normalmente.
  Future<Map<String, dynamic>?> _dumpChannelTab(
    String url, {
    required int limit,
  }) async {
    try {
      return await _dumpFlatPlaylistJson(url, playlistEnd: limit);
    } on YtDlpProcessException catch (e) {
      if (_looksLikeMissingTab(e.processStderr)) return null;
      rethrow;
    }
  }

  /// ASSUNÇÃO NÃO TESTADA: quando o canal não tem a aba pedida, o yt-dlp
  /// termina com erro e uma mensagem do tipo "This channel does not have a
  /// streams tab". Reconhecer o texto é frágil (pode mudar entre versões do
  /// yt-dlp) — se mudar, o sintoma é a tela mostrar "não foi possível
  /// carregar" em vez de "este canal não tem essa aba".
  bool _looksLikeMissingTab(String? stderr) {
    if (stderr == null) return false;
    final lower = stderr.toLowerCase();
    return lower.contains('does not have a') && lower.contains('tab');
  }

  ChannelTabData<YoutubeSearchResult> _emptyVideos() =>
      const ChannelTabData<YoutubeSearchResult>(items: []);

  /// Resolve uma URL de streaming de áudio pronta para tocar AGORA, junto
  /// dos headers HTTP que precisam acompanhá-la (ver [ResolvedAudioStream]).
  ///
  /// Importante: nunca guarde a URL em lugar nenhum (banco, `Song.path`,
  /// cache) — ela expira depois de algumas horas e precisa ser resolvida
  /// de novo a cada reprodução.
  Future<ResolvedAudioStream> getAudioStreamUrl(String videoId) async {
    _ensureNotInRateLimitCooldown();
    try {
      final info = await _fetchVideoInfo(videoId);
      final format = _pickBestAudioFormat(info);
      return ResolvedAudioStream(
        url: format['url'] as String,
        httpHeaders: _stringHeaders(format['http_headers']),
      );
    } on YoutubeRateLimitException {
      _rateLimitedUntil = DateTime.now().add(_rateLimitCooldown);
      rethrow;
    }
  }

  /// Baixa o melhor áudio disponível para [videoId] direto para dentro de
  /// [directory], nomeado só com o `videoId` (nunca colide com nada já
  /// existente — o nome bonito "Artista - Título" é responsabilidade de
  /// `YoutubeDownloadService`, que renomeia depois).
  ///
  /// Não usa `-x`/`--audio-format`: o áudio fica no formato original
  /// (Opus/M4A/WebM — o que o YouTube tiver disponível), que o
  /// `media_kit` já toca direto, sem precisar do ffmpeg convertendo.
  ///
  /// Devolve o caminho final de verdade do arquivo baixado, **lido do
  /// sistema de arquivos** — não confiamos em nenhum texto que o yt-dlp
  /// imprima de volta (ver [_findDownloadedFile] para o motivo).
  Future<String> downloadAudioTo({
    required String videoId,
    required String directory,
    void Function(double progress)? onProgress,
  }) async {
    _ensureNotInRateLimitCooldown();
    _deleteStaleTempFiles(directory, videoId);
    try {
      await YtDlpProcess.runDownload(
        [
          '-f', 'bestaudio',
          '-o', p.join(directory, '$videoId.%(ext)s'),
          _watchUrl(videoId),
        ],
        onProgress: (progress) => onProgress?.call(progress),
      );
      return _findDownloadedFile(directory, videoId);
    } on YoutubeRateLimitException {
      _rateLimitedUntil = DateTime.now().add(_rateLimitCooldown);
      rethrow;
    }
  }

  /// Acha, olhando o sistema de arquivos diretamente, o arquivo que acabou
  /// de ser baixado para [videoId] dentro de [directory] — e não, como
  /// numa primeira versão desta classe, lendo de volta um caminho impresso
  /// pelo próprio yt-dlp.
  ///
  /// Motivo: o `yt-dlp.exe` é um Python empacotado, e o texto que ele
  /// imprime no stdout passa pelo mecanismo de encoding de texto do
  /// Python — que, com a saída redirecionada para um pipe no Windows
  /// (sempre o nosso caso), pode sair errado para caminhos com acento
  /// (ex.: "Músicas" virando "M?sicas" ou pior), mesmo já pedindo
  /// explicitamente UTF-8 por variável de ambiente (ver
  /// `YtDlpProcess._forceUtf8Environment`). O nome real do arquivo em
  /// disco, por outro lado, é escrito certo (a escrita em si usa a API de
  /// arquivos do Windows, que lida com Unicode corretamente,
  /// independente do encoding do console) — só o texto impresso de volta
  /// é que não é confiável. Por isso lemos o nome direto daqui, do
  /// `Directory.listSync()` do próprio Dart, que reflete o nome real do
  /// arquivo sem passar pelo stdout do processo filho em nenhum momento.
  String _findDownloadedFile(String directory, String videoId) {
    final dir = Directory(directory);
    for (final entry in dir.listSync()) {
      if (entry is File && p.basenameWithoutExtension(entry.path) == videoId) {
        return entry.path;
      }
    }
    throw YtDlpProcessException(
      'O yt-dlp terminou sem erro, mas não encontrei nenhum arquivo para '
      'o vídeo "$videoId" em "$directory".',
    );
  }

  /// Remove, antes de começar um novo download, qualquer arquivo deixado
  /// para trás por uma tentativa anterior com o mesmo [videoId] (ex.: uma
  /// tentativa que baixou certo mas falhou na renomeação final) — sem
  /// isso, [_findDownloadedFile] poderia achar um arquivo antigo, de
  /// extensão errada, em vez do que acabou de ser baixado agora.
  void _deleteStaleTempFiles(String directory, String videoId) {
    final dir = Directory(directory);
    if (!dir.existsSync()) return;
    for (final entry in dir.listSync()) {
      if (entry is File && p.basenameWithoutExtension(entry.path) == videoId) {
        try {
          entry.deleteSync();
        } catch (_) {
          // Não crítico: na pior das hipóteses, _findDownloadedFile abaixo
          // encontra esse arquivo antigo ainda ali — raro o bastante pra
          // não precisar de mais tratamento que isto.
        }
      }
    }
  }

  Future<Map<String, dynamic>> _fetchVideoInfo(String videoId) async {
    final stdout = await YtDlpProcess.runCapturingJson([
      '--dump-json',
      _watchUrl(videoId),
    ]);
    return jsonDecode(stdout) as Map<String, dynamic>;
  }

  String _watchUrl(String videoId) => 'https://www.youtube.com/watch?v=$videoId';

  /// Escolhe o melhor formato só-áudio (`acodec != 'none'` e
  /// `vcodec == 'none'`) pelo maior bitrate (`abr`, com `tbr` como
  /// alternativa — nem todo formato preenche `abr`).
  Map<String, dynamic> _pickBestAudioFormat(Map<String, dynamic> videoInfo) {
    final formats = (videoInfo['formats'] as List?) ?? const [];
    final audioOnly = formats
        .cast<Map<String, dynamic>>()
        .where((f) => f['acodec'] != null && f['acodec'] != 'none' && f['vcodec'] == 'none')
        .toList();

    if (audioOnly.isEmpty) {
      throw StateError('Nenhum stream de áudio disponível para este vídeo.');
    }

    audioOnly.sort((a, b) => _bitrateOf(b).compareTo(_bitrateOf(a)));
    return audioOnly.first;
  }

  double _bitrateOf(Map<String, dynamic> format) {
    final abr = format['abr'];
    if (abr is num) return abr.toDouble();
    final tbr = format['tbr'];
    if (tbr is num) return tbr.toDouble();
    return 0;
  }

  Map<String, String> _stringHeaders(Object? raw) {
    final headers = <String, String>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (key is String && value is String) headers[key] = value;
      });
    }
    return headers;
  }

  void _ensureNotInRateLimitCooldown() {
    final until = _rateLimitedUntil;
    if (until == null) return;
    final remaining = until.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _rateLimitedUntil = null;
      return;
    }
    throw YoutubeRateLimitException(
      'O YouTube limitou as requisições feitas deste computador há '
      'pouco (ver tentativa anterior). Aguarde mais '
      '${remaining.inSeconds}s antes de tentar de novo — tentar de '
      'novo agora só arrisca prolongar o bloqueio.',
    );
  }

  /// Converte um objeto JSON do yt-dlp (uma entrada de `--flat-playlist`,
  /// ou o dump completo de um vídeo — os dois usam os mesmos nomes de
  /// campo) num [YoutubeSearchResult]. A conversão em si mora em
  /// `channel_json_parser.dart` (função pura, testável sem rede).
  YoutubeSearchResult _toSearchResult(Map<String, dynamic> data) =>
      youtubeSearchResultFromJson(data);

  /// Nada a liberar: cada chamada ao yt-dlp é um processo novo e
  /// independente, sem conexão nem estado persistente entre uma chamada e
  /// outra (diferente do `YoutubeExplode` antigo, que mantinha um cliente
  /// HTTP aberto). Mantido só por estabilidade de API, caso algo dependa
  /// de poder chamar isto.
  void close() {}
}
