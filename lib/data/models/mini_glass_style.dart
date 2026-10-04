/// Fundo do painel "Discreto" do modo bandeira (ver `MiniPlayerLayout.discreto`).
///
/// Existem três estilos porque o efeito de vidro do Windows depende da
/// versão do Windows, da placa de vídeo e do motor do Flutter — e o jeito
/// seguro de acertar é deixar o usuário escolher o que funciona na máquina
/// dele (tela de Perfil).
enum MiniGlassStyle {
  /// Translúcido E desfocado: o que está atrás da janela aparece borrado,
  /// como o "vidro" do Windows. No Windows 10 usa o desfoque simples (o
  /// acrylic trava o arrasto da janela lá); no Windows 11, o acrylic.
  desfocado(
    label: 'Vidro',
    description: 'Translúcido e desfocado, como o vidro do Windows.',
  ),

  /// Translúcido, mas sem desfoque. Mais leve, e é o que depende de menos
  /// coisas do sistema.
  transparente(
    label: 'Transparente',
    description: 'Translúcido, sem desfoque. Mais leve.',
  ),

  /// Fundo opaco, sem transparência nenhuma.
  solido(
    label: 'Sólido',
    description: 'Fundo opaco, sem transparência.',
  );

  final String label;
  final String description;

  const MiniGlassStyle({required this.label, required this.description});

  /// Nome ausente ou desconhecido cai no vidro desfocado (o padrão).
  static MiniGlassStyle fromName(String? name) {
    return MiniGlassStyle.values.firstWhere(
      (style) => style.name == name,
      orElse: () => MiniGlassStyle.desfocado,
    );
  }
}
