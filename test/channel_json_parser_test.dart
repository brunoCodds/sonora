// Testes da lógica pura da busca por canal (sem rede, sem yt-dlp, sem banco).
//
// ATENÇÃO: os JSONs de exemplo abaixo foram escritos à mão a partir de como
// o `yt-dlp --flat-playlist --dump-single-json` COSTUMA se comportar — não
// foram capturados de uma execução real. Estes testes provam que o código
// do Sonora interpreta corretamente esse formato; quem prova que o formato
// real é esse é `tools/verificar_canal_ytdlp.ps1`, rodado no Windows.

import 'package:flutter_test/flutter_test.dart';

import 'package:sonora/core/utils/view_count_formatter.dart';
import 'package:sonora/data/models/youtube_channel.dart';
import 'package:sonora/data/models/youtube_search_result.dart';
import 'package:sonora/services/youtube/channel_json_parser.dart';

Map<String, dynamic> _video(
  String id, {
  String? channel,
  String? channelId,
  String? channelUrl,
  int? views,
}) {
  return {
    'id': id,
    'title': 'Título $id',
    if (channel != null) 'channel': channel,
    if (channelId != null) 'channel_id': channelId,
    if (channelUrl != null) 'channel_url': channelUrl,
    if (views != null) 'view_count': views,
    'duration': 200.0,
    'thumbnails': [
      {'url': 'https://img/$id-small.jpg'},
      {'url': 'https://img/$id-big.jpg'},
    ],
  };
}

YoutubeSearchResult _result(
  String id, {
  String channel = 'Canal',
  String? channelId,
  String? channelUrl,
  int? views,
}) {
  return YoutubeSearchResult(
    videoId: id,
    title: 'Título $id',
    channelName: channel,
    thumbnailUrl: null,
    duration: Duration.zero,
    channelId: channelId,
    channelUrl: channelUrl,
    viewCount: views,
  );
}

