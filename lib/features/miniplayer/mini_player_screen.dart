import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/app_palette.dart';
import '../../core/utils/duration_formatter.dart';
import '../../core/utils/tray_mode_controller.dart';
import '../../core/utils/window_glass.dart';
import '../../data/models/mini_player_layout.dart';
import '../../data/models/repeat_mode.dart';
import '../../providers/audio_providers.dart';
import '../../providers/miniplayer_providers.dart';
import '../../providers/volume_providers.dart';
import '../../shared_widgets/app_icon_button.dart';
import '../../shared_widgets/app_list_tile.dart';
import '../../shared_widgets/cover_art.dart';
import '../../shared_widgets/download_button.dart';
import '../../shared_widgets/empty_state.dart';
import '../../shared_widgets/favorite_button.dart';
import '../player/widgets/progress_bar.dart';

/// Painel compacto mostrado quando a janela está no modo bandeja (ver
/// `TrayModeController`/`WindowMode`, e a troca em `app.dart`). Reaproveita
/// os mesmos providers do player completo (é literalmente a mesma música
/// tocando na mesma engine, só numa tela menor).
///
/// O visual depende do design escolhido na tela de Perfil
/// ([miniPlayerLayoutProvider]):
///
/// * [MiniPlayerLayout.classico]: duas telas dentro da mesma janelinha,
///   trocadas localmente (sem outra janela ou diálogo) — o "tocando agora"
///   de sempre, e a fila atual, alternadas pelo botão de fila junto dos
///   outros controles.
/// * [MiniPlayerLayout.compacto]: uma tela só; capa pequena ao lado do
///   título, controles e a fila "a seguir" sempre visível embaixo.
/// * [MiniPlayerLayout.limpo] (320x420): capa redonda, progresso, título,
///   os três controles principais bem espaçados e o volume. Sem fila.
/// * [MiniPlayerLayout.capaCheia] (320x320, quadrado): a capa preenche o
///   painel, com os controles por cima (estilo do mini player do Spotify).
///   Sem barra superior — o painel inteiro arrasta a janela.
/// * [MiniPlayerLayout.discreto] (360x172): cartão pequeno de vidro — a
///   janela fica translúcida e borra o que está atrás dela.
///
/// Cada design tem o tamanho de janela do próprio design
/// (`MiniPlayerLayout.windowSize`, aplicado pelo `TrayModeController`). Este
/// widget só desenha o conteúdo — e, por ser montado ANTES de a janela ser
/// redimensionada (ver `TrayModeController.showMini`), todo design precisa
/// continuar seguro em qualquer tamanho de janela.
class MiniPlayerScreen extends ConsumerStatefulWidget {
  const MiniPlayerScreen({super.key});

  @override
  ConsumerState<MiniPlayerScreen> createState() => _MiniPlayerScreenState();
}

class _MiniPlayerScreenState extends ConsumerState<MiniPlayerScreen> {
  /// Só usado pelo design clássico (o compacto mostra a fila o tempo todo).
  bool _showQueue = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final layout = ref.watch(miniPlayerLayoutProvider);
    final showingQueue = layout == MiniPlayerLayout.classico && _showQueue;
    // Com a transparência realmente ligada na janela, o fundo do painel
    // precisa ser transparente pra ela aparecer. Sem ela (estilo sólido, ou
    // se falhou, ou durante o arrasto), fundo sólido.
    final glass = layout.usesGlass && ref.watch(miniGlassActiveProvider);

    return Material(
      color: glass ? Colors.transparent : palette.background,
      child: switch (layout) {
        MiniPlayerLayout.classico => _withTopBar(
            showingQueue: showingQueue,
            body: _showQueue
                ? _MiniQueueView(onBack: () => setState(() => _showQueue = false))
                : _MiniNowPlaying(onShowQueue: () => setState(() => _showQueue = true)),
          ),
        MiniPlayerLayout.compacto =>
          _withTopBar(showingQueue: false, body: const _MiniCompactView()),
        MiniPlayerLayout.limpo =>
          _withTopBar(showingQueue: false, body: const _MiniCleanView()),
        // Estes dois cuidam do próprio topo (sem a barra padrão).
        MiniPlayerLayout.capaCheia => const _MiniFullCoverView(),
        MiniPlayerLayout.discreto => _MiniDiscreetView(glass: glass),
      },
    );
  }

  /// Barra superior padrão + o conteúdo do design.
  Widget _withTopBar({required bool showingQueue, required Widget body}) {
    return Column(
      children: [
        _TopBar(showingQueue: showingQueue),
        Expanded(child: body),
      ],
    );
  }
}

