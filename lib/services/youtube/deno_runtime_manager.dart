import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Garante que exista um `deno.exe` utilizável, baixando um runtime
/// portátil do Deno na primeira execução, se necessário.
///
/// Por quê: o `youtube_explode_dart` precisa resolver um desafio de
/// assinatura em JavaScript para tocar boa parte dos vídeos do YouTube
/// atualmente, e o único solver que o pacote implementa hoje roda
/// sobre o runtime do Deno (ver `DenoEJSSolver` em
/// `package:youtube_explode_dart/solvers.dart`). Em vez de pedir para o
/// usuário instalar o Deno manualmente (fricção de instalação, e uma
/// dependência de sistema fora do controle do app), o Sonora baixa um
/// executável portátil uma única vez e o gerencia sozinho — o mesmo
/// padrão que apps que embutem `yt-dlp`/`ffmpeg` costumam usar.
///
/// O download é de dezenas de MB e roda uma vez só, em segundo plano;
/// a reprodução de arquivos locais não depende disso e continua
/// funcionando normalmente enquanto isso acontece.
class DenoRuntimeManager {
  /// URL "latest" do GitHub Releases: sempre resolve (via redirect) para
  /// o asset da versão mais recente publicada, sem precisar saber o
  /// número da versão de antemão.
  static const _releaseZipUrl =
      'https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip';

  /// Garante que `deno.exe` existe em disco e devolve o caminho completo
  /// para ele. Se já tiver sido baixado numa execução anterior, retorna
  /// na hora sem tocar na rede.
  ///
  /// [onProgress] é chamado com um valor de 0.0 a 1.0 durante o
  /// download (só quando um download de verdade acontece).
  Future<String> ensureDenoExecutable({
    void Function(double progress)? onProgress,
  }) async {
    final dir = await _denoDirectory();
    final exePath = p.join(dir.path, 'deno.exe');
    if (File(exePath).existsSync()) return exePath;

    final zipPath = p.join(dir.path, 'deno_download.zip');
    await _download(_releaseZipUrl, zipPath, onProgress: onProgress);

    try {
      await _extract(zipPath, dir.path);
    } finally {
      final zipFile = File(zipPath);
      if (zipFile.existsSync()) {
        try {
          zipFile.deleteSync();
        } catch (_) {
          // Não é crítico deixar o zip para trás; só ocupa espaço.
        }
      }
    }

    if (!File(exePath).existsSync()) {
      throw StateError(
        'deno.exe não foi encontrado depois de extrair o pacote baixado.',
      );
    }
    return exePath;
  }

  /// Verdadeiro se o executável já foi baixado antes (sem checar rede).
  Future<bool> isReady() async {
    final dir = await _denoDirectory();
    return File(p.join(dir.path, 'deno.exe')).existsSync();
  }

  Future<Directory> _denoDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, 'sonora_deno'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<void> _download(
    String url,
    String destPath, {
    void Function(double progress)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await request.send();

    if (response.statusCode != 200) {
      throw HttpException(
        'Falha ao baixar o componente de reprodução web '
        '(HTTP ${response.statusCode}).',
      );
    }

    final total = response.contentLength ?? 0;
    var received = 0;
    final sink = File(destPath).openWrite();

    await response.stream.map((chunk) {
      received += chunk.length;
      if (total > 0) onProgress?.call(received / total);
      return chunk;
    }).pipe(sink);

    await sink.close();
  }

  /// Descompacta o zip baixado usando o `Expand-Archive` do PowerShell,
  /// já disponível em qualquer Windows moderno — evita adicionar uma
  /// dependência Dart só para isso, já que o Sonora é um app Windows.
  Future<void> _extract(String zipPath, String destDir) async {
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "Expand-Archive -LiteralPath '$zipPath' -DestinationPath '$destDir' -Force",
    ]);

    if (result.exitCode != 0) {
      throw StateError(
        'Falha ao extrair o componente de reprodução web: ${result.stderr}',
      );
    }
  }
}
