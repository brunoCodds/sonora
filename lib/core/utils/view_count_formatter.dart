/// Formata uma contagem de visualizações em português, de forma compacta:
/// `532` → "532 visualizações", `1500` → "1,5 mil visualizações",
/// `1200000` → "1,2 mi de visualizações".
class ViewCountFormatter {
  ViewCountFormatter._();

  static String format(int views) {
    if (views == 1) return '1 visualização';
    if (views < 1000) return '$views visualizações';

    if (views < 1000000) {
      final thousands = views / 1000;
      // 999.600 arredondaria para "1000 mil": nesse ponto já é "1 mi".
      if (thousands < 999.5) return '${_compact(thousands)} mil visualizações';
      return '1 mi de visualizações';
    }

    if (views < 1000000000) {
      final millions = views / 1000000;
      if (millions < 999.5) return '${_compact(millions)} mi de visualizações';
      return '1 bi de visualizações';
    }

    return '${_compact(views / 1000000000)} bi de visualizações';
  }

  /// Uma casa decimal (vírgula) abaixo de 100, nenhuma a partir daí; some
  /// o ",0" quando o valor é redondo.
  static String _compact(double value) {
    final fixed =
        value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    final trimmed =
        fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
    return trimmed.replaceAll('.', ',');
  }
}