class _TopBar extends ConsumerWidget {
  final bool showingQueue;
  const _TopBar({required this.showingQueue});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    // DragToMoveArea: a barra de título nativa fica escondida no modo
    // mini (ver TrayModeController.showMini), então é assim que o
    // usuário consegue arrastar o painel pra outro lugar se quiser — a
    // posição escolhida é lembrada (ver TrayModeController.onWindowMoved)
    // e usada da próxima vez que o painel aparecer.
    //
    // GestureDetector próprio em vez do `DragToMoveArea`: o
    // `DragToMoveArea` trata duplo-clique como "maximizar a janela", o que
    // num painel mini de tamanho fixo deixaria ele gigante e fora de
    // proporção.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 36,
        padding: const EdgeInsets.only(left: 10, right: 2),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(bottom: BorderSide(color: palette.divider)),
        ),
        child: Row(
          children: [
            Icon(Icons.graphic_eq_rounded, size: 14, color: palette.accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                showingQueue ? 'Fila de reprodução' : 'Sonora',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: palette.textSecondary,
                ),
              ),
            ),
            AppIconButton(
              icon: Icons.open_in_full_rounded,
              tooltip: 'Abrir Sonora completo',
              size: 15,
              onPressed: () => ref.read(trayModeControllerProvider).showFull(),
            ),
            AppIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Fechar painel',
              size: 15,
              onPressed: () => windowManager.hide(),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniNowPlaying extends ConsumerWidget {
  final VoidCallback onShowQueue;
  const _MiniNowPlaying({required this.onShowQueue});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final queueState = ref.watch(queueControllerProvider);
    final isPlaying = ref.watch(playerPlayingProvider).value ?? false;
    final song = queueState.currentSong;
    final notifier = ref.read(queueControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Center(
            child: CoverArt(
              path: song?.coverPath,
              imageUrl: song?.coverUrl,
              size: 176,
              borderRadius: 12,
            ),
          ),
          const SizedBox(height: 16),
          // Título/artista à esquerda + coração de favorito à direita —
          // igual ao layout de "now playing" comum em outros players.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song?.title ?? 'Nenhuma música tocando',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song == null
                          ? ' '
                          : (song.artist.isEmpty ? 'Artista desconhecido' : song.artist),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              if (song != null) FavoriteButton(song: song, size: 20),
              if (song != null) const SizedBox(width: 4),
              if (song != null) DownloadButton(song: song, size: 20),
            ],
          ),
          const SizedBox(height: 14),
          const PlayerProgressBar(),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MiniControlIcon(
                icon: Icons.shuffle_rounded,
                active: queueState.shuffleEnabled,
                tooltip: 'Aleatório',
                onPressed: notifier.toggleShuffle,
              ),
              _MiniControlIcon(
                icon: Icons.skip_previous_rounded,
                tooltip: 'Anterior',
                onPressed: song == null ? null : notifier.previous,
                boxSize: 34,
                iconSize: 23,
              ),
              _PlayPauseButton(isPlaying: isPlaying, hasSong: song != null),
              _MiniControlIcon(
                icon: Icons.skip_next_rounded,
                tooltip: 'Próxima',
                onPressed: song == null ? null : notifier.next,
                boxSize: 34,
                iconSize: 23,
              ),
              _MiniControlIcon(
                icon: _repeatIcon(queueState.repeatMode),
                active: queueState.repeatMode != RepeatMode.off,
                tooltip: 'Repetir',
                onPressed: notifier.cycleRepeatMode,
              ),
              _MiniControlIcon(
                icon: Icons.queue_music_rounded,
                tooltip: 'Fila atual',
                onPressed: onShowQueue,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

IconData _repeatIcon(RepeatMode mode) {
  return switch (mode) {
    RepeatMode.one => Icons.repeat_one_rounded,
    RepeatMode.all || RepeatMode.off => Icons.repeat_rounded,
  };
}

/// Botão de controle compacto, com alvo de toque menor do que o
/// `IconButton`/`AppIconButton` padrão (que reservam ~48px mesmo pra
/// ícones pequenos) — necessário pra caber shuffle, anterior, play/pause,
/// próxima, repetir E fila numa linha só dentro dos 320px do painel mini.
class _MiniControlIcon extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double boxSize;
  final double iconSize;

  const _MiniControlIcon({
    required this.icon,
    this.active = false,
    required this.onPressed,
    this.tooltip,
    this.boxSize = 28,
    this.iconSize = 17,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = active
        ? palette.accent
        : (onPressed == null ? palette.textDisabled : palette.textPrimary);

    final button = SizedBox(
      width: boxSize,
      height: boxSize,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(icon, size: iconSize, color: color),
        onPressed: onPressed,
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Versão compacta da `QueuePanel` do app completo, pensada pra caber
/// numa janela pequena — sem arrastar pra reordenar (não é essencial
/// aqui, e simplifica) e sem o botão "Limpar". Toca uma música da lista
/// com um toque, igual à fila do app completo.
class _MiniQueueView extends ConsumerWidget {
  final VoidCallback onBack;
  const _MiniQueueView({required this.onBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                tooltip: 'Voltar',
                onPressed: onBack,
              ),
              Text(
                'Próximas',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palette.textSecondary),
              ),
            ],
          ),
        ),
        const Expanded(child: _MiniQueueList()),
      ],
    );
  }
}

