import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_palette.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/resize_playback_guard.dart';
import 'core/utils/taskbar_media_controller.dart';
import 'core/utils/tray_mode_controller.dart';
import 'core/utils/window_bounds_persistence.dart';
import 'core/utils/window_mode.dart';
import 'features/miniplayer/mini_player_screen.dart';
import 'features/shell/app_shell.dart';
import 'providers/theme_providers.dart';
import 'shortcuts/keyboard_shortcuts.dart';

class SonoraApp extends ConsumerWidget {
  const SonoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Observa só a paleta escolhida (tela de Perfil): este widget só
    // reconstrói quando o usuário troca de tema. O MaterialApp anima a
    // passagem de um ThemeData pro outro (ver AppPalette.lerp).
    final palette = ref.watch(currentPaletteProvider);
    final theme = AppTheme.fromPalette(palette);

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: palette.isDark ? ThemeMode.dark : ThemeMode.light,
      home: const TrayModeActivator(
        child: TaskbarMediaActivator(
          child: WindowBoundsPersistence(
            child: ResizePlaybackGuard(
              child: KeyboardShortcutsHandler(child: _RootScreenSwitcher()),
            ),
          ),
        ),
      ),
    );
  }
}

/// Largura mínima disponível abaixo da qual o [AppShell] NÃO deve ser
/// montado. A janela em modo cheio nunca fica menor que
/// [AppConstants.minWindowWidth] (860, ~847 de área útil depois da
/// moldura) por ação do usuário, então uma largura menor que isso só
/// acontece durante a troca de modo do `TrayModeController` (o painel
/// mini tem ~307 de área útil). 700 fica com folga dos dois lados.
const double _kMinFullLayoutWidth = 700;

/// Mostra o app inteiro ou o painel mini/bandeja, dependendo de
/// [windowModeProvider] — trocado pelo `TrayModeController` sempre que a
/// janela troca de modo. Um `ConsumerWidget` fininho aqui em vez de mais
/// lógica no `SonoraApp` é de propósito: só esse pedacinho da árvore
/// precisa reconstruir quando o modo muda.
///
/// Rede de segurança: mesmo com o `TrayModeController` trocando o
/// conteúdo na ordem certa, o `await windowManager.setSize()` só garante
/// que o lado nativo executou a chamada, não que o framework já recebeu o
/// novo tamanho e refez o layout (são dois canais assíncronos
/// diferentes). Se o [AppShell] chegar a ser montado num frame ainda com a
/// largura do painel mini, TODOS os widgets dele estouram (PlayerBar,
/// cabeçalhos, SongTile...). Em vez de proteger cada widget, recusa-se
/// montar o AppShell enquanto a largura for menor que a mínima do modo
/// cheio — esse estado é sempre transitório, então um quadro vazio
/// (com a cor de fundo) é o resultado correto. Nenhum estado se perde: o
/// AppShell já é desmontado a cada troca de modo de qualquer forma.
class _RootScreenSwitcher extends ConsumerWidget {
  const _RootScreenSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final mode = ref.watch(windowModeProvider);
    return switch (mode) {
      WindowMode.full => LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < _kMinFullLayoutWidth) {
              return ColoredBox(color: palette.background);
            }
            return const AppShell();
          },
        ),
      WindowMode.mini => const MiniPlayerScreen(),
    };
  }
}
