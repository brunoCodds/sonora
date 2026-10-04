import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart' show BackgroundIsolateBinaryMessenger, RootIsolateToken;
import 'package:media_kit/media_kit.dart';

/// Ponto de entrada da isolate dedicada ao motor de áudio (media_kit/libmpv).
///
/// Todo o [Player] e suas threads nativas internas (decodificação, saída
/// de áudio, callbacks de evento do libmpv) vivem inteiramente aqui,
/// isolados da isolate principal — a que desenha a UI e onde o Win32
/// processa o loop de redimensionamento da janela no Windows.
///
/// Comunicação com a isolate principal:
/// - `args[0]` (SendPort): porta da isolate principal. Assim que esta
///   isolate estiver pronta, envia de volta a própria [SendPort] de
///   comandos (o primeiro e único valor "cru", sem envelope, que sai
///   daqui — tudo o mais é um `Map`).
/// - `args[1]` (RootIsolateToken?): necessário caso algum plugin usado
///   pelo media_kit (ou por uma dependência sua) use um platform channel
///   internamente. Sem isso, qualquer `MethodChannel` chamado a partir
///   desta isolate travaria silenciosamente. Ver:
///   https://docs.flutter.dev/platform-integration/platform-channels#channels-and-platform-threading
///
/// Comandos recebidos (um `Map` por mensagem): `{'id': int, 'cmd': String,
/// ...args}`. Toda mensagem de comando recebe exatamente uma resposta:
/// `{'type': 'reply', 'id': int, 'error': String?}` (`error == null`
/// significa sucesso).
///
/// Eventos emitidos espontaneamente (streams do [Player]):
/// `{'type': 'event', 'evt': String, ...dados}`.
///
/// Só usamos `Map`s com tipos primitivos (nunca instâncias de classes
/// customizadas) nas mensagens para não depender de detalhes de qual
/// versão do Dart/Flutter suporta copiar quais objetos entre isolates —
/// `Map`/`List`/`num`/`String`/`bool`/`SendPort` sempre funcionam.
@pragma('vm:entry-point')
void audioIsolateEntryPoint(List<Object?> args) {
  final SendPort mainSendPort = args[0] as SendPort;
  final RootIsolateToken? rootIsolateToken = args[1] as RootIsolateToken?;

  if (rootIsolateToken != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
  }

  // Cada isolate tem seu próprio heap e reexecuta inicializadores
  // estáticos/top-level de forma independente — a chamada feita na
  // isolate principal (main.dart) não "conta" para esta aqui.
  MediaKit.ensureInitialized();

  final player = Player();
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);

  void sendEvent(String evt, Map<String, Object?> data) {
    mainSendPort.send({'type': 'event', 'evt': evt, ...data});
  }

  final subscriptions = <StreamSubscription<dynamic>>[
    player.stream.position.listen(
      (d) => sendEvent('position', {'ms': d.inMilliseconds}),
    ),
    player.stream.duration.listen(
      (d) => sendEvent('duration', {'ms': d.inMilliseconds}),
    ),
    player.stream.playing.listen(
      (v) => sendEvent('playing', {'value': v}),
    ),
    player.stream.completed.listen(
      (v) => sendEvent('completed', {'value': v}),
    ),
    player.stream.volume.listen(
      (v) => sendEvent('volume', {'value': v}),
    ),
    player.stream.buffering.listen(
      (v) => sendEvent('buffering', {'value': v}),
    ),
  ];

  Future<void> handleCommand(Map message) async {
    final id = message['id'] as int;
    final cmd = message['cmd'] as String;
    String? error;
    try {
      switch (cmd) {
        case 'open':
          final path = message['path'] as String;
          final play = message['play'] as bool;
          final uri = Uri.file(File(path).absolute.path).toString();
          await player.open(Media(uri), play: play);
          break;
        case 'play':
          await player.play();
          break;
        case 'pause':
          await player.pause();
          break;
        case 'seek':
          await player.seek(Duration(milliseconds: message['ms'] as int));
          break;
        case 'setVolume':
          await player.setVolume(message['value'] as double);
          break;
        case 'stop':
          await player.stop();
          break;
        case 'dispose':
          for (final sub in subscriptions) {
            await sub.cancel();
          }
          await player.dispose();
          break;
        default:
          error = 'Comando desconhecido: $cmd';
      }
    } catch (e) {
      error = e.toString();
    }
    mainSendPort.send({'type': 'reply', 'id': id, 'error': error});
    if (cmd == 'dispose') {
      commandPort.close();
    }
  }

  commandPort.listen((message) {
    if (message is Map) {
      handleCommand(message);
    }
  });
}
