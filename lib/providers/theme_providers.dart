import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_palette.dart';
import '../data/repositories/settings_repository.dart';
import 'repository_providers.dart';

/// Guarda a paleta de cores ativa e a persiste no [SettingsRepository].
///
/// A paleta é lida UMA vez na criação (síncrono — o banco já está aberto
/// desde o `main()`), então o primeiro frame do app já sai com o tema
/// certo, sem "piscar" na paleta padrão.
class PaletteNotifier extends StateNotifier<AppPalette> {
  final SettingsRepository _settings;

  PaletteNotifier(this._settings)
      : super(AppPalettes.byId(_settings.getString(AppConstants.keyThemePalette)));

  void select(AppPalette palette) {
    if (palette.id == state.id) return;
    state = palette;
    _settings.setString(AppConstants.keyThemePalette, palette.id);
  }
}

/// Paleta ativa. Quem monta o `ThemeData` (ver `SonoraApp`) observa este
/// provider; o resto do app lê as cores pelo tema, com `context.palette`.
final currentPaletteProvider =
    StateNotifierProvider<PaletteNotifier, AppPalette>((ref) {
  return PaletteNotifier(ref.watch(settingsRepositoryProvider));
});
