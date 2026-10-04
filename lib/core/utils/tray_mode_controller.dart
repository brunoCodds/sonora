import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../data/models/mini_player_layout.dart';
import '../../providers/miniplayer_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/theme_providers.dart';
import '../constants/app_constants.dart';
import 'window_bounds.dart';
import 'window_glass.dart';
import 'window_mode.dart';

/// Tamanho do painel mini/bandeja dos designs Clássico e Compacto — compacto
/// de propósito, no estilo "now playing" comum em players de música (capa
/// quadrada, texto alinhado à esquerda, controles numa linha só). Os outros
/// designs têm tamanho próprio, que combina com o que eles são (ver
/// `MiniPlayerLayout.windowSize`); é esse tamanho, do design escolhido na
/// tela de Perfil, que [TrayModeController.showMini] aplica.
const Size kMiniWindowSize = Size(320, 480);

/// Chave de posição salva do painel de um design: cada design lembra a sua
/// (ver `MiniPlayerLayout.positionKeySuffix`).
String _miniPositionKey(String baseKey, MiniPlayerLayout layout) =>
    '$baseKey${layout.positionKeySuffix}';

/// Coloca a Sonora pra rodar em segundo plano, estilo Discord: fechar
/// pela borda (X) não encerra o processo, só esconde a janela e deixa um
/// ícone na bandeja. Um clique nesse ícone mostra um painel reduzido
/// (`MiniPlayerScreen`, trocado em `app.dart` via [windowModeProvider]);
/// um clique duplo abre a janela cheia direto. Só sai de verdade pelo
/// item "Sair" do menu do botão direito.
///
/// Reaproveita a MESMA janela/engine para os dois modos, em vez de criar
/// uma segunda janela flutuante: trocar de modo só muda o tamanho, a
/// posição e o estilo da janela atual. Mais simples e mais robusto do
/// que gerenciar duas engines Flutter à parte, e nunca faria sentido
/// mostrar os dois ao mesmo tempo de qualquer forma.
///
/// Posição do painel mini: na primeira vez que aparece (nenhuma posição
/// salva ainda), centraliza na tela — não tenta adivinhar onde fica a
/// bandeja (o Windows não expõe isso de forma confiável, e uma
/// aproximação errada é exatamente o que causava o painel aparecer
/// cortado, fora da tela). Assim que o usuário arrasta o painel pra
/// outro lugar (ver [onWindowMoved]), essa posição é salva e passa a ser
/// usada sempre — o usuário só precisa ajustar isso uma vez.
///
/// É uma classe comum (não um widget) registrada num `Provider`, e não
/// um `ConsumerStatefulWidget` como o `ResizePlaybackGuard`/
/// `WindowBoundsPersistence` — de propósito: o botão "abrir app
/// completo" dentro do `MiniPlayerScreen` precisa chamar [showFull]
/// vindo de um widget totalmente diferente na árvore, e isso fica muito
/// mais simples com `ref.read(trayModeControllerProvider).showFull()` do
/// que tentando alcançar o estado privado de outro widget. Quem liga o
/// ciclo de vida disso à árvore de widgets é o [TrayModeActivator], logo
/// abaixo.
class TrayModeController with WindowListener, TrayListener {
  final Ref _ref;
  TrayModeController(this._ref);

  static const _keyShowFull = 'show_full';
  static const _keyExit = 'exit';

  WindowMode _mode = WindowMode.full;
  bool _exiting = false;

  /// `true` se a janela cheia estava maximizada quando o painel mini foi
  /// aberto. Guardado só na transição cheio -> mini (não a cada reabertura
  /// do painel) pra [showFull] devolver a janela maximizada, igual estava.
  bool _wasMaximizedBeforeMini = false;
  Timer? _pendingSingleClick;
  Timer? _traySwitchResetTimer;
  Timer? _miniPositionSaveDebounce;

