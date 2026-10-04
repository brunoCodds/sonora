import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/constants/app_constants.dart';
import '../data/models/song.dart';
import '../services/youtube/youtube_download_service.dart';
import '../services/youtube/ytdlp_process.dart';
import 'audio_providers.dart';
import 'database_provider.dart';
import 'favorites_providers.dart';
import 'library_providers.dart';
import 'repository_providers.dart';
import 'service_providers.dart';

/// Como terminou uma chamada a [DownloadNotifier.download]. Antes isso era
/// só um `Future<void>` (o resultado ia só para [DownloadState]); quem
/// baixa vários de uma vez (ver `AlbumInstallNotifier`) precisa saber, a
/// cada faixa, se deu certo, se falhou, ou se o YouTube está limitando —
/// neste último caso insistir nas próximas só piora.
enum DownloadResult {
  success,
  failed,
  rateLimited,

  /// Já havia outro download em andamento (um por vez) — nada foi feito.
  busy,
}

/// Estado do download em andamento (no máximo um por vez, disparado
/// pelo botão de instalar no player — ver `DownloadButton`).
class DownloadState {
  /// Id da música sendo baixada agora. `null` quando não há download em
  /// andamento.
  final int? downloadingSongId;
  final double progress;
  final String? errorMessage;

  const DownloadState({
    this.downloadingSongId,
    this.progress = 0,
    this.errorMessage,
  });

  DownloadState copyWith({
    int? downloadingSongId,
    bool clearDownloading = false,
    double? progress,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DownloadState(
      downloadingSongId:
          clearDownloading ? null : (downloadingSongId ?? this.downloadingSongId),
      progress: progress ?? this.progress,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Baixa/instala músicas da web no PC (ver `YoutubeDownloadService`) e
/// propaga o resultado para todos os lugares que guardam uma cópia em
/// memória da música afetada: a fila de reprodução atual e a lista de
/// favoritos — o mesmo cuidado de sincronização que
/// `LibraryNotifier.toggleFavorite` já toma.
class DownloadNotifier extends StateNotifier<DownloadState> {
  final Ref _ref;

  DownloadNotifier(this._ref) : super(const DownloadState());

  Future<DownloadResult> download(Song song) async {
    if (state.downloadingSongId != null) return DownloadResult.busy; // um por vez.

    state = DownloadState(downloadingSongId: song.id, progress: 0);

    try {
      final youtube = await _ref.read(youtubeClientProvider.future);
      final service = YoutubeDownloadService(
        youtube,
        customDownloadsPath: _ref
            .read(settingsRepositoryProvider)
            .getString(AppConstants.keyDownloadFolder),
      );
      final path = await service.downloadAudio(
        videoId: song.remoteId!,
        artist: song.artist,
        title: song.title,
        onProgress: (progress) {
          state = state.copyWith(progress: progress);
        },
      );

      final repository = _ref.read(libraryRepositoryProvider);
      repository.setLocalPath(song.id, path);

      // Título, artista e capa já vieram da busca e estão no banco; a
      // capa, porém, é só uma URL de rede. Ao instalar, guardamos a
      // imagem em disco também (como o app já faz com as capas extraídas
      // de arquivos locais) — assim ela aparece nas telas de álbum e
      // artista, e continua aparecendo sem internet.
      if (song.coverPath == null) {
        final coverPath = await _cacheCoverArt(song);
        if (coverPath != null) repository.setCoverPath(song.id, coverPath);
      }

      _ref.read(queueControllerProvider.notifier).updateSongLocalPath(song.id, path);
      _ref.read(favoritesNotifierProvider.notifier).loadFromDb();
      // A música acabou de ficar "instalada": passa a fazer parte da
      // Biblioteca (ver `LibraryRepository.getAllSongs`).
      _ref.read(libraryNotifierProvider.notifier).loadFromDb();

      state = const DownloadState();
      return DownloadResult.success;
    } on YoutubeRateLimitException catch (e) {
      // ignore: avoid_print
      print('Sonora [download]: rate limit ao baixar "${song.title}": $e');
      state = const DownloadState(
        errorMessage:
            'O YouTube está limitando temporariamente as requisições feitas '
            'deste computador. Espere alguns minutos antes de tentar baixar '
            'de novo.',
      );
      return DownloadResult.rateLimited;
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('Sonora [download]: falha ao baixar "${song.title}" '
          '(remoteId=${song.remoteId}): $e\n$stackTrace');
      state = DownloadState(
        errorMessage:
            'Não foi possível baixar "${song.title}". Tente de novo mais tarde.',
      );
      return DownloadResult.failed;
    }
  }

  /// Remove o arquivo baixado e volta a música a depender só de
  /// streaming.
  Future<void> removeDownload(Song song) async {
    final path = song.localPath;
    if (path == null) return;

    final youtube = await _ref.read(youtubeClientProvider.future);
    await YoutubeDownloadService(youtube).deleteDownloadedFile(path);

    _ref.read(libraryRepositoryProvider).setLocalPath(song.id, null);
    _ref.read(queueControllerProvider.notifier).updateSongLocalPath(song.id, null);
    _ref.read(favoritesNotifierProvider.notifier).loadFromDb();
    // Sem arquivo baixado a música deixa de ser "instalada" e sai da
    // Biblioteca (ver `LibraryRepository.getAllSongs`).
    _ref.read(libraryNotifierProvider.notifier).loadFromDb();
  }

  /// Baixa a capa (thumbnail) da música e guarda em disco, na mesma pasta
  /// usada pelas capas extraídas de arquivos locais (ver
  /// `AppDatabase.coversDirectory`). Devolve o caminho do arquivo, ou
  /// `null` se não houver URL de capa ou o download falhar — falhar aqui
  /// nunca deve estragar a instalação da música: ela só fica sem capa em
  /// cache (e continua mostrando a da rede, via `coverUrl`).
  Future<String?> _cacheCoverArt(Song song) async {
    final url = song.coverUrl;
    final videoId = song.remoteId;
    if (url == null || url.isEmpty || videoId == null) return null;

    try {
      final coversDir = await _ref.read(databaseProvider).coversDirectory();
      final file = File(p.join(coversDir.path, 'yt_$videoId.cover'));
      if (file.existsSync() && file.lengthSync() > 0) return file.path;

      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;

      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}

final downloadNotifierProvider =
    StateNotifierProvider<DownloadNotifier, DownloadState>((ref) {
  return DownloadNotifier(ref);
});
