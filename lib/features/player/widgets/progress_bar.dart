import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../providers/audio_providers.dart';

class PlayerProgressBar extends ConsumerStatefulWidget {
  const PlayerProgressBar({super.key});

  @override
  ConsumerState<PlayerProgressBar> createState() => _PlayerProgressBarState();
}

class _PlayerProgressBarState extends ConsumerState<PlayerProgressBar> {
  double? _dragValueMs;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final position = ref.watch(playerPositionProvider).value ?? Duration.zero;
    final duration = ref.watch(playerDurationProvider).value ?? Duration.zero;

    final maxMs = duration.inMilliseconds.toDouble();
    final safeMax = maxMs <= 0 ? 1.0 : maxMs;
    final currentMs =
        (_dragValueMs ?? position.inMilliseconds.toDouble()).clamp(0.0, safeMax);

    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            DurationFormatter.formatMs(currentMs.toInt()),
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: palette.textSecondary),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            // ExcludeSemantics: este Slider é atualizado automaticamente a
            // cada ~250ms enquanto a música toca (ver playerPositionProvider
            // em audio_providers.dart). Confirmado via Visualizador de
            // Eventos do Windows que, com um leitor de tela/lupa ativo, o
            // motor do Flutter no Windows tem um bug real de estouro de
            // buffer (STATUS_STACK_BUFFER_OVERRUN) dentro do próprio
            // flutter_windows.dll ao reconstruir a árvore de acessibilidade
            // (AXTree) com essa frequência — derruba o processo inteiro,
            // não só trava. Não é algo que dá pra corrigir daqui (é um bug
            // do motor), então a opção seguinte é excluir só este widget da
            // árvore de semântica: ele perde a leitura por leitor de tela,
            // mas o app para de crashar para quem usa um. O resto do app
            // (botões, listas, menus) continua totalmente acessível.
            child: ExcludeSemantics(
              child: Slider(
                min: 0,
                max: safeMax,
                value: currentMs,
                onChanged: maxMs <= 0
                    ? null
                    : (value) => setState(() => _dragValueMs = value),
                onChangeEnd: (value) {
                  ref
                      .read(audioPlayerServiceProvider)
                      .seek(Duration(milliseconds: value.toInt()));
                  setState(() => _dragValueMs = null);
                },
              ),
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            DurationFormatter.format(duration),
            style: TextStyle(fontSize: 11, color: palette.textSecondary),
          ),
        ),
      ],
    );
  }
}
