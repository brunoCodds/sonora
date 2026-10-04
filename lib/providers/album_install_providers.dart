import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/song.dart';
import '../data/models/youtube_channel.dart';
import '../data/models/youtube_search_result.dart';
import 'download_providers.dart';
import 'library_providers.dart';
import 'playlist_providers.dart';

/// Progresso (e resultado) da instalação de um álbum inteiro.
class AlbumInstallState {
  /// Álbum sendo instalado agora, ou o último que terminou (para a tela
  /// dele mostrar [resultMessage]). `null` = nunca instalou nada nesta
  /// sessão.
  final String? albumId;
  final String? albumTitle;

  final int total;

  /// Faixas já resolvidas com sucesso (baixadas agora ou já instaladas
  /// antes).
  final int done;
  final int failed;

  /// Título da faixa sendo baixada neste instante.
  final String? currentTitle;

  final bool isRunning;

  /// Resumo do que aconteceu, preenchido quando a instalação termina
  /// (certo, com falhas, cancelada ou barrada pelo YouTube).
  final String? resultMessage;

  const AlbumInstallState({
    this.albumId,
    this.albumTitle,
    this.total = 0,
    this.done = 0,
    this.failed = 0,
    this.currentTitle,
    this.isRunning = false,
    this.resultMessage,
  });

  /// De 0.0 a 1.0, ou `null` se não há total ainda.
  double? get progress => total == 0 ? null : (done + failed) / total;

  AlbumInstallState copyWith({
    int? done,
    int? failed,
    String? currentTitle,
    bool clearCurrentTitle = false,
    bool? isRunning,
    String? resultMessage,
  }) {
    return AlbumInstallState(
      albumId: albumId,
      albumTitle: albumTitle,
      total: total,
      done: done ?? this.done,
      failed: failed ?? this.failed,
      currentTitle:
          clearCurrentTitle ? null : (currentTitle ?? this.currentTitle),
      isRunning: isRunning ?? this.isRunning,
      resultMessage: resultMessage ?? this.resultMessage,
    );
  }
}

/// Instala ou salva um álbum inteiro da aba Álbuns de um canal.
///
/// - [install]: baixa as faixas UMA POR VEZ, reaproveitando
///   `DownloadNotifier.download` (que já cuida da pasta de downloads, do
///   nome "Artista - Título", do cache de capa e de atualizar Biblioteca,
///   fila e favoritos) — não há mecanismo de download novo aqui. Cada faixa
///   é gravada com o nome do álbum e o número da faixa, então o álbum
///   aparece agrupado na tela Álbuns da biblioteca.
/// - [saveAsPlaylist]: só guarda o álbum como uma playlist do Sonora
///   (tocando por streaming), sem baixar nada.
///
/// Não é `autoDispose`: a instalação continua se o usuário sair da tela
/// Buscar no meio do caminho.
class AlbumInstallNotifier extends StateNotifier<AlbumInstallState> {
  final Ref _ref;
  bool _cancelRequested = false;

  AlbumInstallNotifier(this._ref) : super(const AlbumInstallState());

  /// Pede para parar. A faixa que já está baixando termina; as seguintes
  /// não começam.
  void cancel() {
    if (state.isRunning) _cancelRequested = true;
  }