/// Lista de músicas da fila, compartilhada pelos dois designs do painel.
/// Com [upcomingOnly] mostra só o que vem depois da música atual (usado
/// pelo design compacto, onde a fila fica sempre visível embaixo dos
/// controles); sem ele, mostra a fila inteira com a atual destacada (o
/// comportamento da tela de fila do design clássico).
class _MiniQueueList extends ConsumerWidget {
  final bool upcomingOnly;
  const _MiniQueueList({this.upcomingOnly = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final queueState = ref.watch(queueControllerProvider);
    final notifier = ref.read(queueControllerProvider.notifier);

    // Índice, dentro de `queueState.queue`, da primeira música mostrada.
    final firstIndex = upcomingOnly && queueState.currentIndex >= 0
        ? queueState.currentIndex + 1
        : 0;
    final itemCount = queueState.queue.length - firstIndex;

    if (itemCount <= 0) {
      if (upcomingOnly) {
        return Center(
          child: Text(
            queueState.queue.isEmpty ? 'Fila vazia' : 'Nada a seguir',
            style: TextStyle(fontSize: 12, color: palette.textSecondary),
          ),
        );
      }
      return const EmptyState(
        icon: Icons.queue_music_outlined,
        title: 'Fila vazia',
        message: 'Toque uma música para começar a montar sua fila.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: itemCount,
      itemBuilder: (context, i) {
        final index = firstIndex + i;
        final song = queueState.queue[index];
        final isCurrent = index == queueState.currentIndex;
        return AppListTile(
          dense: true,
          leading: CoverArt(
            path: song.coverPath,
            imageUrl: song.coverUrl,
            size: 36,
            borderRadius: 5,
          ),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isCurrent ? palette.accentVariant : palette.textPrimary,
            ),
          ),
          subtitle: Text(
            song.artist.isEmpty ? 'Artista desconhecido' : song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: palette.textSecondary),
          ),
          trailing: Text(
            DurationFormatter.formatMs(song.durationMs),
            style: TextStyle(fontSize: 11, color: palette.textSecondary),
          ),
          onTap: () => notifier.playAt(index),
        );
      },
    );
  }
}

