import 'package:flutter/material.dart';

/// Paleta de cores da Sonora.
///
/// Inspirada na experiência de players modernos (fundo escuro, alto
/// contraste, um destaque de cor vibrante), mas com identidade própria:
/// tons de roxo/violeta em vez do verde característico de outros apps.
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0F0B14);
  static const Color surface = Color(0xFF181420);
  static const Color surfaceVariant = Color(0xFF221C2C);
  static const Color surfaceHighlight = Color(0xFF2C2438);

  static const Color accent = Color(0xFF8B5CF6);
  static const Color accentVariant = Color(0xFFB794F6);

  static const Color textPrimary = Color(0xFFF5F3F7);
  static const Color textSecondary = Color(0xFFA8A0B4);
  static const Color textDisabled = Color(0xFF615A6E);

  static const Color divider = Color(0xFF2A2433);
  static const Color error = Color(0xFFE5484D);
  static const Color favorite = Color(0xFFE23F6B);

  static const List<Color> defaultCoverGradient = [
    Color(0xFF3A2E52),
    Color(0xFF1E1730),
  ];
}
