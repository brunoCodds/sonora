import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../providers/audio_providers.dart';
import 'window_mode.dart';

/// Mitigação para um crash nativo conhecido no Windows: algo no motor de
/// áudio (media_kit/libmpv, que roda em suas próprias threads nativas —
/// hoje isoladas em sua própria Dart isolate, ver `AudioPlayerService`)
/// parece entrar em conflito com o loop de redimensionamento do Windows
/// quando uma música está tocando ativamente.
///
/// Duas fontes disparam a pausa/retomada, porque cada uma cobre um caso
/// que a outra não cobre:
///
/// 1. Canal nativo `sonora/native_resize_guard` (ver `flutter_window.cpp`):
///    dispara em WM_ENTERSIZEMOVE/WM_EXITSIZEMOVE, ou seja, no instante
///    em que o usuário começa a arrastar a borda da janela — antes de
///    qualquer WM_SIZE. É o sinal mais cedo possível, fechando a janela
///    de corrida que existia numa versão anterior desta guarda (que só
///    reagia depois que o primeiro redimensionamento já tinha
///    acontecido). Não cobre maximizar/restaurar por duplo-clique ou
///    atalho de teclado.
/// 2. `window_manager` (`onWindowResize`/`onWindowResized`): reage depois
///    que a janela já mudou de tamanho, mas cobre TODOS os casos,
///    incluindo maximizar/restaurar — que não passam por
///    WM_ENTERSIZEMOVE.
///
/// As duas fontes convergem num único estado (`_pausedByGuard`), então
/// não importa qual dispara primeiro: a pausa/retomada é idempotente.
///
/// Ignora redimensionamentos que vêm do `TrayModeController` trocando
/// entre o modo cheio e o painel mini/bandeja (ver
/// `traySwitchingModeProvider`) — são resizes de uma tacada só, não o
/// tipo de arraste contínuo que motivou essa mitigação, e pausar a
/// música por causa deles seria só um soluço perceptível sem necessidade.
class ResizePlaybackGuard extends ConsumerStatefulWidget {
  final Widget child;

  const ResizePlaybackGuard({super.key, required this.child});

  @override
  ConsumerState<ResizePlaybackGuard> createState() =>
      _ResizePlaybackGuardState();
}

class _ResizePlaybackGuardState extends ConsumerState<ResizePlaybackGuard>
    with WindowListener {
  static const _nativeChannel = MethodChannel('sonora/native_resize_guard');

  bool _pausedByGuard = false;
  bool _nativeResizeInProgress = false;
  Timer? _resumeDebounce;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _nativeChannel.setMethodCallHandler(_onNativeMethodCall);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _nativeChannel.setMethodCallHandler(null);
    _resumeDebounce?.cancel();
    super.dispose();
  }

  Future<void> _onNativeMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'resizeWillBegin':
        _nativeResizeInProgress = true;
        _resumeDebounce?.cancel();
        _pauseForResize();
        break;
      case 'resizeDidEnd':
        _nativeResizeInProgress = false;
        _scheduleResume(const Duration(milliseconds: 150));
        break;
    }
  }

  @override
  void onWindowResize() {
    // Troca de modo do TrayModeController (abrir/fechar o painel mini) —
    // não é um arraste do usuário, não precisa pausar por causa disso.
    if (ref.read(traySwitchingModeProvider)) return;
    // Dispara repetidamente durante o arraste (e é a única fonte para
    // casos que não passam por WM_ENTERSIZEMOVE, como maximizar).
    _pauseForResize();
    _scheduleResume(const Duration(milliseconds: 400));
  }

  @override
  void onWindowResized() {
    // Se o canal nativo já está cuidando de retomar (resizeDidEnd), não
    // faz nada aqui para não dar um "play" duplicado/prematuro.
    if (_nativeResizeInProgress) return;
    _scheduleResume(Duration.zero);
  }

  void _pauseForResize() {
    final audio = ref.read(audioPlayerServiceProvider);
    if (!_pausedByGuard && audio.isPlaying) {
      debugPrint('[resize-guard] pausando por redimensionamento');
      _pausedByGuard = true;
      audio.suspendForResize();
    }
  }

  void _scheduleResume(Duration delay) {
    _resumeDebounce?.cancel();
    if (delay == Duration.zero) {
      _maybeResume();
    } else {
      _resumeDebounce = Timer(delay, _maybeResume);
    }
  }

  void _maybeResume() {
    if (!_pausedByGuard) return;
    debugPrint('[resize-guard] retomando depois do redimensionamento');
    _pausedByGuard = false;
    if (!mounted) return;
    ref.read(audioPlayerServiceProvider).resumeFromResize();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
