import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Em qual "forma" a janela está agora.
///
/// [full] é o app inteiro, do jeito de sempre. [mini] é o painel
/// reduzido que aparece ao clicar no ícone da bandeja — mesma janela,
/// mesma engine, só com bounds/estilo diferentes e mostrando
/// [MiniPlayerScreen] em vez de [AppShell] (ver `app.dart`).
enum WindowMode { full, mini }

/// Fonte da verdade de qual modo está ativo agora. Só o
/// `TrayModeController` deveria escrever aqui; todo o resto (o switch em
/// `app.dart`, o `WindowBoundsPersistence`) só lê.
final windowModeProvider = StateProvider<WindowMode>((ref) => WindowMode.full);

/// `true` só durante a troca de modo do `TrayModeController`
/// (`showMini`/`showFull`). O redimensionamento programático dessa troca
/// também dispara os mesmos eventos de `WindowListener` que um arraste
/// de borda feito pelo usuário — sem isso, o `ResizePlaybackGuard`
/// pausaria a música por um instante toda vez que o painel mini abrisse
/// ou fechasse, já que ele reage a qualquer redimensionamento, não só a
/// um arraste de verdade.
final traySwitchingModeProvider = StateProvider<bool>((ref) => false);