/// Design [MiniPlayerLayout.compacto]: uma tela só. Capa pequena ao lado
/// do título/artista, barra de progresso, os cinco controles (sem o botão
/// de fila — ela já está logo abaixo) e a lista "A seguir" ocupando o
/// resto da altura.
///
/// Tamanho seguro dentro dos 320x480 do painel: a parte fixa (capa +
/// progresso + controles) ocupa ~190px dos ~444px úteis (abaixo da barra
/// superior de 36px), e a lista é um `Expanded` — só ela se ajusta, então
/// nada aqui pode estourar em altura.
class _MiniCompactView extends ConsumerWidget {
  const _MiniCompactView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final queueState = ref.watch(queueControllerProvider);
    final isPlaying = ref.watch(playerPlayingProvider).value ?? false;
    final song = queueState.currentSong;
    final notifier = ref.read(queueControllerProvider.notifier);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Column(
            children: [
              Row(
                children: [
                  CoverArt(
                    path: song?.coverPath,
                    imageUrl: song?.coverUrl,
                    size: 64,
                    borderRadius: 8,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song?.title ?? 'Nenhuma música tocando',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song == null
                              ? ' '
                              : (song.artist.isEmpty ? 'Artista desconhecido' : song.artist),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: palette.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (song != null) FavoriteButton(song: song, size: 20),
                  if (song != null) const SizedBox(width: 4),
                  if (song != null) DownloadButton(song: song, size: 20),
                ],
              ),
              const SizedBox(height: 8),
              const PlayerProgressBar(),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _MiniControlIcon(
                    icon: Icons.shuffle_rounded,
                    active: queueState.shuffleEnabled,
                    tooltip: 'Aleatório',
                    onPressed: notifier.toggleShuffle,
                  ),
                  _MiniControlIcon(
                    icon: Icons.skip_previous_rounded,
                    tooltip: 'Anterior',
                    onPressed: song == null ? null : notifier.previous,
                    boxSize: 34,
                    iconSize: 23,
                  ),
                  _PlayPauseButton(isPlaying: isPlaying, hasSong: song != null),
                  _MiniControlIcon(
                    icon: Icons.skip_next_rounded,
                    tooltip: 'Próxima',
                    onPressed: song == null ? null : notifier.next,
                    boxSize: 34,
                    iconSize: 23,
                  ),
                  _MiniControlIcon(
                    icon: _repeatIcon(queueState.repeatMode),
                    active: queueState.repeatMode != RepeatMode.off,
                    tooltip: 'Repetir',
                    onPressed: notifier.cycleRepeatMode,
                  ),
                ],
              ),
            ],
          ),
        ),
        Divider(height: 1, color: palette.divider),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'A seguir',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: palette.textSecondary,
              ),
            ),
          ),
        ),
        const Expanded(child: _MiniQueueList(upcomingOnly: true)),
      ],
    );
  }
}

