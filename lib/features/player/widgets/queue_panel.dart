import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../providers/audio_providers.dart';
import '../../../providers/navigation_providers.dart';
import '../../../shared_widgets/app_list_tile.dart';
import '../../../shared_widgets/cover_art.dart';
import '../../../shared_widgets/empty_state.dart';

class QueuePanel extends ConsumerWidget {
  const QueuePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final queueState = ref.watch(queueControllerProvider);
    final notifier = ref.read(queueControllerProvider.notifier);

    return Container(
      width: 320,
      color: palette.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                const Text(
                  'Fila de reprodução',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (queueState.queue.isNotEmpty)
                  TextButton(
                    onPressed: notifier.clearQueue,
                    child: const Text('Limpar'),
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => ref.read(queuePanelOpenProvider.notifier).state = false,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: queueState.queue.isEmpty
                ? const EmptyState(
                    icon: Icons.queue_music_outlined,
                    title: 'Fila vazia',
                    message: 'Toque uma música para começar a montar sua fila.',
                  )
                : ExcludeSemantics(
                    // ExcludeSemantics: ReorderableListView tem um bug
                    // documentado e ainda em aberto no motor do Flutter no
                    // Windows — a forma como ele insere/remove nós da árvore
                    // de semântica durante o arraste (mesmo sem nenhum
                    // leitor de tela ativo) corrompe a árvore de
                    // acessibilidade nativa e pode derrubar o app, às vezes
                    // só na próxima ação (como um resize) que force um
                    // recálculo dessa árvore já corrompida. É exatamente o
                    // padrão visto nos crashes ao reordenar a fila e criar
                    // playlists. Perde a reordenação por teclado/leitor de
                    // tela; a reordenação por arraste do mouse continua
                    // normal.
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.only(top: 8, bottom: 16),
                      itemCount: queueState.queue.length,
                      onReorderItem: notifier.reorderQueue,
                      itemBuilder: (context, index) {
                        final song = queueState.queue[index];
                        final isCurrent = index == queueState.currentIndex;
                        return Material(
                          // A key precisa estar no widget de mais fora
                          // retornado pelo itemBuilder — é o que o
                          // ReorderableListView usa pra identificar cada
                          // item durante o arraste. (AppListTile já cuida
                          // do próprio Material/splash de toque por
                          // dentro, mas a key continua precisando ficar
                          // aqui fora.)
                          key: ValueKey('queue_${song.id}_$index'),
                          color: Colors.transparent,
                          child: AppListTile(
                            dense: true,
                            leading: CoverArt(
                              path: song.coverPath,
                              imageUrl: song.coverUrl,
                              size: 40,
                              borderRadius: 5,
                            ),
                            title: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isCurrent
                                    ? palette.accentVariant
                                    : palette.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              song.artist.isEmpty ? 'Artista desconhecido' : song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  TextStyle(fontSize: 12, color: palette.textSecondary),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  DurationFormatter.formatMs(song.durationMs),
                                  style: TextStyle(
                                      fontSize: 11, color: palette.textSecondary),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 16),
                                  onPressed: () => notifier.removeFromQueue(index),
                                ),
                              ],
                            ),
                            onTap: () => notifier.playAt(index),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
