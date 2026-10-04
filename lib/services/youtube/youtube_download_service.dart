import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'youtube_client.dart';

/// Baixa o áudio de uma música da web e a instala como um arquivo de
/// verdade no PC do usuário.
///
/// Salva, por padrão, em `Documentos/Sonora/Músicas baixadas/` — uma
/// pasta própria dentro da pasta Documentos do usuário (não na pasta de
/// dados interna do app, onde ficam o banco e o cache de capas). O
/// usuário pode escolher outra pasta em Configurações; nesse caso quem
/// constrói este serviço passa o caminho em [customDownloadsPath] (ver
/// `DownloadNotifier`).
///
/// Quem baixa e escreve o arquivo de verdade agora é o próprio yt-dlp (ver
/// `YoutubeClient.downloadAudioTo`) — esta classe só decide ONDE ele deve
/// escrever e cuida do nome final "Artista - Título", que o yt-dlp não
/// sabe montar sozinho.
class YoutubeDownloadService {
  final YoutubeClient _youtube;

  /// Pasta escolhida pelo usuário para os downloads. `null` ou vazio =
  /// usa a pasta padrão ([defaultDownloadsPath]).
  final String? customDownloadsPath;

  YoutubeDownloadService(this._youtube, {this.customDownloadsPath});

  /// Pasta padrão dos downloads: `Documentos/Sonora/Músicas baixadas/`.
  /// Pública para a tela de configurações mostrar qual é o destino atual
  /// quando o usuário ainda não escolheu nenhuma pasta — assim o caminho
  /// padrão fica definido num lugar só.
  static Future<String> defaultDownloadsPath() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    return p.join(documentsDir.path, 'Sonora', 'Músicas baixadas');
  }

  /// Baixa o melhor stream de áudio disponível para [videoId] e grava em
  /// disco, devolvendo o caminho final do arquivo.
  ///
  /// [onProgress] é chamado com um valor de 0.0 a 1.0 durante o download.
  Future<String> downloadAudio({
    required String videoId,
    required String artist,
    required String title,
    void Function(double progress)? onProgress,
  }) async {
    final dir = await _downloadsDirectory();

    // O nome bonito ("Artista - Título") só dá pra montar DEPOIS de saber
    // a extensão real — e essa extensão só se sabe depois que o yt-dlp
    // escolhe o melhor formato de áudio disponível. Por isso
    // `downloadAudioTo` baixa primeiro com um nome temporário (só o
    // videoId, sem risco de colidir com nada) e devolve o caminho real,
    // lido do sistema de arquivos.
    final tempPath = await _youtube.downloadAudioTo(
      videoId: videoId,
      directory: dir.path,
      onProgress: onProgress,
    );

    final extensionWithDot = p.extension(tempPath);
    final baseName = _sanitizeFileName(
      artist.isEmpty ? title : '$artist - $title',
    );
    final destPath = await _uniqueDestination(dir, baseName, extensionWithDot);

    await File(tempPath).rename(destPath);
    return destPath;
  }

  /// Remove um arquivo previamente baixado (ex.: ao desfazer a instalação
  /// de uma música). Silencioso se o arquivo já não existir.
  Future<void> deleteDownloadedFile(String path) async {
    final file = File(path);
    if (file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {
        // Não é crítico deixar o arquivo pra trás: o pior caso é um
        // arquivo órfão na pasta de downloads, sem nenhum efeito no
        // funcionamento do app.
      }
    }
  }

  Future<Directory> _downloadsDirectory() async {
    final custom = customDownloadsPath;
    final path = (custom != null && custom.trim().isNotEmpty)
        ? custom
        : await defaultDownloadsPath();
    final dir = Directory(path);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Remove caracteres inválidos em nomes de arquivo no Windows
  /// (`< > : " / \ | ? *`) e aparas de espaço nas pontas.
  String _sanitizeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    return cleaned.isEmpty ? 'Música' : cleaned;
  }

  Future<String> _uniqueDestination(
    Directory dir,
    String baseName,
    String extensionWithDot,
  ) async {
    var candidate = p.join(dir.path, '$baseName$extensionWithDot');
    var attempt = 2;
    while (File(candidate).existsSync()) {
      candidate = p.join(dir.path, '$baseName ($attempt)$extensionWithDot');
      attempt++;
    }
    return candidate;
  }
}
