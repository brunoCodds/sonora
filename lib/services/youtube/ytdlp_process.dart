import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Erro genérico ao rodar o yt-dlp: o processo saiu com código diferente de
/// zero por um motivo que não é o bloqueio de tráfego do YouTube (ver
/// [YoutubeRateLimitException] pra esse caso específico).
///
/// Guarda a saída de erro crua do processo (`processStderr`) — quem pega
/// essa exceção decide se mostra algo pro usuário ou só loga; ela não tenta
/// traduzir o erro do yt-dlp pra uma mensagem amigável sozinha.
class YtDlpProcessException implements Exception {
  final String message;
  final String? processStderr;

  YtDlpProcessException(this.message, {this.processStderr});

  @override
  String toString() => processStderr == null || processStderr!.isEmpty
      ? 'YtDlpProcessException: $message'
      : 'YtDlpProcessException: $message\n$processStderr';
}

/// O YouTube bloqueou temporariamente as requisições vindas deste
/// computador — a página de "confirme que você não é um robô", ou um HTTP
/// 429. Substitui o `RequestLimitExceededException` que vinha do
/// `youtube_explode_dart`.
///
/// Diferente daquela exceção (a lib antiga sabia internamente quando isso
/// acontecia, por já rodar dentro do próprio processo Dart), aqui a
/// detecção é por texto na saída de erro do yt-dlp — ver
/// [YtDlpProcess._looksLikeRateLimit]. É o mesmo método que a generalidade
/// dos wrappers de yt-dlp usa, mas é mais sensível a mudança de texto entre
/// versões do yt-dlp do que uma exceção tipada de verdade seria.
class YoutubeRateLimitException implements Exception {
  final String message;

  YoutubeRateLimitException(this.message);

  @override
  String toString() => 'YoutubeRateLimitException: $message';
}

/// Roda o `yt-dlp.exe` empacotado como processo externo — a única porta de
/// entrada pra ele no Sonora. Usado por `YoutubeClient` (busca, resolução
/// de stream pra tocar, playlists) e por `YoutubeDownloadService`
/// (download manual).
///
/// Todos os métodos passam os argumentos como `List<String>` direto pro
/// `Process`, nunca como uma única string de shell — isso evita qualquer
/// problema de escaping/injeção com buscas ou títulos que tenham aspas,
/// `&`, etc.: cada item da lista chega ao yt-dlp como um argumento
/// isolado, não importa o que tenha dentro.
class YtDlpProcess {
  YtDlpProcess._();

  /// Liga um log verboso (comando completo + saída crua de cada chamada ao
  /// yt-dlp) no console/terminal. Mude só temporariamente, pra investigar
  /// um problema de verdade — ver `kEnableYoutubeVerboseLogging` em
  /// `main.dart`. A saída pode conter a URL de streaming resolvida e os
  /// headers HTTP associados a ela; não cole isso em lugar público sem
  /// revisar antes.
  static bool verboseLoggingEnabled = false;

  /// Decodificador de UTF-8 tolerante: troca qualquer byte inválido pelo
  /// caractere de substituição (�) em vez de lançar uma exceção e derrubar
  /// o app.
  ///
  /// Isto é a rede de segurança do lado do Dart. A causa raiz é atacada
  /// por [_forceUtf8Environment] (pedir pro próprio yt-dlp escrever UTF-8),
  /// mas mesmo assim vale manter esta tolerância aqui: uma saída de
  /// processo externo é sempre um pouco imprevisível entre versões/SOs, e
  /// só usamos este texto pra casar um regex de progresso — um caractere
  /// decorativo malformado virando "�" no meio de uma linha de progresso
  /// simplesmente não casa o regex e é ignorado, sem quebrar nada. O
  /// caminho final do arquivo baixado nunca é lido deste texto (ver
  /// [runDownload]), então uma eventual corrupção aqui não pode mais
  /// bagunçar um caminho de arquivo.
  static const _lenientUtf8 = Utf8Codec(allowMalformed: true);

