import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../providers/shortcut_providers.dart';
import '../../../shortcuts/key_binding.dart';
import '../../../shortcuts/shortcut_action.dart';

/// Lista editável de atalhos de teclado, usada na tela de Configurações.
/// Cada linha mostra a ação, a tecla atual (ou "Não definido") e permite
/// capturar uma nova combinação ou remover o atalho.
class ShortcutBindingsEditor extends ConsumerWidget {
  const ShortcutBindingsEditor({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, ShortcutAction action) async {
    final captured = await showDialog<KeyBinding>(
      context: context,
      builder: (_) => _KeyCaptureDialog(action: action),
    );
    if (captured == null || !context.mounted) return;

    final result = ref.read(shortcutBindingsProvider.notifier).rebind(action, captured);
    if (!result.success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"${captured.label}" já está em uso para "${result.conflictsWith!.label}". '
            'Escolha outra combinação.',
          ),
        ),
      );
    }
  }

  Future<void> _confirmResetAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restaurar atalhos padrão?'),
        content: const Text('Qualquer personalização que você tenha feito será perdida.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(shortcutBindingsProvider.notifier).resetAll();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final bindings = ref.watch(shortcutBindingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final action in ShortcutAction.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(action.label, style: TextStyle(color: palette.textSecondary)),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _edit(context, ref, action),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 74),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: palette.surfaceHighlight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      bindings[action]?.label ?? 'Não definido',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: bindings[action] == null
                      ? null
                      : IconButton(
                          tooltip: 'Remover atalho',
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.close_rounded, size: 16),
                          onPressed: () => ref.read(shortcutBindingsProvider.notifier).clear(action),
                        ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _confirmResetAll(context, ref),
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: const Text('Restaurar padrões'),
          ),
        ),
      ],
    );
  }
}

/// Diálogo modal que fica esperando a próxima combinação de teclas real
/// (ignorando modificadores sozinhos) pra usar como novo atalho.
class _KeyCaptureDialog extends StatefulWidget {
  final ShortcutAction action;
  const _KeyCaptureDialog({required this.action});

  @override
  State<_KeyCaptureDialog> createState() => _KeyCaptureDialogState();
}

class _KeyCaptureDialogState extends State<_KeyCaptureDialog> {
  final _focusNode = FocusNode(debugLabel: 'shortcut-capture');
  String _heldModifiers = '';

  @override
  void initState() {
    super.initState();
    // `autofocus: true` no Focus abaixo já deveria bastar, mas o pedido
    // explícito depois do primeiro frame é uma rede de segurança barata
    // contra qualquer disputa de foco dentro do Overlay do diálogo.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    if (KeyBinding.isModifierOnly(event.logicalKey)) {
      // Só um modificador foi pressionado até agora — continua esperando
      // a tecla "de verdade" e só atualiza a dica na tela.
      setState(() {
        _heldModifiers = [
          if (HardwareKeyboard.instance.isControlPressed) 'Ctrl',
          if (HardwareKeyboard.instance.isShiftPressed) 'Shift',
          if (HardwareKeyboard.instance.isAltPressed) 'Alt',
        ].join(' + ');
      });
      return KeyEventResult.handled;
    }

    Navigator.of(context).pop(KeyBinding.fromEvent(event));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      title: Text('Novo atalho — ${widget.action.label}'),
      content: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _heldModifiers.isEmpty
                    ? 'Pressione a combinação de teclas desejada...'
                    : '$_heldModifiers + ...',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary),
              ),
              const SizedBox(height: 10),
              Text(
                'Esc para cancelar',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textDisabled, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
