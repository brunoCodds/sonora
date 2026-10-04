import 'package:flutter/material.dart';

/// Conjunto de cores de um tema da Sonora.
///
/// Substitui a antiga classe `AppColors` (constantes fixas, resolvidas em
/// tempo de compilação): como as cores agora podem mudar com a escolha do
/// usuário (tela de Perfil), elas precisam ser lidas em tempo de execução,
/// a partir do tema atual — por isso esta classe é uma [ThemeExtension], que
/// viaja dentro do próprio `ThemeData` (ver `AppTheme.fromPalette`).
///
/// Como ler: `context.palette.accent` (extensão em [AppPaletteContext]).
/// Quem lê desse jeito reconstrói sozinho quando o tema muda — sem
/// `ref.watch` extra e sem nenhum cuidado especial.
///
/// Consequência importante: como o valor não é mais uma constante, um
/// widget que use `context.palette.x` não pode ser criado com `const`.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  /// Identificador estável, gravado nas preferências ([AppPalettes.byId]).
  final String id;

  /// Nome mostrado ao usuário na tela de Perfil.
  final String name;

  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color surfaceHighlight;

  final Color accent;
  final Color accentVariant;

  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;

  final Color divider;
  final Color error;
  final Color favorite;

  /// Gradiente do placeholder de capa (quando a música não tem imagem).
  /// Precisa ser de tom médio/escuro: o ícone por cima é branco.
  final List<Color> coverGradient;

  /// Tema claro ou escuro. Define a base do `ThemeData` (ver
  /// `AppTheme.fromPalette`) — widgets do Material que não leem a paleta
  /// diretamente (campo de texto, menus, diálogos) herdam daí.
  final Brightness brightness;

  /// Cor do texto/ícone desenhado SOBRE o [accent] (botões preenchidos,
  /// chip selecionado, ícone do logo). `null` = o padrão de antes das
  /// paletas novas: branco nos rótulos próprios do app, e o que o Material
  /// escolher nos botões. Só as paletas cujo destaque é claro demais pra
  /// texto branco (verde, rosa) definem.
  final Color? onAccent;

  /// [onAccent], ou branco quando a paleta não define.
  Color get labelOnAccent => onAccent ?? Colors.white;

  bool get isDark => brightness == Brightness.dark;

  const AppPalette({
    required this.id,
    required this.name,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.surfaceHighlight,
    required this.accent,
    required this.accentVariant,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.divider,
    required this.error,
    required this.favorite,
    required this.coverGradient,
    this.brightness = Brightness.dark,
    this.onAccent,
  });

  @override
  AppPalette copyWith({
    String? id,
    String? name,
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? surfaceHighlight,
    Color? accent,
    Color? accentVariant,
    Color? textPrimary,
    Color? textSecondary,
    Color? textDisabled,
    Color? divider,
    Color? error,
    Color? favorite,
    List<Color>? coverGradient,
    Brightness? brightness,
    Color? onAccent,
  }) {
    return AppPalette(
      id: id ?? this.id,
      name: name ?? this.name,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      surfaceHighlight: surfaceHighlight ?? this.surfaceHighlight,
      accent: accent ?? this.accent,
      accentVariant: accentVariant ?? this.accentVariant,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textDisabled: textDisabled ?? this.textDisabled,
      divider: divider ?? this.divider,
      error: error ?? this.error,
      favorite: favorite ?? this.favorite,
      coverGradient: coverGradient ?? this.coverGradient,
      brightness: brightness ?? this.brightness,
      onAccent: onAccent ?? this.onAccent,
    );
  }

  /// Interpola entre duas paletas — é o que faz a troca de tema "deslizar"
  /// suavemente de uma cor pra outra (o `MaterialApp` anima o `ThemeData`
  /// inteiro, incluindo as extensões, ao receber um tema novo).
  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    final first = t < 0.5;
    return AppPalette(
      id: first ? id : other.id,
      name: first ? name : other.name,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      surfaceHighlight: Color.lerp(surfaceHighlight, other.surfaceHighlight, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentVariant: Color.lerp(accentVariant, other.accentVariant, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      error: Color.lerp(error, other.error, t)!,
      favorite: Color.lerp(favorite, other.favorite, t)!,
      coverGradient: _lerpColors(coverGradient, other.coverGradient, t),
      brightness: first ? brightness : other.brightness,
      onAccent: (onAccent == null && other.onAccent == null)
          ? null
          : Color.lerp(labelOnAccent, other.labelOnAccent, t),
    );
  }

  static List<Color> _lerpColors(List<Color> a, List<Color> b, double t) {
    if (a.length != b.length) return t < 0.5 ? a : b;
    return [for (var i = 0; i < a.length; i++) Color.lerp(a[i], b[i], t)!];
  }
}

