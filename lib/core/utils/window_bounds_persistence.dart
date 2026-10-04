import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../providers/repository_providers.dart';
import '../constants/app_constants.dart';
import 'window_mode.dart';

/// Salva o tamanho e a posição da janela sempre que o usuário termina de
/// redimensionar ou mover (com debounce, para não bater no banco a cada
/// pixel arrastado), para que possam ser restaurados na próxima
/// abertura. Ver `main.dart`, que lê os valores salvos aqui antes de
/// `windowManager.waitUntilReadyToShow`.
///
/// Fica num widget próprio, separado do `ResizePlaybackGuard`, mesmo os
/// dois usando a mesma API de `WindowListener`: são duas
/// responsabilidades independentes (uma mitiga um crash pausando a
/// música durante o resize; esta só observa e persiste o tamanho/posição
/// final) que só por acaso escutam os mesmos eventos de janela — misturar
/// as duas deixaria qualquer uma das duas mais arriscada de mexer no
/// futuro sem afetar a outra.
///
/// Propositalmente NÃO tenta salvar o estado "maximizada": enquanto
/// maximizada, `getBounds()` devolve o retângulo da tela cheia, não o
/// tamanho "normal" de antes — salvar isso faria a janela reabrir do
/// tamanho da tela mesmo depois do usuário restaurá-la. Mais simples e
/// mais previsível: ignora eventos que chegam com a janela maximizada, e
/// só grava o retângulo "normal" (restaurado).
class WindowBoundsPersistence extends ConsumerStatefulWidget {
  final Widget child;

  const WindowBoundsPersistence({super.key, required this.child});

  @override
  ConsumerState<WindowBoundsPersistence> createState() =>
      _WindowBoundsPersistenceState();
}

class _WindowBoundsPersistenceState
    extends ConsumerState<WindowBoundsPersistence> with WindowListener {
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _saveDebounce?.cancel();
    super.dispose();
  }

  @override
  void onWindowResized() => _scheduleSave();

  @override
  void onWindowMoved() => _scheduleSave();

  @override
  void onWindowUnmaximize() => _scheduleSave();

  void _scheduleSave() {
    // Debounce curto: onWindowMoved/onWindowResized podem disparar várias
    // vezes em sequência (ex.: Aero Snap dispara mover + redimensionar
    // juntos). Espera tudo se acalmar antes de gravar.
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _saveNow);
  }

  Future<void> _saveNow() async {
    // O `TrayModeController` redimensiona a janela pra um retângulo bem
    // menor ao entrar no modo mini/bandeja — isso também dispara
    // onWindowResized/onWindowMoved, mas não é um tamanho que o usuário
    // escolheu, então não pode ser salvo como se fosse o normal (senão
    // o app abriria minúsculo da próxima vez).
    if (ref.read(windowModeProvider) != WindowMode.full) return;
    if (await windowManager.isMaximized()) return;
    if (!mounted) return;

    final bounds = await windowManager.getBounds();
    if (!mounted) return;

    final settings = ref.read(settingsRepositoryProvider);
    settings.setDouble(AppConstants.keyWindowWidth, bounds.width);
    settings.setDouble(AppConstants.keyWindowHeight, bounds.height);
    settings.setDouble(AppConstants.keyWindowPosX, bounds.left);
    settings.setDouble(AppConstants.keyWindowPosY, bounds.top);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
