/// Modos de repetição da fila de reprodução.
enum RepeatMode {
  /// Reprodução normal: para ao final da fila.
  off,

  /// Repete a fila inteira ao chegar ao final.
  all,

  /// Repete apenas a música atual indefinidamente.
  one;

  static RepeatMode fromName(String? name) {
    return RepeatMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => RepeatMode.off,
    );
  }
}
