import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/audio_providers.dart';
import 'window_mode.dart';

/// Botões de mídia (aleatório / anterior / tocar-pausar / próxima /
/// repetir) no painel que aparece ao passar o mouse sobre o ícone do app na
/// barra de tarefas do Windows — o mesmo painel do Spotify e do Windows
/// Media Player.
///
/// NÃO é o SMTC (System Media Transport Controls): o SMTC alimenta o
/// cartão de mídia do volume/tela de bloqueio e as teclas de mídia, mas
/// não desenha nada na miniatura da barra de tarefas. O que desenha
/// botões ali é a "thumbnail toolbar" do `ITaskbarList3`, que aqui é
/// feita direto no runner nativo (`windows/runner/taskbar_media_controls.cpp`)
/// — sem pacote novo e sem Rust. Ver o comentário daquele arquivo para o
/// motivo de não usar o `windows_taskbar` (ele não se recupera quando a
/// janela é escondida na bandeja e reaparece, que é o fluxo normal da
/// Sonora).
///
/// Protocolo do canal `sonora/taskbar_media`:
/// - Dart -> nativo, `update` `{enabled, playing, shuffle, repeat}`: estado
///   atual do player. O nativo só desenha; guarda o último estado para
///   redesenhar sozinho quando o Windows recria o botão da barra.
/// - nativo -> Dart, `button` `"shuffle" | "previous" | "playPause" |
///   "next" | "repeat"`: o usuário clicou; aqui se chama o
///   `QueueController`, o mesmo que o player completo e o
///   `MiniPlayerScreen` já usam.
///
/// Só faz algo no Windows; nas outras plataformas [start] não faz nada.
class TaskbarMediaController {
  TaskbarMediaController(this._ref);

  static const MethodChannel _channel = MethodChannel('sonora/taskbar_media');

  final Ref _ref;

  bool _started = false;

  /// Último estado enviado ao nativo, só para não repetir a mesma chamada
  /// (o `QueueState` muda por muitos motivos que não interessam aqui, como
  /// erro de reprodução ou reordenar a fila). `null` força o próximo envio.
  String? _lastSentKey;

  Timer? _refreshTimer;

  /// Liga os listeners e manda o estado inicial. Precisa ser chamado de
  /// dentro do corpo do `Provider` (ver [taskbarMediaControllerProvider]),
  /// que é onde `ref.listen` é permitido.
  void start() {
    if (_started || !Platform.isWindows) return;
    _started = true;

    _channel.setMethodCallHandler(_onNativeCall);

    _ref.listen(queueControllerProvider, (_, __) => _pushState());
    _ref.listen(playerPlayingProvider, (_, __) => _pushState());
    _ref.listen(windowModeProvider, (_, mode) {
      if (mode == WindowMode.full) _scheduleRefresh();
    });

    _pushState();
  }

  void dispose() {
    _refreshTimer?.cancel();
    if (!_started) return;
    _channel.setMethodCallHandler(null);
  }

  /// No modo mini a janela fica fora da barra de tarefas
  /// (`setSkipTaskbar(true)`, ver `TrayModeController.showMini`) e, ao
  /// voltar pro modo cheio, o Windows cria um botão novo na barra — sem
  /// nenhuma toolbar de miniatura nele. O nativo normalmente se recupera
  /// sozinho (mensagem `TaskbarButtonCreated`), mas isto é um cinto de
  /// segurança barato: reenvia o estado um instante depois da troca, e
  /// cada `update` faz o nativo (re)adicionar os botões se for preciso.
  /// O atraso deixa o botão novo existir de fato antes da tentativa.
  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 400), () {
      _lastSentKey = null;
      _pushState();
    });
  }

  // ---- Dart -> nativo ------------------------------------------------------

  void _pushState() {
    final queue = _ref.read(queueControllerProvider);
    final playing = _ref.read(playerPlayingProvider).valueOrNull ?? false;

    // Sem nada na fila os botões ficam desabilitados (apagados) em vez de
    // sumirem; "tocar" continua possível assim que houver uma fila.
    final enabled = queue.queue.isNotEmpty;
    final shuffle = queue.shuffleEnabled;
    // `RepeatMode.name` => 'off' | 'all' | 'one' (o nativo espera isso).
    final repeat = queue.repeatMode.name;

    final key = '$enabled|$playing|$shuffle|$repeat';
    if (key == _lastSentKey) return;
    _lastSentKey = key;

    _channel.invokeMethod<void>('update', <String, Object>{
      'enabled': enabled,
      'playing': playing,
      'shuffle': shuffle,
      'repeat': repeat,
    }).catchError((Object error) {
      // Não é crítico (só os botões da miniatura ficam desatualizados), mas
      // libera o próximo envio para tentar de novo.
      _lastSentKey = null;
      debugPrint('[taskbar-media] falha ao atualizar botões: $error');
    });
  }

  // ---- nativo -> Dart ------------------------------------------------------

  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method != 'button') return;

    final queue = _ref.read(queueControllerProvider.notifier);
    try {
      switch (call.arguments) {
        case 'shuffle':
          await queue.toggleShuffle();
          break;
        case 'previous':
          await queue.previous();
          break;
        case 'playPause':
          await queue.togglePlayPause();
          break;
        case 'next':
          await queue.next();
          break;
        case 'repeat':
          queue.cycleRepeatMode();
          break;
      }
    } catch (e, stackTrace) {
      debugPrint('[taskbar-media] falha ao executar "${call.arguments}": '
          '$e\n$stackTrace');
    }
  }
}

final taskbarMediaControllerProvider = Provider<TaskbarMediaController>((ref) {
  final controller = TaskbarMediaController(ref);
  ref.onDispose(controller.dispose);
  controller.start();
  return controller;
});

/// Widget fininho que só instancia o [TaskbarMediaController] (que se
/// liga sozinho ao `QueueController`/player) — mesmo padrão do
/// `TrayModeActivator`. Espera o primeiro frame de propósito: assim o
/// `queueControllerProvider` (e, junto, o `AudioPlayerService`) continua
/// sendo criado na mesma ordem de sempre, pela árvore de widgets, e não
/// um instante antes dela por causa deste recurso.
class TaskbarMediaActivator extends ConsumerStatefulWidget {
  final Widget child;
  const TaskbarMediaActivator({super.key, required this.child});

  @override
  ConsumerState<TaskbarMediaActivator> createState() =>
      _TaskbarMediaActivatorState();
}

class _TaskbarMediaActivatorState extends ConsumerState<TaskbarMediaActivator> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(taskbarMediaControllerProvider);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
