import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../data/models/mini_glass_style.dart';
import '../data/models/mini_player_layout.dart';
import '../data/repositories/settings_repository.dart';
import 'repository_providers.dart';

/// Design escolhido para o painel do modo bandeira (ver
/// [MiniPlayerLayout]). Quem escolhe é a tela de Perfil; quem lê é o
/// `MiniPlayerScreen`.
class MiniPlayerLayoutNotifier extends StateNotifier<MiniPlayerLayout> {
  final SettingsRepository _settings;

  MiniPlayerLayoutNotifier(this._settings)
      : super(MiniPlayerLayout.fromName(
          _settings.getString(AppConstants.keyMiniPlayerLayout),
        ));

  void select(MiniPlayerLayout layout) {
    if (layout == state) return;
    state = layout;
    _settings.setString(AppConstants.keyMiniPlayerLayout, layout.name);
  }
}

final miniPlayerLayoutProvider =
    StateNotifierProvider<MiniPlayerLayoutNotifier, MiniPlayerLayout>((ref) {
  return MiniPlayerLayoutNotifier(ref.watch(settingsRepositoryProvider));
});

/// Fundo escolhido para o painel Discreto (ver [MiniGlassStyle]). Quem
/// escolhe é a tela de Perfil; quem usa é o `TrayModeController`, ao abrir
/// o painel.
class MiniGlassStyleNotifier extends StateNotifier<MiniGlassStyle> {
  final SettingsRepository _settings;

  MiniGlassStyleNotifier(this._settings)
      : super(MiniGlassStyle.fromName(
          _settings.getString(AppConstants.keyMiniGlassStyle),
        ));

  void select(MiniGlassStyle style) {
    if (style == state) return;
    state = style;
    _settings.setString(AppConstants.keyMiniGlassStyle, style.name);
  }
}

final miniGlassStyleProvider =
    StateNotifierProvider<MiniGlassStyleNotifier, MiniGlassStyle>((ref) {
  return MiniGlassStyleNotifier(ref.watch(settingsRepositoryProvider));
});

/// Limites e padrão da opacidade do fundo do painel Discreto. Quanto MENOR,
/// mais transparente (e mais difícil de ler o texto sobre um fundo claro ou
/// agitado); quanto maior, mais sólido.
const double kMiniGlassOpacityMin = 0.05;
const double kMiniGlassOpacityMax = 0.90;
const double kMiniGlassOpacityDefault = 0.20;

/// Opacidade da tinta do tema que o painel Discreto desenha POR CIMA da
/// transparência da janela. Quem escolhe é a tela de Perfil (controle
/// deslizante); vale na próxima vez que o painel abrir.
class MiniGlassOpacityNotifier extends StateNotifier<double> {
  final SettingsRepository _settings;

  MiniGlassOpacityNotifier(this._settings)
      : super(
          _settings
              .getDouble(AppConstants.keyMiniGlassOpacity, fallback: kMiniGlassOpacityDefault)
              .clamp(kMiniGlassOpacityMin, kMiniGlassOpacityMax)
              .toDouble(),
        );

  void set(double value) {
    final clamped = value.clamp(kMiniGlassOpacityMin, kMiniGlassOpacityMax).toDouble();
    if (clamped == state) return;
    state = clamped;
    _settings.setDouble(AppConstants.keyMiniGlassOpacity, clamped);
  }
}

final miniGlassOpacityProvider =
    StateNotifierProvider<MiniGlassOpacityNotifier, double>((ref) {
  return MiniGlassOpacityNotifier(ref.watch(settingsRepositoryProvider));
});

/// `true` enquanto a janela está realmente translúcida (estilo Vidro ou
/// Transparente aplicado com sucesso). Quem liga/desliga é o
/// `TrayModeController` (e, por instantes, o arrasto da janela); o
/// `MiniPlayerScreen` só lê: com `true` deixa o fundo transparente (pra a
/// janela aparecer atrás), com `false` usa um fundo sólido — que é também o
/// que aparece no estilo Sólido ou se o efeito não pôde ser aplicado.
final miniGlassActiveProvider = StateProvider<bool>((ref) => false);
