import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/audio_providers.dart';
import '../providers/shortcut_providers.dart';
import '../providers/volume_providers.dart';
import 'shortcut_action.dart';

/// Envolve toda a aplicação e escuta os atalhos de teclado globais
/// definidos em [shortcutBindingsProvider] (editáveis em Configurações).
///
/// Atalhos são ignorados quando o foco está em um campo de texto (ex:
/// busca), para não atrapalhar a digitação.
class KeyboardShortcutsHandler extends ConsumerWidget {
  final Widget child;

  const KeyboardShortcutsHandler({super.key, required this.child});

  /// Antes, isso checava só `primaryFocus?.context?.widget is EditableText`
  /// — mas o `BuildContext` de um `FocusNode` de campo de texto não é o
  /// `EditableText` em si, e sim um `Focus` interno que ele mesmo cria
  /// (`EditableText.build()` envolve o conteúdo editável nesse `Focus`,
  /// repassando o FocusNode recebido). Ou seja, `context.widget` nunca
  /// era um `EditableText`, e essa checagem sempre devolvia `false` — os
  /// atalhos disparavam mesmo digitando. Subindo pelos ancestrais a
  /// partir desse `Focus` interno, o `EditableText` que o envolve aparece
  /// como um deles.
  bool _isTypingInTextField() {
    final element = FocusManager.instance.primaryFocus?.context;
    if (element == null) return false;
    if (element.widget is EditableText) return true;

    var found = false;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is EditableText) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  KeyEventResult _handleKey(WidgetRef ref, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_isTypingInTextField()) return KeyEventResult.ignored;

    final bindings = ref.read(shortcutBindingsProvider);
    ShortcutAction? matchedAction;
    for (final entry in bindings.entries) {
      final binding = entry.value;
      if (binding != null && binding.matchesEvent(event)) {
        matchedAction = entry.key;
        break;
      }
    }
    if (matchedAction == null) return KeyEventResult.ignored;

    final queue = ref.read(queueControllerProvider.notifier);
    final volume = ref.read(volumeControllerProvider.notifier);
    final audio = ref.read(audioPlayerServiceProvider);

    switch (matchedAction) {
      case ShortcutAction.playPause:
        queue.togglePlayPause();
        break;
      case ShortcutAction.next:
        queue.next();
        break;
      case ShortcutAction.previous:
        queue.previous();
        break;
      case ShortcutAction.seekForward:
        audio.seekRelative(const Duration(seconds: 5));
        break;
      case ShortcutAction.seekBackward:
        audio.seekRelative(const Duration(seconds: -5));
        break;
      case ShortcutAction.volumeUp:
        volume.nudge(5);
        break;
      case ShortcutAction.volumeDown:
        volume.nudge(-5);
        break;
      case ShortcutAction.mute:
        volume.toggleMute();
        break;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) => _handleKey(ref, event),
      child: child,
    );
  }
}
