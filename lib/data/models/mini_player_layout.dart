import 'dart:ui' show Size;

/// Designs disponíveis para o painel do modo bandeira (o painel reduzido
/// que aparece ao clicar no ícone da Sonora na bandeja do sistema — ver
/// `MiniPlayerScreen`).
///
/// Cada design tem o TAMANHO de janela que combina com o que ele é
/// ([windowSize]): um painel quadrado de capa, um cartão de vidro baixinho,
/// etc. O `TrayModeController` usa esse tamanho ao abrir o painel. Quem
/// continua só desenhando conteúdo é o `MiniPlayerScreen`; o tamanho e o
/// gerenciamento da janela são do controlador.
enum MiniPlayerLayout {
  /// O design original: capa grande, controles e, trocando de tela, a fila.
  classico(
    label: 'Clássico',
    description: 'Capa grande no centro. A fila abre numa segunda tela.',
    windowSize: Size(320, 480),
  ),

  /// Mais compacto: capa pequena ao lado do título, controles logo abaixo
  /// e a fila sempre visível embaixo.
  compacto(
    label: 'Compacto',
    description: 'Capa pequena ao lado do título e a fila sempre visível.',
    windowSize: Size(320, 480),
  ),

  /// Só o essencial: capa redonda, progresso, título, os três controles
  /// principais e o volume. Sem fila, sem favoritar.
  limpo(
    label: 'Limpo',
    description: 'Capa redonda, progresso, controles e volume. Mais baixo, sem fila.',
    windowSize: Size(320, 420),
    positionKeySuffix: '_limpo',
  ),

  /// Painel QUADRADO: a capa ocupa tudo, com os controles por cima — no
  /// estilo do mini player do Spotify.
  capaCheia(
    label: 'Capa cheia',
    description: 'Painel quadrado: a capa preenche tudo e os controles ficam por cima.',
    windowSize: Size(320, 320),
    positionKeySuffix: '_capa_cheia',
  ),

  /// Cartão pequeno de VIDRO: a janela fica translúcida e borra o que está
  /// atrás dela (acrylic do Windows). Miniatura da capa, progresso,
  /// controles e volume.
  discreto(
    label: 'Discreto',
    description: 'Cartão pequeno de vidro: mostra, desfocado, o que está atrás dele.',
    windowSize: Size(360, 172),
    positionKeySuffix: '_discreto',
    usesGlass: true,
  );

  final String label;
  final String description;

  /// Tamanho (lógico) da janela quando este design está aberto.
  final Size windowSize;

  /// Sufixo das chaves de posição salva do painel. Cada design lembra a
  /// SUA posição: eles têm tamanhos diferentes, e uma posição escolhida
  /// pra um painel de 320x480 deixaria um cartão de 360x172 mal ancorado.
  /// Vazio nos dois primeiros de propósito: são os designs que já
  /// existiam, e assim a posição que o usuário já salvou continua valendo.
  final String positionKeySuffix;

  /// Se a janela usa o efeito de vidro (acrylic) enquanto este design está
  /// aberto (ver `WindowGlass`).
  final bool usesGlass;

  const MiniPlayerLayout({
    required this.label,
    required this.description,
    required this.windowSize,
    this.positionKeySuffix = '',
    this.usesGlass = false,
  });

  /// Nome ausente ou desconhecido (ex.: um design removido numa versão
  /// futura) cai no clássico — o que o app sempre teve.
  static MiniPlayerLayout fromName(String? name) {
    return MiniPlayerLayout.values.firstWhere(
      (layout) => layout.name == name,
      orElse: () => MiniPlayerLayout.classico,
    );
  }
}