class _PlayPauseButton extends ConsumerWidget {
  final bool isPlaying;
  final bool hasSong;
  const _PlayPauseButton({required this.isPlaying, required this.hasSong});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return Material(
      color: hasSong ? palette.textPrimary : palette.surfaceHighlight,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: hasSong
            ? () => ref.read(queueControllerProvider.notifier).togglePlayPause()
            : null,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 24,
            color: hasSong ? palette.background : palette.textDisabled,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Design LIMPO (320x420)
// ---------------------------------------------------------------------------

/// Design [MiniPlayerLayout.limpo]: capa redonda, barra de progresso com os
/// tempos nas pontas, título/artista centralizados e, numa faixa mais clara
/// embaixo, anterior / play-pausa / próxima bem espaçados (distribuídos pela
/// largura toda, com o play em destaque) e o volume.
///
/// A janela é mais baixa que a do clássico (420 em vez de 480): sobra pouco
/// espaço vazio. A capa NÃO tem tamanho fixo — ocupa o que sobrar da altura
/// (96 a 168px) depois de reservar o resto — e o conjunto "capa + progresso
/// + textos" fica num `FittedBox(scaleDown)`: se algo vier maior que o
/// previsto (fonte maior, por exemplo), ele encolhe um pouco em vez de
/// estourar o layout.
class _MiniCleanView extends ConsumerWidget {
  const _MiniCleanView();

  /// Altura reservada pro que fica abaixo da capa (espaço + progresso +
  /// dois textos), mais a folga do padding.
  static const double _reservedBelowCover = 112;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final queueState = ref.watch(queueControllerProvider);
    final isPlaying = ref.watch(playerPlayingProvider).value ?? false;
    final song = queueState.currentSong;
    final notifier = ref.read(queueControllerProvider.notifier);

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cover = (constraints.maxHeight - _reservedBelowCover).clamp(96.0, 168.0).toDouble();
              // Nunca negativa (a janela passa por tamanhos intermediários
              // na troca de modo; ver TrayModeController.showMini).
              final contentWidth = (constraints.maxWidth - 48).clamp(0.0, double.infinity).toDouble();
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: contentWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CoverArt(
                            path: song?.coverPath,
                            imageUrl: song?.coverUrl,
                            size: cover,
                            borderRadius: cover / 2,
                          ),
                          const SizedBox(height: 14),
                          const PlayerProgressBar(),
                          const SizedBox(height: 4),
                          Text(
                            song?.title ?? 'Nenhuma música tocando',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song == null
                                ? ' '
                                : (song.artist.isEmpty ? 'Artista desconhecido' : song.artist),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: palette.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          width: double.infinity,
          color: palette.surface,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _MiniControlIcon(
                    icon: Icons.skip_previous_rounded,
                    tooltip: 'Anterior',
                    onPressed: song == null ? null : notifier.previous,
                    boxSize: 46,
                    iconSize: 32,
                  ),
                  _BigPlayButton(
                    isPlaying: isPlaying,
                    onPressed: song == null ? null : notifier.togglePlayPause,
                  ),
                  _MiniControlIcon(
                    icon: Icons.skip_next_rounded,
                    tooltip: 'Próxima',
                    onPressed: song == null ? null : notifier.next,
                    boxSize: 46,
                    iconSize: 32,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const _MiniVolume(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Play/pause redondo na cor de destaque do tema (60px), pro botão
/// principal do design limpo.
class _BigPlayButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback? onPressed;

  const _BigPlayButton({required this.isPlaying, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: isPlaying ? 'Pausar' : 'Tocar',
      child: Material(
        color: onPressed == null ? palette.surfaceHighlight : palette.accent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 60,
            height: 60,
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 36,
              color: onPressed == null ? palette.textDisabled : palette.labelOnAccent,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Design CAPA CHEIA (320x320, estilo mini player do Spotify)
// ---------------------------------------------------------------------------

/// Sombra leve nos textos/ícones desenhados por cima da capa, pra
/// continuarem legíveis mesmo sobre uma imagem clara.
const List<Shadow> _kOverlayShadows = [Shadow(color: Colors.black54, blurRadius: 8)];

/// Design [MiniPlayerLayout.capaCheia]: painel QUADRADO (320x320) em que a
/// capa preenche tudo e os controles ficam por cima — anterior / play grande
/// / próxima no centro, o "fechar" no canto de cima, o "abrir o Sonora
/// completo" no canto de baixo à direita e o título/artista embaixo à
/// esquerda. Uma linha fininha de progresso fica na borda de baixo.
///
/// As cores aqui são FIXAS (branco sobre a imagem, com um degradê escuro
/// por trás), de propósito: elas ficam por cima de uma foto, não de uma
/// superfície do tema, então não devem mudar com a paleta.
///
/// Não há barra superior neste design, então o painel inteiro arrasta a
/// janela (`windowManager.startDragging()` no início do arraste) — a
/// posição é lembrada pelo `TrayModeController`, igual aos outros designs.
/// Usa um `GestureDetector` próprio em vez do `DragToMoveArea` de propósito:
/// o `DragToMoveArea` também trata duplo-clique como "maximizar a janela", e
/// aqui o painel inteiro é clicável (um duplo-clique rápido em play/pause não
/// pode virar outro gesto da janela).
class _MiniFullCoverView extends ConsumerWidget {
  const _MiniFullCoverView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueState = ref.watch(queueControllerProvider);
    final isPlaying = ref.watch(playerPlayingProvider).value ?? false;
    final song = queueState.currentSong;
    final notifier = ref.read(queueControllerProvider.notifier);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CoverArt(
            path: song?.coverPath,
            imageUrl: song?.coverUrl,
            size: double.infinity,
            borderRadius: 0,
          ),
          // Escurece de leve o miolo (onde ficam os controles) e mais nas
          // bordas de cima e de baixo (onde ficam os botões e o texto).
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x99000000), Color(0x33000000), Color(0x33000000), Color(0xCC000000)],
                stops: [0, 0.3, 0.55, 1],
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: _OverlayIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Fechar painel',
              onPressed: () => windowManager.hide(),
            ),
          ),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _OverlayIconButton(
                  icon: Icons.skip_previous_rounded,
                  tooltip: 'Anterior',
                  boxSize: 48,
                  iconSize: 32,
                  onPressed: song == null ? null : notifier.previous,
                ),
                const SizedBox(width: 14),
                _OverlayPlayButton(
                  isPlaying: isPlaying,
                  onPressed: song == null ? null : notifier.togglePlayPause,
                ),
                const SizedBox(width: 14),
                _OverlayIconButton(
                  icon: Icons.skip_next_rounded,
                  tooltip: 'Próxima',
                  boxSize: 48,
                  iconSize: 32,
                  onPressed: song == null ? null : notifier.next,
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 56,
            bottom: 18,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song?.title ?? 'Nenhuma música tocando',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    shadows: _kOverlayShadows,
                  ),
                ),
                if (song != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    song.artist.isEmpty ? 'Artista desconhecido' : song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                      shadows: _kOverlayShadows,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            right: 4,
            bottom: 10,
            child: _OverlayIconButton(
              icon: Icons.open_in_full_rounded,
              tooltip: 'Abrir Sonora completo',
              onPressed: () => ref.read(trayModeControllerProvider).showFull(),
            ),
          ),
          const Positioned(left: 0, right: 0, bottom: 0, child: _MiniThinProgress()),
        ],
      ),
    );
  }
}

