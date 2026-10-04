import 'dart:math';

class ShuffleUtils {
  ShuffleUtils._();

  static final Random _random = Random();

  /// Embaralha [items] usando Fisher-Yates (distribuição uniforme,
  /// sem repetições ou padrões previsíveis).
  ///
  /// Se [keepFirst] for informado, o item é fixado na primeira posição
  /// (útil para manter a música atual tocando no topo da fila embaralhada).
  static List<T> shuffle<T>(List<T> items, {T? keepFirst}) {
    final list = List<T>.from(items);

    if (keepFirst != null) {
      list.remove(keepFirst);
    }

    for (var i = list.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }

    if (keepFirst != null) {
      list.insert(0, keepFirst);
    }

    return list;
  }
}