  /// Pedido explícito para o yt-dlp (um Python empacotado) escrever
  /// UTF-8 de verdade no stdout/stderr.
  ///
  /// Sem isso, um Python no Windows com a saída redirecionada para um
  /// pipe (nosso caso, sempre — nunca é um console de verdade) pode cair
  /// de volta pra codepage do Windows em vez de UTF-8 para texto
  /// decorativo (ex.: nas linhas de progresso `[download] ...`), mesmo
  /// que o JSON do `--dump-json` em si seja sempre ASCII puro (por isso
  /// busca e reprodução não sentiam esse problema — só o download, que lê
  /// as linhas de progresso, sentia).
  static const _forceUtf8Environment = {
    'PYTHONIOENCODING': 'utf-8',
    'PYTHONUTF8': '1',
  };

  static String? _cachedExecutablePath;

  /// Caminho completo pro `yt-dlp.exe` empacotado como asset do Flutter
  /// (ver `pubspec.yaml`, pasta `assets/bin/`). Resolvido relativo ao
  /// executável do próprio app (`Platform.resolvedExecutable`), não ao
  /// diretório de trabalho atual — funciona não importa de onde o Sonora
  /// foi iniciado (atalho, duplo-clique, `flutter run`, etc.).
  ///
  /// Lança [StateError] com uma mensagem clara se o arquivo não existir —
  /// bem melhor do que deixar o `Process.start` falhar mais na frente com
  /// um erro de SO genérico ("arquivo não encontrado").
  static String resolveExecutable() {
    final cached = _cachedExecutablePath;
    if (cached != null) return cached;

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final path = p.join(
      exeDir,
      'data',
      'flutter_assets',
      'assets',
      'bin',
      'yt-dlp.exe',
    );

    if (!File(path).existsSync()) {
      throw StateError(
        'yt-dlp.exe não foi encontrado em "$path". Confira se '
        '"assets/bin/yt-dlp.exe" existe no projeto e está listado em '
        '"flutter: assets:" no pubspec.yaml, e rode "flutter clean" antes '
        'de recompilar se o arquivo foi adicionado depois do último build.',
      );
    }

    _cachedExecutablePath = path;
    return path;
  }

  /// Roda o yt-dlp e devolve a saída padrão (stdout) inteira, já
  /// decodificada como UTF-8. Pensado pra comandos com
  /// `--dump-json`/`--dump-single-json`, onde a resposta inteira só faz
  /// sentido depois que o processo termina (ao contrário do download, que
  /// precisa de progresso incremental — ver [runDownload]).
  ///
  /// Decodifica com [_lenientUtf8] (em vez do `utf8` padrão do
  /// `dart:convert`) e roda com [_forceUtf8Environment]: no Windows, o
  /// padrão do `Process.run` é decodificar com a codepage do console (não
  /// UTF-8), o que corrompe título/busca com acento — bem relevante pra um
  /// app em português.
  static Future<String> runCapturingJson(List<String> args) async {
    final exe = resolveExecutable();
    _logCommand(exe, args);

    final result = await Process.run(
      exe,
      args,
      environment: _forceUtf8Environment,
      stdoutEncoding: _lenientUtf8,
      stderrEncoding: _lenientUtf8,
    );

    final stdout = result.stdout as String;
    final stderr = result.stderr as String;
    _logResult(stdout: stdout, stderr: stderr, exitCode: result.exitCode);

    if (result.exitCode != 0) {
      _throwForFailure(stderr);
    }
    return stdout;
  }

  static final _progressRegExp = RegExp(r'\[download\]\s+([\d.]+)%');

