import 'package:flutter/services.dart';

/// Uma combinação de tecla + modificadores (Ctrl/Shift/Alt), usada tanto
/// para os atalhos padrão quanto para o que o usuário escolher em
/// Configurações.
///
/// É um tipo de valor: duas instâncias com a mesma tecla e os mesmos
/// modificadores são `==`, o que é essencial tanto pra detectar conflito
/// entre dois atalhos quanto pra comparar o que foi salvo no banco com o
/// que chega num KeyEvent de verdade.
class KeyBinding {
  final LogicalKeyboardKey key;
  final bool ctrl;
  final bool shift;
  final bool alt;

  const KeyBinding(this.key, {this.ctrl = false, this.shift = false, this.alt = false});

  /// Teclas puramente modificadoras nunca viram "a" tecla de um atalho —
  /// só entram como `ctrl`/`shift`/`alt` quando seguradas junto de outra.
  ///
  /// Não pode ser `const`: `LogicalKeyboardKey` sobrescreve `==`/`hashCode`
  /// (pra comparar por `keyId`, não por identidade), e o analisador do
  /// Dart proíbe exatamente esse tipo de elemento numa coleção *const*
  /// (só aceita tipos com igualdade "primitiva" ali, já que a dedupe do
  /// literal const precisa acontecer em tempo de compilação). Um `Set`
  /// comum (`static final`), construído em tempo de execução, não tem
  /// essa restrição — funciona exatamente igual, só não é uma constante
  /// de compilação.
  static final Set<LogicalKeyboardKey> _modifierKeys = {
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.fn,
  };

  static bool isModifierOnly(LogicalKeyboardKey key) => _modifierKeys.contains(key);

  /// Monta uma combinação a partir de um evento de tecla real, lendo o
  /// estado atual dos modificadores em [HardwareKeyboard]. Não deve ser
  /// chamado com a tecla do próprio modificador (ver [isModifierOnly]).
  factory KeyBinding.fromEvent(KeyEvent event) {
    return KeyBinding(
      event.logicalKey,
      ctrl: HardwareKeyboard.instance.isControlPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
      alt: HardwareKeyboard.instance.isAltPressed,
    );
  }

  bool matchesEvent(KeyEvent event) {
    return event.logicalKey == key &&
        HardwareKeyboard.instance.isControlPressed == ctrl &&
        HardwareKeyboard.instance.isShiftPressed == shift &&
        HardwareKeyboard.instance.isAltPressed == alt;
  }

  /// Rótulo curto pra UI, ex.: "Ctrl + →".
  String get label {
    final parts = <String>[
      if (ctrl) 'Ctrl',
      if (shift) 'Shift',
      if (alt) 'Alt',
      _keyLabel(key),
    ];
    return parts.join(' + ');
  }

  static String _keyLabel(LogicalKeyboardKey key) {
    if (_namedKeyLabels.containsKey(key)) return _namedKeyLabels[key]!;

    // Teclas de função (F1-F24): já têm um nome de debug legível e
    // estável em qualquer modo de build (ao contrário de `debugName`,
    // que é removido em release), então dá pra confiar nele aqui.
    final label = key.keyLabel;
    if (label.isNotEmpty) return label.toUpperCase();

    return 'Tecla ${key.keyId}';
  }

  // Mesmo motivo do comentário em `_modifierKeys` acima: não pode ser
  // `const` porque `LogicalKeyboardKey` sobrescreve `==`/`hashCode`.
  static final Map<LogicalKeyboardKey, String> _namedKeyLabels = {
    LogicalKeyboardKey.space: 'Espaço',
    LogicalKeyboardKey.arrowLeft: '←',
    LogicalKeyboardKey.arrowRight: '→',
    LogicalKeyboardKey.arrowUp: '↑',
    LogicalKeyboardKey.arrowDown: '↓',
    LogicalKeyboardKey.enter: 'Enter',
    LogicalKeyboardKey.numpadEnter: 'Enter',
    LogicalKeyboardKey.escape: 'Esc',
    LogicalKeyboardKey.tab: 'Tab',
    LogicalKeyboardKey.backspace: 'Backspace',
    LogicalKeyboardKey.delete: 'Delete',
    LogicalKeyboardKey.home: 'Home',
    LogicalKeyboardKey.end: 'End',
    LogicalKeyboardKey.pageUp: 'Page Up',
    LogicalKeyboardKey.pageDown: 'Page Down',
    LogicalKeyboardKey.comma: ',',
    LogicalKeyboardKey.period: '.',
    LogicalKeyboardKey.minus: '-',
    LogicalKeyboardKey.equal: '=',
    LogicalKeyboardKey.semicolon: ';',
    LogicalKeyboardKey.slash: '/',
  };

  /// Serialização compacta pra guardar em texto: "ctrl,shift,alt,keyId".
  String toStorageString() => '${ctrl ? 1 : 0},${shift ? 1 : 0},${alt ? 1 : 0},${key.keyId}';

  static KeyBinding? fromStorageString(String raw) {
    final parts = raw.split(',');
    if (parts.length != 4) return null;
    final keyId = int.tryParse(parts[3]);
    if (keyId == null) return null;
    final key = LogicalKeyboardKey.findKeyByKeyId(keyId) ?? LogicalKeyboardKey(keyId);
    return KeyBinding(
      key,
      ctrl: parts[0] == '1',
      shift: parts[1] == '1',
      alt: parts[2] == '1',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is KeyBinding &&
      other.key == key &&
      other.ctrl == ctrl &&
      other.shift == shift &&
      other.alt == alt;

  @override
  int get hashCode => Object.hash(key, ctrl, shift, alt);
}