/// Atalho `context.palette` para ler a paleta do tema atual.
extension AppPaletteContext on BuildContext {
  /// Se, por algum motivo, o tema não tiver a extensão (ex.: um widget
  /// testado isoladamente com o `ThemeData` padrão do Flutter), cai na
  /// paleta padrão em vez de quebrar.
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalettes.defaultPalette;
}

/// Paletas prontas. Cada uma é uma constante canônica — comparar por
/// identidade/`id` funciona, e o `Riverpod` só notifica quando a escolha
/// de fato muda.
class AppPalettes {
  AppPalettes._();

  /// A paleta original da Sonora: roxo/violeta sobre fundo escuro. Os
  /// valores aqui são os mesmos da antiga `AppColors` — trocar `AppColors`
  /// por `AppPalette` não pode mudar nada visualmente.
  static const AppPalette violeta = AppPalette(
    id: 'violeta',
    name: 'Violeta',
    background: Color(0xFF0F0B14),
    surface: Color(0xFF181420),
    surfaceVariant: Color(0xFF221C2C),
    surfaceHighlight: Color(0xFF2C2438),
    accent: Color(0xFF8B5CF6),
    accentVariant: Color(0xFFB794F6),
    textPrimary: Color(0xFFF5F3F7),
    textSecondary: Color(0xFFA8A0B4),
    textDisabled: Color(0xFF615A6E),
    divider: Color(0xFF2A2433),
    error: Color(0xFFE5484D),
    favorite: Color(0xFFE23F6B),
    coverGradient: [
      Color(0xFF3A2E52),
      Color(0xFF1E1730),
    ],
  );

  /// Segunda paleta (só pra provar a troca de ponta a ponta): azul
  /// profundo. O destaque ([accent]) é escuro o bastante pra manter o
  /// texto branco legível em cima dele (ex.: chip selecionado).
  static const AppPalette oceano = AppPalette(
    id: 'oceano',
    name: 'Oceano',
    background: Color(0xFF080F16),
    surface: Color(0xFF0F1923),
    surfaceVariant: Color(0xFF172531),
    surfaceHighlight: Color(0xFF21323F),
    accent: Color(0xFF2F7DE1),
    accentVariant: Color(0xFF7DB8F5),
    textPrimary: Color(0xFFF1F6F9),
    textSecondary: Color(0xFF9DB0BD),
    textDisabled: Color(0xFF576977),
    divider: Color(0xFF1E2C37),
    error: Color(0xFFE5484D),
    favorite: Color(0xFFFF5C8A),
    coverGradient: [
      Color(0xFF1E3A4F),
      Color(0xFF0F1D2B),
    ],
  );

  /// Rosé — escuro, inspirada no "Figma Music Player": fundo de ameixa
  /// quase preto e um rosa-antigo suave como destaque.
  static const AppPalette rose = AppPalette(
    id: 'rose',
    name: 'Rosé',
    background: Color(0xFF151116),
    surface: Color(0xFF1E181F),
    surfaceVariant: Color(0xFF2A222B),
    surfaceHighlight: Color(0xFF372C38),
    accent: Color(0xFFD4868F),
    accentVariant: Color(0xFFF2B1B8),
    textPrimary: Color(0xFFF4EFF1),
    textSecondary: Color(0xFFAA9EA7),
    textDisabled: Color(0xFF6B5F69),
    divider: Color(0xFF2B232C),
    error: Color(0xFFE5484D),
    favorite: Color(0xFFFF6B7A),
    coverGradient: [
      Color(0xFF4A3140),
      Color(0xFF2A1D2B),
    ],
    onAccent: Color(0xFF2A1118),
  );