  Future<void> init() async {
    windowManager.addListener(this);
    trayManager.addListener(this);

    // Impede o fechamento nativo (X / Alt+F4) de encerrar o processo —
    // a partir daqui ele só chega até nós via onWindowClose() abaixo.
    // Chamado o mais cedo possível (direto em initState, sem esperar o
    // primeiro frame) pra deixar a menor janela de corrida possível
    // entre "app abriu" e "isso está realmente ativo".
    await windowManager.setPreventClose(true);

    try {
      await trayManager.setIcon('assets/icons/tray_icon.ico');
    } catch (_) {
      // Sem ícone disponível por algum motivo: o ícone da bandeja
      // simplesmente não aparece, mas o resto do app continua normal.
    }
    await trayManager.setToolTip(AppConstants.appName);
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: _keyShowFull, label: 'Abrir Sonora'),
          MenuItem.separator(),
          MenuItem(key: _keyExit, label: 'Sair'),
        ],
      ),
    );
  }

  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    _pendingSingleClick?.cancel();
    _traySwitchResetTimer?.cancel();
    _miniPositionSaveDebounce?.cancel();
  }

  // ---- Eventos da bandeja ----------------------------------------------

  @override
  void onTrayIconMouseDown() {
    // Esta versão do tray_manager só avisa "o ícone foi clicado", sem
    // distinguir clique simples de duplo. Detecta o duplo-clique aqui:
    // se um segundo clique chegar antes do temporizador do primeiro
    // disparar, é um clique duplo (abre cheio) — senão, passado esse
    // intervalo sem um segundo clique, era só um clique simples (mostra
    // o painel mini).
    if (_pendingSingleClick != null) {
      _pendingSingleClick!.cancel();
      _pendingSingleClick = null;
      showFull();
      return;
    }
    _pendingSingleClick = Timer(const Duration(milliseconds: 260), () {
      _pendingSingleClick = null;
      toggleMini();
    });
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _keyShowFull:
        showFull();
        break;
      case _keyExit:
        exitApp();
        break;
    }
  }

  // ---- Eventos da janela -------------------------------------------------

  @override
  void onWindowClose() {
    // setPreventClose(true) faz o X chegar até aqui em vez de fechar de
    // verdade. Só deixamos fechar mesmo quando foi o "Sair" do menu (ver
    // exitApp) que pediu — qualquer outro fechamento vira "esconder pra
    // bandeja", igual ao Discord.
    if (_exiting) return;
    _beginTraySwitch();
    windowManager.hide();
  }

  @override
  void onWindowBlur() {
    // Comportamento de flyout: o painel mini some ao clicar em outro
    // lugar. Não vale para o modo cheio — perder o foco ali (por
    // exemplo, ao alternar pra outro programa) não deveria esconder o
    // app principal.
    if (_mode == WindowMode.mini) {
      windowManager.hide();
    }
  }

  @override
  void onWindowMoved() {
    if (_mode != WindowMode.mini) return;
    _miniPositionSaveDebounce?.cancel();
    _miniPositionSaveDebounce = Timer(const Duration(milliseconds: 400), () async {
      final bounds = await windowManager.getBounds();
      final settings = _ref.read(settingsRepositoryProvider);
      final layout = _ref.read(miniPlayerLayoutProvider);
      settings.setDouble(_miniPositionKey(AppConstants.keyMiniWindowPosX, layout), bounds.left);
      settings.setDouble(_miniPositionKey(AppConstants.keyMiniWindowPosY, layout), bounds.top);
    });
  }

  // ---- Troca de modo -----------------------------------------------------

  /// Avisa o `ResizePlaybackGuard` (via `traySwitchingModeProvider`) que
  /// os próximos eventos de redimensionamento são uma troca de modo
  /// programática, não um arraste do usuário — evita uma pausa/retomada
  /// audível toda vez que o painel mini abre ou fecha. Usa um timer em
  /// vez de um try/finally em volta da chamada de setBounds porque o
  /// evento correspondente do WindowListener pode chegar de volta pelo
  /// canal de plataforma um pouco depois da chamada retornar — o timer
  /// dá uma margem seguindo o mesmo padrão de debounce já usado no
  /// próprio ResizePlaybackGuard.
  void _beginTraySwitch() {
    _ref.read(traySwitchingModeProvider.notifier).state = true;
    _traySwitchResetTimer?.cancel();
    _traySwitchResetTimer = Timer(const Duration(milliseconds: 600), () {
      _ref.read(traySwitchingModeProvider.notifier).state = false;
    });
  }

  /// Garante que a janela NÃO está maximizada nem em tela cheia de verdade.
  ///
  /// No Windows, `window_manager` 0.4.3 faz `maximize()`/`unmaximize()` via
  /// `PostMessage` — ou seja, a chamada volta antes de o estado realmente
  /// mudar. Por isso, depois de pedir pra sair, espera (com limite) até
  /// `isMaximized()` virar `false`, senão o `setSize()` seguinte ainda
  /// bateria numa janela maximizada.
  Future<void> _leaveMaximizedOrFullScreen() async {
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
    }
    if (!await windowManager.isMaximized()) return;

    await windowManager.unmaximize();
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!await windowManager.isMaximized()) return;
    }
  }

  Future<void> toggleMini() async {
    if (_mode == WindowMode.mini && await windowManager.isVisible()) {
      await windowManager.hide();
      return;
    }
    await showMini();
  }

  Future<void> showMini() async {
    // Só guarda o estado da janela cheia na transição cheio -> mini. Se o
    // painel já estava em modo mini (ex.: fechou ao perder o foco e foi
    // aberto de novo), a janela já foi "normalizada" e o valor guardado
    // lá atrás precisa ser preservado.
    if (_mode == WindowMode.full) {
      _wasMaximizedBeforeMini = await windowManager.isMaximized();
    }
    _mode = WindowMode.mini;
    _beginTraySwitch();

    // Design escolhido na tela de Perfil: define o tamanho do painel.
    final layout = _ref.read(miniPlayerLayoutProvider);
    final miniSize = layout.windowSize;

    // IMPORTANTE: aqui a ordem é o OPOSTO de showFull(). Troca o conteúdo
    // pra MiniPlayerScreen (ver windowModeProvider em app.dart) ANTES de
    // encostar na janela. O MiniPlayerScreen é seguro em qualquer
    // tamanho (capa e controles de tamanho fixo), então não há problema
    // em ele existir por um instante dentro da janela ainda grande. Já o
    // AppShell (larguras pensadas pra 860px+) NÃO é seguro numa janela
    // pequena: se o redimensionamento viesse primeiro, ele ficava montado
    // — e pintando, com show() no meio — dentro da janela já encolhida
    // pra 320px durante várias idas ao canal de plataforma, causando
    // "RenderFlex overflowed" (ex.: song_tile.dart) a cada abertura.
    //
    // Efeito colateral bom: WindowBoundsPersistence só grava o tamanho da
    // janela quando windowModeProvider == full; com o modo já em mini
    // desde o início, o resize pra 320x480 nunca é gravado por engano
    // como se fosse o tamanho "normal" do app.
    _ref.read(windowModeProvider.notifier).state = WindowMode.mini;

    // IMPORTANTE: o tamanho mínimo definido lá no início do app
    // (AppConstants.minWindowWidth/Height, pro modo cheio) continua
    // sendo aplicado pelo Windows a QUALQUER redimensionamento — mesmo
    // programático, mesmo com setResizable(false) — porque o Windows
    // consulta WM_GETMINMAXINFO (onde esse mínimo é reportado) toda vez
    // que o tamanho de uma janela muda, não só quando o usuário arrasta
    // a borda. Sem isso aqui, setBounds() abaixo pedia 320x480 mas o
    // Windows silenciosamente aumentava de volta pro mínimo de 860x560
    // — era por isso que o painel mini aparecia enorme e cortado (a
    // posição era calculada pra uma janela de 320x480, mas o Windows
    // desenhava 860x560 ali, sobrando pra fora da tela).
    // CAUSA DO BUG "painel fora de proporção": se a janela estava
    // MAXIMIZADA (ou em tela cheia) quando foi fechada pela bandeja, ela
    // continua marcada como maximizada mesmo escondida. setSize() é só um
    // SetWindowPos — não tira a janela desse estado, então o Windows
    // seguia mostrando o painel com o tamanho da tela inteira. Por isso
    // tem que sair do estado maximizado ANTES de pedir o tamanho do mini.
    await _leaveMaximizedOrFullScreen();

    await windowManager.setMinimumSize(miniSize);
    await windowManager.setResizable(false);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSize(miniSize);

    final savedPosition = loadSavedPosition(
      _ref.read(settingsRepositoryProvider),
      xKey: _miniPositionKey(AppConstants.keyMiniWindowPosX, layout),
      yKey: _miniPositionKey(AppConstants.keyMiniWindowPosY, layout),
    );
    if (savedPosition != null) {
      await windowManager.setPosition(savedPosition);
    } else {
      await windowManager.center();
    }

    // Transparência (só no design "Discreto"): DEPOIS de definir o estilo da
    // barra de título e o tamanho acima — mudar o estilo zera a configuração
    // de moldura que o efeito usa — e ANTES do show(), pra o painel já
    // aparecer translúcido em vez de piscar opaco primeiro. O estilo (Vidro,
    // Transparente ou Sólido) é o escolhido na tela de Perfil. Se falhar
    // (Windows sem suporte, plugin indisponível), fica `false` e o painel
    // usa um fundo sólido.
    if (layout.usesGlass) {
      _beginTraySwitch();
      final active = await WindowGlass.apply(
        _ref.read(currentPaletteProvider),
        _ref.read(miniGlassStyleProvider),
      );
      _ref.read(miniGlassActiveProvider.notifier).state = active;
    } else {
      // Design sem transparência: garante que nada de antes ficou ligado.
      _ref.read(miniGlassActiveProvider.notifier).state = false;
      await WindowGlass.clear();
    }

    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> showFull() async {
    _mode = WindowMode.full;
    _beginTraySwitch();

    // Tira o efeito ANTES de mexer no estilo/tamanho da janela (ver
    // WindowGlass). Não faz nada se ele não estava ligado.
    _ref.read(miniGlassActiveProvider.notifier).state = false;
    await WindowGlass.clear();

    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    // Restaura o mínimo do modo cheio (ver o comentário equivalente em
    // showMini) antes de pedir o tamanho salvo — senão, se esse tamanho
    // salvo for menor que os 320x480 do mini (não deveria acontecer,
    // mas por segurança), o Windows aplicaria o mínimo errado.
    await windowManager
        .setMinimumSize(const Size(AppConstants.minWindowWidth, AppConstants.minWindowHeight));
    await windowManager.setResizable(true);

    final saved = loadSavedWindowBounds(_ref.read(settingsRepositoryProvider));
    await windowManager.setSize(saved.size);
    final position = saved.position;
    if (position != null) {
      await windowManager.setPosition(position);
    } else {
      await windowManager.center();
    }
    await windowManager.show();
    await windowManager.focus();

    // Se a janela cheia estava maximizada antes do painel mini abrir,
    // maximiza de novo (o tamanho "normal" salvo acima continua valendo
    // pra quando o usuário restaurar a janela).
    if (_wasMaximizedBeforeMini) {
      _wasMaximizedBeforeMini = false;
      await windowManager.maximize();
    }

    // IMPORTANTE: só troca o conteúdo pra AppShell (windowModeProvider,
    // lido em app.dart) DEPOIS que a janela já foi redimensionada pro
    // tamanho cheio, nunca antes. `ref....state = WindowMode.full`
    // reconstrói a árvore de widgets NA HORA (síncrono), enquanto
    // setSize() acima é assíncrono e efetivamente mais lento — se a
    // troca de conteúdo viesse primeiro (como estava numa versão
    // anterior), a tela cheia (com listas/grades pensadas pra uma janela
    // de 860px+) chegava a ser desenhada por um instante ainda dentro da
    // janela de 320px do modo mini, antes do setSize() acima terminar.
    // Foi exatamente isso que causou aquele erro "Leading widget
    // consumes the entire tile width" na tela de Artistas: por uma
    // fração de segundo, o ListTile tentou se desenhar numa largura de
    // pouquíssimos pixels. Flutter geralmente se recupera sozinho no
    // frame seguinte (por isso "funcionava perfeitamente" apesar do
    // erro no log), mas não é algo que deveria acontecer.
    //
    // (Em showMini() a ordem é a inversa, pelo mesmo motivo visto do
    // outro lado: lá o conteúdo que precisa estar na tela primeiro é o
    // MiniPlayerScreen, que é o seguro em janela pequena.)
    //
    // Como o `await` de setSize() só garante que o nativo executou a
    // chamada — não que o framework já recebeu o novo tamanho e refez o
    // layout —, o `_RootScreenSwitcher` (app.dart) também recusa montar
    // o AppShell enquanto a largura disponível for menor que a mínima
    // do modo cheio. Isso cobre essa corrida entre os dois canais.
    _ref.read(windowModeProvider.notifier).state = WindowMode.full;
  }

  Future<void> exitApp() async {
    _exiting = true;
    await trayManager.destroy();
    await windowManager.destroy();
  }
}

final trayModeControllerProvider = Provider<TrayModeController>((ref) {
  final controller = TrayModeController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

/// Widget fininho que só liga o [TrayModeController] ao ciclo de vida da
/// árvore de widgets (chama [TrayModeController.init] uma vez). Toda a
/// lógica de verdade mora na classe acima.
///
/// Chama `init()` direto em `initState` (sem esperar o primeiro frame
/// via `addPostFrameCallback`) — `ref.read` pra uma ação pontual (não um
/// `ref.watch` num `build`) é seguro de chamar em `initState`, e isso
/// fecha uma fresta de tempo entre "o app abriu" e "o prevent-close já
/// está realmente ativo".
class TrayModeActivator extends ConsumerStatefulWidget {
  final Widget child;
  const TrayModeActivator({super.key, required this.child});

  @override
  ConsumerState<TrayModeActivator> createState() => _TrayModeActivatorState();
}

class _TrayModeActivatorState extends ConsumerState<TrayModeActivator> {
  @override
  void initState() {
    super.initState();
    ref.read(trayModeControllerProvider).init();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
