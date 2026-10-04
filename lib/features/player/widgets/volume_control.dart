import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/volume_providers.dart';

class VolumeControl extends ConsumerWidget {
  const VolumeControl({super.key});

  IconData _iconFor(double volume, bool muted) {
    if (muted || volume == 0) return Icons.volume_off_rounded;
    if (volume < 50) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(volumeControllerProvider);
    final controller = ref.read(volumeControllerProvider.notifier);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(_iconFor(state.volume, state.muted), size: 20),
          onPressed: controller.toggleMute,
          splashRadius: 18,
        ),
        // Largura MÁXIMA de 100, não fixa: na janela no tamanho mínimo a
        // seção direita do PlayerBar recebe menos que os ~224px que o
        // conjunto (coração + volume + fila) precisaria com um slider de
        // 100 fixos, e estourava por ~2px. Com Flexible + maxWidth o
        // slider ocupa até 100 quando há espaço e encolhe só o
        // necessário quando não há — sem depender de escala de DPI nem do
        // tamanho exato da moldura da janela.
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100),
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
        ),
      ],
    );
  }
}