  /// Roda um download de verdade — o próprio yt-dlp resolve, baixa e grava
  /// o arquivo em disco; aqui só acompanhamos o progresso e propagamos
  /// erro, se houver.
  ///
  /// Não devolve o caminho final do arquivo: uma versão anterior desta
  /// classe tentava descobri-lo lendo de volta um texto impresso pelo
  /// próprio yt-dlp (via `--print "after_move:..."`), mas esse texto pode
  /// sair com o encoding errado no Windows quando o caminho tem acento
  /// (o yt-dlp.exe é um Python empacotado, e a saída dele está sempre
  /// redirecionada para um pipe aqui, nunca um console de verdade) — o
  /// arquivo em si é gravado certo, só o texto impresso de volta que não
  /// é confiável. Por isso quem chama isto descobre o caminho final
  /// olhando o sistema de arquivos diretamente (ver
  /// `YoutubeClient._findDownloadedFile`), não por um valor de retorno
  /// daqui.
  ///
  /// [args] deve conter as opções específicas do download (formato, `-o`
  /// com o template de saída, e a URL por último) — `--newline` é
  /// adicionado aqui dentro, pra quem chama não precisar conhecer esse
  /// detalhe.
  static Future<void> runDownload(
    List<String> args, {
    required void Function(double progress) onProgress,
  }) async {
    final exe = resolveExecutable();
    final fullArgs = ['--newline', ...args];
    _logCommand(exe, fullArgs);

    final process = await Process.start(
      exe,
      fullArgs,
      environment: _forceUtf8Environment,
    );

    final stderrBuffer = StringBuffer();

    final stdoutDone = process.stdout
        .transform(_lenientUtf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (verboseLoggingEnabled) {
            // ignore: avoid_print
            print('Sonora [yt-dlp]: $line');
          }
          final match = _progressRegExp.firstMatch(line);
          if (match != null) {
            final percent = double.tryParse(match.group(1)!);
            if (percent != null) onProgress((percent / 100).clamp(0.0, 1.0));
          }
        })
        .asFuture<void>();

    final stderrDone = process.stderr
        .transform(_lenientUtf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => stderrBuffer.writeln(line))
        .asFuture<void>();

    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);

    _logResult(stdout: '', stderr: stderrBuffer.toString(), exitCode: exitCode);

    if (exitCode != 0) {
      _throwForFailure(stderrBuffer.toString());
    }
  }

  static void _throwForFailure(String stderr) {
    if (_looksLikeRateLimit(stderr)) {
      throw YoutubeRateLimitException(
        'O YouTube limitou as requisições feitas deste computador há '
        'pouco.\n$stderr',
      );
    }
    throw YtDlpProcessException(
      'O yt-dlp terminou com erro.',
      processStderr: stderr,
    );
  }

  /// Textos conhecidos que o próprio yt-dlp imprime quando o YouTube
  /// bloqueia o tráfego — a página de "confirme que você não é um robô",
  /// ou um HTTP 429. Cobrir por texto (em vez de um erro estruturado) é
  /// uma limitação real de chamar uma ferramenta externa em vez de uma lib
  /// Dart tipada; se o texto mudar numa versão futura do yt-dlp, esta
  /// lista pode precisar de ajuste — confirmar contra um bloqueio de
  /// verdade é um dos pontos em aberto da Fase 2.
  static bool _looksLikeRateLimit(String stderr) {
    final lower = stderr.toLowerCase();
    return lower.contains("confirm you're not a bot") ||
        lower.contains('sign in to confirm') ||
        lower.contains('429') ||
        lower.contains('too many requests');
  }

  static void _logCommand(String exe, List<String> args) {
    if (!verboseLoggingEnabled) return;
    // ignore: avoid_print
    print('Sonora [yt-dlp]: $exe ${args.join(' ')}');
  }

  static void _logResult({
    required String stdout,
    required String stderr,
    required int exitCode,
  }) {
    if (!verboseLoggingEnabled) return;
    // ignore: avoid_print
    print('Sonora [yt-dlp]: saiu com código $exitCode');
    if (stdout.isNotEmpty) {
      // ignore: avoid_print
      print('Sonora [yt-dlp] stdout: $stdout');
    }
    if (stderr.isNotEmpty) {
      // ignore: avoid_print
      print('Sonora [yt-dlp] stderr: $stderr');
    }
  }
}
