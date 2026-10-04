import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color, Colors;
import 'package:flutter_acrylic/flutter_acrylic.dart' show Window, WindowEffect;
import 'package:window_manager/window_manager.dart' show windowManager;

import '../../data/models/mini_glass_style.dart';
import '../theme/app_palette.dart';

/// Transparência da janela do painel "Discreto" (ver `MiniGlassStyle`).
///
/// É TODO o contato do app com o plugin `flutter_acrylic` (e o único lugar
/// que mexe no fundo da janela além do `main()`): se um dia ele for trocado
/// ou removido, é aqui. Nada aqui lança exceção pra fora — qualquer falha
/// só devolve "sem efeito" e o chamador usa um fundo sólido. Tudo o que
/// acontece é registrado com o prefixo `[WindowGlass]` (aparece no console
/// do `flutter run`), pra dar pra entender o que o Windows fez.
///
/// Por que o efeito depende da versão do Windows (conferido na documentação
/// e no código-fonte do plugin):
/// * Windows 10: o `acrylic` TRAVA o arrasto da janela (lag enorme, com
///   cursor "fantasma") — é um problema conhecido, só corrigido no Windows
///   11. Por isso lá o "vidro" usa o `aero` (desfoque simples), que não tem
///   esse problema, e o desfoque é pausado enquanto a janela é arrastada.
/// * Windows 11: o `acrylic` funciona bem. A partir da compilação 22523
///   (22H2) ele é o "backdrop acrylic" do sistema, que IGNORA a cor passada;
///   por isso a tinta que garante a leitura do texto é desenhada pelo
///   Flutter por cima (ver `miniGlassOpacityProvider`, ajustável no Perfil),
///   igual nas duas versões.
/// * ARRASTO: a janela translúcida fica MUITO lenta de arrastar em alguns
///   Windows (atraso grande, com um cursor "fantasma"), tanto com acrylic
///   quanto com desfoque simples, inclusive no Windows 11 recente. Por isso,
///   enquanto o usuário arrasta o painel, o efeito é desligado e o painel
///   fica sólido (como os outros designs, que arrastam bem) — ver
///   [solidWhileDragging] — e tudo volta ao soltar.
/// * Mudar o estilo da barra de título (`windowManager.setTitleBarStyle`)
///   zera a configuração de moldura que o efeito usa. Por isso o
///   `TrayModeController` aplica o efeito DEPOIS de definir o estilo, e o
///   remove ANTES de voltar pra janela cheia.
class WindowGlass {
  WindowGlass._();

  /// Se `true`, o painel vira sólido e sem efeito enquanto a janela é arrastada,
  /// e volta ao soltar (ver o comentário da classe, em "ARRASTO"). Ponha
  /// `false` pra manter a transparência durante o arrasto (mais bonito, mas
  /// pode ficar lento).
  static const bool solidWhileDragging = true;

  static bool _ready = false;
  static bool _pluginEffectOn = false;
  static bool _suspended = false;
  static WindowEffect? _effect;
  static Color _effectColor = Colors.transparent;
  static bool _effectDark = true;
  static int? _build;

  /// Número da compilação do Windows (ex.: 19045 = Windows 10 22H2; 22631 =
  /// Windows 11 23H2). 0 se não deu pra descobrir.
  static int get windowsBuild => _build ??= _readBuild();