/// Botão de ícone pra desenhar por cima de uma imagem ou de um vidro:
/// branco com sombra por padrão (sobre foto); passe [color] e
/// [withShadow] = false pra usar sobre uma superfície de tema.
class _OverlayIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double boxSize;
  final double iconSize;
  final Color color;
  final bool withShadow;

  const _OverlayIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.boxSize = 36,
    this.iconSize = 20,
    this.color = Colors.white,
    this.withShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: boxSize,
        height: boxSize,
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(
            icon,
            size: iconSize,
            color: onPressed == null ? color.withValues(alpha: 0.38) : color,
            shadows: withShadow ? _kOverlayShadows : null,
          ),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// "Abrir o Sonora completo" e "Fechar o painel", lado a lado. É o que
/// substitui a barra superior padrão nos designs que não têm uma (capa
/// cheia e discreto).
class _MiniWindowButtons extends ConsumerWidget {
  final Color color;
  final double size;
  final double iconSize;
  final bool withShadow;

  const _MiniWindowButtons({
    required this.color,
    this.size = 30,
    this.iconSize = 17,
    this.withShadow = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _OverlayIconButton(
          icon: Icons.open_in_full_rounded,
          tooltip: 'Abrir Sonora completo',
          boxSize: size,
          iconSize: iconSize,
          color: color,
          withShadow: withShadow,
          onPressed: () => ref.read(trayModeControllerProvider).showFull(),
        ),
        _OverlayIconButton(
          icon: Icons.close_rounded,
          tooltip: 'Fechar painel',
          boxSize: size,
          iconSize: iconSize,
          color: color,
          withShadow: withShadow,
          onPressed: () => windowManager.hide(),
        ),
      ],
    );
  }
}

