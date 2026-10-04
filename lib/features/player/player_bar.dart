import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_palette.dart';
import '../../data/models/repeat_mode.dart';
import '../../providers/audio_providers.dart';
import '../../providers/navigation_providers.dart';
import '../../shared_widgets/app_icon_button.dart';
import '../../shared_widgets/cover_art.dart';
import '../../shared_widgets/download_button.dart';
import '../../shared_widgets/favorite_button.dart';
import '../song_details/song_details_sheet.dart';
import 'widgets/progress_bar.dart';
import 'widgets/volume_control.dart';

class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final queueState = ref.watch(queueControllerProvider);
    final isPlaying = ref.watch(playerPlayingProvider).value ?? false;
    final song = queueState.currentSong;
    final queuePanelOpen = ref.watch(queuePanelOpenProvider);
    final notifier = ref.read(queueControllerProvider.notifier);

    return Container(
      height: AppConstants.playerBarHeight,
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: song == null
                ? Text('Nenhuma música tocando',
                    style: TextStyle(color: palette.textSecondary, fontSize: 13))
                : InkWell(
                    onTap: () => showSongDetailsSheet(context, song),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CoverArt(
                          path: song.coverPath,
                          imageUrl: song.coverUrl,
                          size: 56,
                          borderRadius: 6,
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                song.artist.isEmpty ? 'Artista desconhecido' : song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: palette.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          Expanded(
            flex: 5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppIconButton(
                      icon: Icons.shuffle_rounded,
                      active: queueState.shuffleEnabled,
                      tooltip: 'Aleatório',
                      onPressed: notifier.toggleShuffle,
                      size: 18,
                    ),
                    AppIconButton(
                      icon: Icons.skip_previous_rounded,
                      tooltip: 'Anterior',
                      onPressed: song == null ? null : notifier.previous,
                      size: 26,
                    ),
                    const SizedBox(width: 4),
                    _PlayPauseButton(isPlaying: isPlaying, hasSong: song != null),
                    const SizedBox(width: 4),
                    AppIconButton(
                      icon: Icons.skip_next_rounded,
                      tooltip: 'Próxima',
                      onPressed: song == null ? null : notifier.next,
                      size: 26,
                    ),
                    AppIconButton(
                      icon: _repeatIcon(queueState.repeatMode),
                      active: queueState.repeatMode != RepeatMode.off,
                      tooltip: 'Repetir',
                      onPressed: notifier.cycleRepeatMode,
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const SizedBox(
                  width: 480,
                  child: PlayerProgressBar(),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (song != null) FavoriteButton(song: song),
                if (song != null) const SizedBox(width: 4),
                if (song != null) DownloadButton(song: song),
                const SizedBox(width: 4),
                // Flexible: deixa o slider de volume encolher quando a
                // janela está no tamanho mínimo (ver VolumeControl).
                const Flexible(child: VolumeControl()),
                AppIconButton(
                  icon: Icons.queue_music_rounded,
                  active: queuePanelOpen,
                  tooltip: 'Fila de reprodução',
                  onPressed: () => ref.read(queuePanelOpenProvider.notifier).state =
                      !queuePanelOpen,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _repeatIcon(RepeatMode mode) {
    return switch (mode) {
      RepeatMode.one => Icons.repeat_one_rounded,
      RepeatMode.all || RepeatMode.off => Icons.repeat_rounded,
    };
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
          padding: const EdgeInsets.all(8),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 22,
            color: hasSong ? palette.background : palette.textDisabled,
          ),
        ),
      ),
    );
  }
}