  /// Esmeralda — escuro, inspirada no Spotify (iPad): cinza quase preto,
  /// barra lateral preta e o verde clássico como destaque.
  static const AppPalette esmeralda = AppPalette(
    id: 'esmeralda',
    name: 'Esmeralda',
    background: Color(0xFF121212),
    surface: Color(0xFF000000),
    surfaceVariant: Color(0xFF242424),
    surfaceHighlight: Color(0xFF2F2F2F),
    accent: Color(0xFF1DB954),
    accentVariant: Color(0xFF1ED760),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB3B3B3),
    textDisabled: Color(0xFF6A6A6A),
    divider: Color(0xFF282828),
    error: Color(0xFFE22134),
    favorite: Color(0xFF1ED760),
    coverGradient: [
      Color(0xFF3A3A3A),
      Color(0xFF1A1A1A),
    ],
    onAccent: Color(0xFF000000),
  );

  /// Neon — escuro, inspirada no "Music Streaming Desktop App": preto
  /// puro, destaque azul-violeta e verde-menta nos detalhes.
  static const AppPalette neon = AppPalette(
    id: 'neon',
    name: 'Neon',
    background: Color(0xFF050507),
    surface: Color(0xFF0E0E12),
    surfaceVariant: Color(0xFF17171D),
    surfaceHighlight: Color(0xFF24242C),
    accent: Color(0xFF7B76FF),
    accentVariant: Color(0xFF3DE8A8),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF9E9EAB),
    textDisabled: Color(0xFF5A5A66),
    divider: Color(0xFF1C1C22),
    error: Color(0xFFFF5C6C),
    favorite: Color(0xFFFF6B4A),
    coverGradient: [
      Color(0xFF2B2A6B),
      Color(0xFF0F0F2A),
    ],
    onAccent: Color(0xFF0A0A1F),
  );

  /// Alvorada — CLARA, inspirada no redesenho do SoundCloud: fundo
  /// branco-rosado, cartões brancos e laranja vibrante como destaque.
  /// [accentVariant] (usado em texto, como o título da música atual) é um
  /// laranja mais fechado, pra manter o contraste sobre fundo claro.
  static const AppPalette alvorada = AppPalette(
    id: 'alvorada',
    name: 'Alvorada',
    background: Color(0xFFF7F3F7),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFF1ECF2),
    surfaceHighlight: Color(0xFFE8E2EC),
    accent: Color(0xFFF05A00),
    accentVariant: Color(0xFFB53500),
    textPrimary: Color(0xFF1B1A1F),
    textSecondary: Color(0xFF625E6C),
    textDisabled: Color(0xFFB1ADB9),
    divider: Color(0xFFECE6EE),
    error: Color(0xFFD93036),
    favorite: Color(0xFFE5384F),
    coverGradient: [
      Color(0xFFFFA970),
      Color(0xFFF0662A),
    ],
    brightness: Brightness.light,
  );

  /// Lavanda — CLARA, inspirada no "Music Player Desktop": conteúdo
  /// branco, tons de lavanda nas superfícies, destaque azul-violeta e
  /// rosa-vivo no item que está tocando.
  static const AppPalette lavanda = AppPalette(
    id: 'lavanda',
    name: 'Lavanda',
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF3F2FA),
    surfaceVariant: Color(0xFFECEAF7),
    surfaceHighlight: Color(0xFFE1DFF3),
    accent: Color(0xFF5B5BEA),
    accentVariant: Color(0xFFC2134A),
    textPrimary: Color(0xFF1C1B2E),
    textSecondary: Color(0xFF5E5D77),
    textDisabled: Color(0xFFB4B3C6),
    divider: Color(0xFFE7E5F2),
    error: Color(0xFFD93036),
    favorite: Color(0xFFE0245E),
    coverGradient: [
      Color(0xFF8F8DF0),
      Color(0xFF5B5BEA),
    ],
    brightness: Brightness.light,
  );

  static const AppPalette defaultPalette = violeta;

  /// Todas as paletas, na ordem em que aparecem na tela de Perfil.
  static const List<AppPalette> all = [
    violeta,
    oceano,
    rose,
    esmeralda,
    neon,
    alvorada,
    lavanda,
  ];

  /// Procura uma paleta pelo [AppPalette.id] gravado. Id ausente ou
  /// desconhecido (ex.: uma paleta removida numa versão futura) cai na
  /// padrão.
  static AppPalette byId(String? id) {
    for (final palette in all) {
      if (palette.id == id) return palette;
    }
    return defaultPalette;
  }
}