/// Play/pause redondo e branco (ícone preto), como no mini player do
/// Spotify.
class _OverlayPlayButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback? onPressed;

  const _OverlayPlayButton({required this.isPlaying, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isPlaying ? 'Pausar' : 'Tocar',
      child: Material(
        color: onPressed == null ? Colors.white38 : Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 72,
            height: 72,
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 44,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}

/// Linha de progresso de 3px, só pra mostrar (não é arrastável). Fica em
/// `ExcludeSemantics` pelo mesmo motivo do `PlayerProgressBar`: ela muda a
/// cada ~250ms, e atualizar a árvore de acessibilidade nessa frequência
/// derruba o motor do Flutter no Windows quando há leitor de tela/lupa
/// ativo (ver o comentário em `progress_bar.dart`).
class _MiniThinProgress extends ConsumerWidget {
  const _MiniThinProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(playerPositionProvider).value ?? Duration.zero;
    final duration = ref.watch(playerDurationProvider).value ?? Duration.zero;
    final fraction = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble();

    return ExcludeSemantics(
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: 3,
        color: Colors.white,
        backgroundColor: Colors.white24,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Design DISCRETO (360x172, cartão de vidro)
// ---------------------------------------------------------------------------

/// Design [MiniPlayerLayout.discreto]: um cartão pequeno e baixinho de
/// vidro. A janela fica translúcida (e, no estilo "Vidro", desfocada) — ver
/// `WindowGlass` e `MiniGlassStyle`; o app só desenha por cima uma tinta da
/// cor do tema, com a opacidade escolhida no Perfil
/// ([miniGlassOpacityProvider]), pro texto continuar legível.
///
/// Conteúdo: miniatura da capa + título/artista + "abrir completo" e
/// "fechar" no canto; progresso; favoritar, anterior / play / próxima
/// (centralizados de verdade) e um volume pequeno.
///
/// Se não há transparência ([glass] = false: estilo "Sólido", o efeito
/// falhou, ou o painel está sendo arrastado), o cartão usa um fundo sólido
/// da cor de superfície do tema.
///
/// O painel inteiro arrasta a janela (ficando sólido durante o arrasto — ver
/// [_GlassDragArea]); os sliders têm prioridade em arrastos horizontais
/// (então mexer no progresso/volume não move a janela). Tudo fica num
/// `FittedBox(scaleDown)`, como rede de segurança contra estouro.
class _MiniDiscreetView extends ConsumerWidget {
  /// Se a janela está translúcida agora.
  final bool glass;
  const _MiniDiscreetView({required this.glass});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final queueState = ref.watch(queueControllerProvider);
    final isPlaying = ref.watch(playerPlayingProvider).value ?? false;
    final song = queueState.currentSong;
    final notifier = ref.read(queueControllerProvider.notifier);
    final opacity = ref.watch(miniGlassOpacityProvider);

    return _GlassDragArea(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: glass ? palette.background.withValues(alpha: opacity) : palette.surface,
          border: Border.all(color: palette.textPrimary.withValues(alpha: 0.12)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CoverArt(
                              path: song?.coverPath,
                              imageUrl: song?.coverUrl,
                              size: 56,
                              borderRadius: 10,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 56,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      song?.title ?? 'Nenhuma música tocando',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      song == null
                                          ? ' '
                                          : (song.artist.isEmpty
                                              ? 'Artista desconhecido'
                                              : song.artist),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12, color: palette.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _MiniWindowButtons(
                              color: palette.textSecondary,
                              size: 28,
                              iconSize: 16,
                              withShadow: false,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const PlayerProgressBar(),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            // Os dois Expanded têm a mesma largura: é isso que
                            // mantém anterior/play/próxima exatamente no meio.
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: song == null
                                    ? const SizedBox.shrink()
                                    : FavoriteButton(song: song, size: 20),
                              ),
                            ),
                            _MiniControlIcon(
                              icon: Icons.skip_previous_rounded,
                              tooltip: 'Anterior',
                              onPressed: song == null ? null : notifier.previous,
                              boxSize: 38,
                              iconSize: 28,
                            ),
                            _MiniControlIcon(
                              icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              tooltip: isPlaying ? 'Pausar' : 'Tocar',
                              onPressed: song == null ? null : notifier.togglePlayPause,
                              boxSize: 46,
                              iconSize: 38,
                            ),
                            _MiniControlIcon(
                              icon: Icons.skip_next_rounded,
                              tooltip: 'Próxima',
                              onPressed: song == null ? null : notifier.next,
                              boxSize: 38,
                              iconSize: 28,
                            ),
                            const Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: SizedBox(width: 96, child: _MiniVolume()),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Área que arrasta a janela inteira, usada pelo painel Discreto.
///
/// Uma janela translúcida fica MUITO lenta de arrastar em alguns Windows
/// (atraso grande, com um cursor "fantasma"), e não há como saber de antes
/// se vai acontecer. Então, ao começar o arrasto, o painel vira sólido e o
/// efeito do Windows é desligado — o mesmo estado dos outros designs, que
/// arrastam bem — e tudo volta ao soltar. Passos, na ordem (cada um espera o
/// anterior, de propósito):
///   1. o painel passa a ser desenhado sólido;
///   2. espera esse quadro ser desenhado (senão desligar o efeito deixaria
///      um quadro translúcido sem nada atrás);
///   3. desliga o efeito do Windows;
///   4. `startDragging()` — que só termina quando o botão do mouse é solto
///      (ele roda o laço de mover do próprio Windows), mas só se o botão
///      ainda estiver apertado: sem esta checagem, um clique rápido faria a
///      janela "grudar" no cursor até o próximo clique;
///   5. religa o efeito e 6. volta o painel a ser translúcido.
/// Desligue com `WindowGlass.solidWhileDragging = false`.
class _GlassDragArea extends ConsumerStatefulWidget {
  final Widget child;
  const _GlassDragArea({required this.child});

  @override
  ConsumerState<_GlassDragArea> createState() => _GlassDragAreaState();
}

class _GlassDragAreaState extends ConsumerState<_GlassDragArea> {
  bool _pressed = false;

  Future<void> _drag() async {
    final active = ref.read(miniGlassActiveProvider.notifier);
    if (!WindowGlass.solidWhileDragging || !active.state) {
      await windowManager.startDragging();
      return;
    }

    active.state = false; // 1
    await WidgetsBinding.instance.endOfFrame; // 2
    await WindowGlass.suspendForDrag(); // 3
    if (_pressed) {
      await windowManager.startDragging(); // 4
    }
    _pressed = false;
    await WindowGlass.resumeAfterDrag(); // 5
    active.state = true; // 6
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _pressed = true,
      onPointerUp: (_) => _pressed = false,
      onPointerCancel: (_) => _pressed = false,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => _drag(),
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Volume (usado pelos designs limpo e discreto)
// ---------------------------------------------------------------------------

IconData _volumeIcon(double volume, bool muted) {
  if (muted || volume == 0) return Icons.volume_off_rounded;
  if (volume < 50) return Icons.volume_down_rounded;
  return Icons.volume_up_rounded;
}

/// Ícone de mudo + slider de volume numa linha, no tamanho do painel mini.
/// Usa o mesmo `volumeControllerProvider` do `VolumeControl` do app
/// completo — mudar o volume aqui muda lá, e vice-versa.
class _MiniVolume extends ConsumerWidget {
  const _MiniVolume();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final state = ref.watch(volumeControllerProvider);
    final controller = ref.read(volumeControllerProvider.notifier);

    return Row(
      children: [
        Tooltip(
          message: state.muted ? 'Ativar o som' : 'Silenciar',
          child: SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(
                _volumeIcon(state.volume, state.muted),
                size: 18,
                color: palette.textSecondary,
              ),
              onPressed: controller.toggleMute,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              min: 0,
              max: 100,
              value: state.effectiveVolume,
              onChanged: controller.setVolume,
            ),
          ),
        ),
      ],
    );
  }
}
