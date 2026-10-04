import 'package:flutter/material.dart';

import 'app_palette.dart';

class AppTheme {
  AppTheme._();

  /// Monta o `ThemeData` do app a partir de uma paleta. É a única porta de
  /// entrada do tema: o `SonoraApp` chama isto com a paleta escolhida
  /// (`currentPaletteProvider`) e o resto do app lê as cores pelo próprio
  /// tema (`context.palette`, ver `AppPalette`).
  ///
  /// Tudo que a antiga `AppTheme.dark` configurava continua igual — só
  /// que agora vindo de [palette] em vez de constantes fixas. A paleta
  /// também viaja dentro do tema (`extensions`), que é o que permite o
  /// `context.palette`.
  static ThemeData fromPalette(AppPalette palette) {
    // A base (claro/escuro) vem da paleta. Pras escuras é exatamente o que
    // sempre foi (`ThemeData.dark`).
    final base = palette.isDark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

    final colorScheme = base.colorScheme.copyWith(
      brightness: palette.brightness,
      // Só sobrescreve quando a paleta define (ver AppPalette.onAccent).
      onPrimary: palette.onAccent,
      primary: palette.accent,
      secondary: palette.accentVariant,
      surface: palette.surface,
      error: palette.error,
    );

    return base.copyWith(
      scaffoldBackgroundColor: palette.background,
      colorScheme: colorScheme,
      canvasColor: palette.background,
      dividerColor: palette.divider,
      splashFactory: InkRipple.splashFactory,
      extensions: <ThemeExtension<dynamic>>[palette],
      textTheme: base.textTheme
          .apply(
            bodyColor: palette.textPrimary,
            displayColor: palette.textPrimary,
          )
          .copyWith(
            titleLarge: TextStyle(
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
            titleMedium: TextStyle(
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
            bodySmall: TextStyle(color: palette.textSecondary),
          ),
      iconTheme: IconThemeData(color: palette.textPrimary),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: palette.accent,
        inactiveTrackColor: palette.surfaceHighlight,
        thumbColor: palette.textPrimary,
        overlayColor: palette.accent.withValues(alpha: 0.2),
        trackHeight: 3,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(palette.surfaceHighlight),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.surfaceHighlight,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(color: palette.textPrimary, fontSize: 12),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceVariant,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        hintStyle: TextStyle(color: palette.textSecondary),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.textSecondary,
        textColor: palette.textPrimary,
      ),
    );
  }
}