  static int _readBuild() {
    final match = RegExp(r'Build (\d+)').firstMatch(Platform.operatingSystemVersion);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  static void _log(String message) => debugPrint('[WindowGlass] $message');

  /// Chamar uma vez, no `main()`, antes de `runApp`. Sem isso o plugin nunca
  /// responde (o `setEffect` espera esta inicialização terminar).
  static Future<void> init() async {
    if (!Platform.isWindows) return;
    try {
      await Window.initialize();
      _ready = true;
      _log('plugin inicializado — ${Platform.operatingSystemVersion}');
    } catch (e) {
      _log('o plugin NÃO inicializou ($e): o estilo "Vidro" ficará indisponível');
    }
  }

  /// Aplica o estilo de fundo pedido. Devolve `true` se a janela ficou
  /// translúcida (estilo Vidro ou Transparente, com sucesso), `false` se não
  /// há transparência (estilo Sólido, ou o efeito falhou).
  static Future<bool> apply(AppPalette palette, MiniGlassStyle style) async {
    switch (style) {
      case MiniGlassStyle.solido:
        await clear();
        _log('estilo Sólido: sem transparência');
        return false;
      case MiniGlassStyle.transparente:
        await clear();
        try {
          // Mesmo estado em que o app já inicia (ver `main()`): transparência
          // simples do próprio window_manager, sem depender do plugin.
          await windowManager.setBackgroundColor(Colors.transparent);
          _log('estilo Transparente (window_manager)');
          return true;
        } catch (e) {
          _log('falha ao deixar a janela transparente: $e');
          return false;
        }
      case MiniGlassStyle.desfocado:
        return _applyBlur(palette);
    }
  }

  static Future<bool> _applyBlur(AppPalette palette) async {
    if (!_ready) {
      _log('estilo Vidro indisponível: o plugin não inicializou');
      return false;
    }
    final build = windowsBuild;
    final isWindows11 = build >= 22000;
    final effect = isWindows11 ? WindowEffect.acrylic : WindowEffect.aero;
    final color = palette.background.withValues(alpha: isWindows11 ? 0.35 : 0.2);
    try {
      await Window.setEffect(effect: effect, color: color, dark: palette.isDark)
          .timeout(const Duration(seconds: 2));
      _pluginEffectOn = true;
      _suspended = false;
      _effect = effect;
      _effectColor = color;
      _effectDark = palette.isDark;
      _log('Vidro aplicado: ${effect.name} (Windows build $build)');
      return true;
    } catch (e) {
      // Não insiste nas próximas aberturas: cada tentativa que falha custaria
      // até 2s de espera antes de o painel aparecer.
      _ready = false;
      _log('falha ao aplicar ${effect.name}: $e');
      return false;
    }
  }

  /// Desfaz o efeito do plugin (se havia) e devolve a janela ao estado em que
  /// o app inicia. Não faz nada se nenhum efeito do plugin estava ligado.
  static Future<void> clear() async {
    if (!_pluginEffectOn) return;
    _pluginEffectOn = false;
    _suspended = false;
    try {
      await Window.setEffect(effect: WindowEffect.disabled).timeout(const Duration(seconds: 2));
      // O plugin deixa a janela sem nenhum "accent"; o app inicia com o fundo
      // transparente do window_manager (ver `main()`), então restaura isso.
      await windowManager.setBackgroundColor(Colors.transparent);
      _log('efeito removido');
    } catch (e) {
      _log('falha ao remover o efeito: $e');
    }
  }

  /// Desliga o efeito do plugin ANTES de arrastar a janela (troca por
  /// transparência simples, sem desfoque) — ver [solidWhileDragging]. Vale
  /// pra TODAS as versões do Windows (antes eu pulava o 11 22H2+, e era
  /// justamente onde a lentidão acontecia).
  static Future<void> suspendForDrag() async {
    if (!solidWhileDragging || !_pluginEffectOn || _suspended) return;
    _suspended = true;
    try {
      await Window.setEffect(effect: WindowEffect.transparent, color: Colors.transparent)
          .timeout(const Duration(seconds: 1));
      _log('efeito pausado para arrastar');
    } catch (e) {
      _log('falha ao pausar o efeito no arrasto: $e');
    }
  }

  /// Volta o efeito depois do arrasto.
  static Future<void> resumeAfterDrag() async {
    if (!_suspended) return;
    _suspended = false;
    final effect = _effect;
    if (!_pluginEffectOn || effect == null) return;
    try {
      await Window.setEffect(effect: effect, color: _effectColor, dark: _effectDark)
          .timeout(const Duration(seconds: 2));
      _log('efeito retomado após o arrasto');
    } catch (e) {
      _log('falha ao retomar o efeito: $e');
    }
  }
}