void main() {
  group('youtubeSearchResultFromJson', () {
    test('lê canal, visualizações, duração e a maior miniatura', () {
      final result = youtubeSearchResultFromJson(
        _video(
          'abc',
          channel: 'Imagine Dragons',
          channelId: 'UC123',
          channelUrl: 'https://www.youtube.com/channel/UC123',
          views: 1500000,
        ),
      );

      expect(result.videoId, 'abc');
      expect(result.channelName, 'Imagine Dragons');
      expect(result.channelId, 'UC123');
      expect(result.channelUrl, 'https://www.youtube.com/channel/UC123');
      expect(result.viewCount, 1500000);
      expect(result.duration, const Duration(seconds: 200));
      expect(result.thumbnailUrl, 'https://img/abc-big.jpg');
    });

    test('sem campos de canal/visualizações, ficam nulos (não quebra)', () {
      final result = youtubeSearchResultFromJson(_video('abc'));

      expect(result.channelName, '');
      expect(result.channelId, isNull);
      expect(result.channelUrl, isNull);
      expect(result.viewCount, isNull);
    });

    test('usa uploader_url quando channel_url não vem', () {
      final data = _video('abc', channel: 'X')
        ..['uploader_url'] = 'https://www.youtube.com/@x';

      expect(youtubeSearchResultFromJson(data).channelUrl, 'https://www.youtube.com/@x');
    });
  });

  group('parseChannelVideoEntries', () {
    test('ignora entradas sem id e herda o nome do canal quando falta', () {
      final dump = {
        'entries': [
          _video('a', channel: 'Dono'),
          {'title': 'sem id'},
          null,
          _video('b'),
        ],
      };

      final results = parseChannelVideoEntries(dump, fallbackChannelName: 'Canal da Aba');

      expect(results.map((r) => r.videoId), ['a', 'b']);
      expect(results[0].channelName, 'Dono');
      expect(results[1].channelName, 'Canal da Aba');
    });

    test('dump sem entries devolve lista vazia', () {
      expect(parseChannelVideoEntries({}, fallbackChannelName: 'X'), isEmpty);
    });
  });

  group('parseChannelAlbumEntries', () {
    test('lê playlists, ignora vídeos soltos e repetidos', () {
      final dump = {
        'entries': [
          {
            'id': 'OLAK5uy_a',
            'ie_key': 'YoutubeTab',
            'url': 'https://www.youtube.com/playlist?list=OLAK5uy_a',
            'title': 'Evolve',
            'thumbnails': [
              {'url': 'https://img/evolve.jpg'},
            ],
          },
          {'id': 'vid1', 'ie_key': 'Youtube', 'title': 'Um vídeo solto'},
          {
            'id': 'OLAK5uy_a',
            'ie_key': 'YoutubeTab',
            'title': 'Evolve (repetido)',
          },
          // Sem ie_key e sem URL de playlist: não dá pra afirmar que é álbum.
          {'id': 'x', 'title': 'Misterioso'},
          // Sem url: monta a partir do id.
          {'id': 'PL42', 'ie_key': 'YoutubeTab', 'title': 'Mix'},
        ],
      };

      final albums = parseChannelAlbumEntries(dump);

      expect(albums.map((a) => a.id), ['OLAK5uy_a', 'PL42']);
      expect(albums[0].title, 'Evolve');
      expect(albums[0].url, 'https://www.youtube.com/playlist?list=OLAK5uy_a');
      expect(albums[0].thumbnailUrl, 'https://img/evolve.jpg');
      expect(albums[1].url, 'https://www.youtube.com/playlist?list=PL42');
    });
  });

  group('parseChannelArt', () {
    test('acha avatar e banner pelos ids das miniaturas do topo', () {
      final art = parseChannelArt({
        'thumbnails': [
          {'id': 'banner_uncropped', 'url': 'https://img/banner.jpg'},
          {'id': 'avatar_uncropped', 'url': 'https://img/avatar.jpg'},
          {'id': '0', 'url': 'https://img/outra.jpg'},
        ],
      });

      expect(art.avatarUrl, 'https://img/avatar.jpg');
      expect(art.bannerUrl, 'https://img/banner.jpg');
    });

    test('sem miniaturas, devolve vazio', () {
      final art = parseChannelArt({});
      expect(art.avatarUrl, isNull);
      expect(art.bannerUrl, isNull);
    });
  });

  group('sortByViewsDescending', () {
    test('mais vistos primeiro; sem contagem no fim; empates na ordem original', () {
      final sorted = sortByViewsDescending([
        _result('sem1'),
        _result('baixa', views: 10),
        _result('alta', views: 1000),
        _result('empate1', views: 500),
        _result('sem2'),
        _result('empate2', views: 500),
      ]);

      expect(
        sorted.map((r) => r.videoId),
        ['alta', 'empate1', 'empate2', 'baixa', 'sem1', 'sem2'],
      );
    });
  });

  group('YoutubeChannelRef', () {
    test('fromResult exige nome e (ID de canal ou URL)', () {
      expect(YoutubeChannelRef.fromResult(_result('a', channel: '')), isNull);
      expect(YoutubeChannelRef.fromResult(_result('a')), isNull);
      expect(
        YoutubeChannelRef.fromResult(_result('a', channelId: 'UC1')),
        isNotNull,
      );
      expect(
        YoutubeChannelRef.fromResult(
          _result('a', channelUrl: 'https://www.youtube.com/@x'),
        ),
        isNotNull,
      );
    });

    test('baseUrl prefere /channel/<id> e limpa barra e aba finais da URL', () {
      expect(
        const YoutubeChannelRef(id: 'UC1', name: 'X', url: 'https://www.youtube.com/@x')
            .baseUrl,
        'https://www.youtube.com/channel/UC1',
      );
      expect(
        const YoutubeChannelRef(id: '', name: 'X', url: 'https://www.youtube.com/@x/videos/')
            .baseUrl,
        'https://www.youtube.com/@x',
      );
    });
  });

  group('pickChannelForResults', () {
    test('o canal que mais aparece vence, mesmo não sendo o 1º resultado', () {
      final results = [
        _result('1', channel: 'Fã', channelId: 'UCfa'),
        _result('2', channel: 'Oficial', channelId: 'UCof'),
        _result('3', channel: 'Oficial', channelId: 'UCof'),
        _result('4', channel: 'Outro', channelId: 'UCou'),
      ];

      expect(pickChannelForResults(results)!.id, 'UCof');
    });

    test('empate: fica o canal do resultado mais relevante (o primeiro)', () {
      final results = [
        _result('1', channel: 'A', channelId: 'UCa'),
        _result('2', channel: 'B', channelId: 'UCb'),
      ];

      expect(pickChannelForResults(results)!.id, 'UCa');
    });

    test('só olha os primeiros [sample] resultados', () {
      final results = [
        _result('1', channel: 'A', channelId: 'UCa'),
        _result('2', channel: 'B', channelId: 'UCb'),
        _result('3', channel: 'B', channelId: 'UCb'),
      ];

      expect(pickChannelForResults(results, sample: 1)!.id, 'UCa');
    });

    test('ignora resultados sem dados de canal; sem nenhum, devolve null', () {
      expect(pickChannelForResults([_result('1'), _result('2')]), isNull);
      expect(pickChannelForResults(const []), isNull);
      expect(
        pickChannelForResults([
          _result('1'),
          _result('2', channel: 'B', channelId: 'UCb'),
        ])!
            .id,
        'UCb',
      );
    });
  });

  group('albumCoverFromTracks', () {
    test('usa a miniatura da PRIMEIRA faixa, ignorando as outras', () {
      final tracks = [
        const YoutubeSearchResult(
          videoId: 'primeiro',
          title: 'Faixa 1',
          channelName: 'X',
          thumbnailUrl: 'https://img/primeiro.jpg',
          duration: Duration.zero,
        ),
        const YoutubeSearchResult(
          videoId: 'segundo',
          title: 'Faixa 2',
          channelName: 'X',
          thumbnailUrl: 'https://img/segundo.jpg',
          duration: Duration.zero,
        ),
      ];

      expect(albumCoverFromTracks(tracks), 'https://img/primeiro.jpg');
    });

    test('sem miniatura devolvida, monta a URL a partir do ID do vídeo', () {
      expect(
        albumCoverFromTracks([_result('abc123')]),
        'https://i.ytimg.com/vi/abc123/hqdefault.jpg',
      );
      expect(thumbnailForVideoId('abc123'), 'https://i.ytimg.com/vi/abc123/hqdefault.jpg');
    });

    test('álbum sem faixas não tem capa', () {
      expect(albumCoverFromTracks(const []), isNull);
    });
  });

  group('YoutubeAlbumRef.copyWith', () {
    test('preenche a capa sem perder o resto, e não apaga uma capa existente', () {
      const semCapa = YoutubeAlbumRef(id: 'A', title: 'Evolve', url: 'https://u');
      final comCapa = semCapa.copyWith(thumbnailUrl: 'https://img/capa.jpg');

      expect(comCapa.id, 'A');
      expect(comCapa.title, 'Evolve');
      expect(comCapa.url, 'https://u');
      expect(comCapa.thumbnailUrl, 'https://img/capa.jpg');
      // copyWith sem argumento mantém a capa que já existe.
      expect(comCapa.copyWith().thumbnailUrl, 'https://img/capa.jpg');
    });
  });

  group('ViewCountFormatter', () {
    test('formata em português, compacto', () {
      expect(ViewCountFormatter.format(0), '0 visualizações');
      expect(ViewCountFormatter.format(1), '1 visualização');
      expect(ViewCountFormatter.format(532), '532 visualizações');
      expect(ViewCountFormatter.format(1500), '1,5 mil visualizações');
      expect(ViewCountFormatter.format(12000), '12 mil visualizações');
      expect(ViewCountFormatter.format(250000), '250 mil visualizações');
      expect(ViewCountFormatter.format(1000000), '1 mi de visualizações');
      expect(ViewCountFormatter.format(1234567), '1,2 mi de visualizações');
      expect(ViewCountFormatter.format(3200000000), '3,2 bi de visualizações');
    });
  });
}