  Future<void> install({
    required YoutubeAlbumRef album,
    required String artistName,
    required List<YoutubeSearchResult> tracks,
  }) async {
    if (state.isRunning || tracks.isEmpty) return;

    _cancelRequested = false;
    state = AlbumInstallState(
      albumId: album.id,
      albumTitle: album.title,
      total: tracks.length,
      isRunning: true,
    );

    final library = _ref.read(libraryNotifierProvider.notifier);
    final downloads = _ref.read(downloadNotifierProvider.notifier);

    var done = 0;
    var failed = 0;
    var rateLimited = false;

    for (var i = 0; i < tracks.length; i++) {
      if (_cancelRequested) break;

      final track = _withArtist(tracks[i], artistName);
      state = state.copyWith(currentTitle: track.title);

      final song = library.materializeWebSong(
        track,
        album: album.title,
        albumArtist: artistName,
        trackNumber: i + 1,
      );

      // Já instalada antes (ex.: o usuário baixou uma faixa avulsa, ou
      // está repetindo a instalação de um álbum que falhou no meio):
      // não baixa de novo.
      final existingPath = song.localPath;
      if (existingPath != null && File(existingPath).existsSync()) {
        done++;
        state = state.copyWith(done: done);
        continue;
      }

      final result = await _downloadWhenFree(downloads, song);
      if (result == null) break; // cancelado enquanto esperava a vez.

      switch (result) {
        case DownloadResult.success:
          done++;
          break;
        case DownloadResult.rateLimited:
          rateLimited = true;
          break;
        case DownloadResult.failed:
        case DownloadResult.busy:
          failed++;
          break;
      }
      state = state.copyWith(done: done, failed: failed);
      if (rateLimited) break;
    }

    final cancelled = _cancelRequested;
    _cancelRequested = false;

    state = state.copyWith(
      isRunning: false,
      clearCurrentTitle: true,
      resultMessage: _summarize(
        title: album.title,
        total: tracks.length,
        done: done,
        failed: failed,
        cancelled: cancelled,
        rateLimited: rateLimited,
      ),
    );
  }

  /// Guarda o álbum como uma playlist do Sonora, sem baixar nada. Devolve
  /// quantas faixas entraram nela.
  int saveAsPlaylist({
    required YoutubeAlbumRef album,
    required String artistName,
    required List<YoutubeSearchResult> tracks,
  }) {
    if (tracks.isEmpty) return 0;

    final library = _ref.read(libraryNotifierProvider.notifier);
    final songs = <Song>[
      for (var i = 0; i < tracks.length; i++)
        library.materializeWebSong(
          _withArtist(tracks[i], artistName),
          album: album.title,
          albumArtist: artistName,
          trackNumber: i + 1,
        ),
    ];

    final playlists = _ref.read(playlistsNotifierProvider.notifier);
    final playlist = playlists.create(album.title);
    playlists.addSongs(playlist.id, songs.map((song) => song.id));
    return songs.length;
  }

  /// Faixa de álbum sem nome de canal herda o nome do artista — evita uma
  /// música instalada com artista vazio (e um arquivo "Título.m4a" sem
  /// "Artista - ").
  YoutubeSearchResult _withArtist(YoutubeSearchResult track, String artist) {
    return track.channelName.isEmpty
        ? track.copyWith(channelName: artist)
        : track;
  }

  /// `DownloadNotifier` só faz um download por vez (o botão de baixar do
  /// player também usa ele). Se outro download estiver rodando, espera a
  /// vez em vez de falhar. Devolve `null` se for cancelado enquanto espera.
  Future<DownloadResult?> _downloadWhenFree(
    DownloadNotifier downloads,
    Song song,
  ) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      while (_ref.read(downloadNotifierProvider).downloadingSongId != null) {
        if (_cancelRequested) return null;
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      if (_cancelRequested) return null;

      final result = await downloads.download(song);
      if (result != DownloadResult.busy) return result;
      // `busy`: outro download começou entre a checagem acima e esta
      // chamada — volta pro início e espera de novo.
    }
    return DownloadResult.busy;
  }

  String _summarize({
    required String title,
    required int total,
    required int done,
    required int failed,
    required bool cancelled,
    required bool rateLimited,
  }) {
    if (rateLimited) {
      return 'O YouTube está limitando as requisições deste computador. '
          '$done de $total faixas de "$title" foram instaladas antes de '
          'parar — espere alguns minutos e instale de novo para continuar '
          '(as já instaladas não são baixadas outra vez).';
    }
    if (cancelled) {
      return 'Instalação cancelada: $done de $total faixas de "$title" '
          'instaladas.';
    }
    if (failed == 0 && done == total) {
      return '"$title" instalado: $done de $total faixas. Já está na '
          'Biblioteca, em Álbuns.';
    }
    return '$done de $total faixas de "$title" instaladas; $failed '
        '${failed == 1 ? 'falhou' : 'falharam'}. Instale de novo para '
        'tentar só as que faltam.';
  }
}

final albumInstallProvider =
    StateNotifierProvider<AlbumInstallNotifier, AlbumInstallState>((ref) {
  return AlbumInstallNotifier(ref);
});
