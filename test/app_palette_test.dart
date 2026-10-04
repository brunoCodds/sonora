// Testes da infraestrutura de tema (paletas) e do enum de design do modo
// bandeira. Não dependem de banco de dados nem de plugins nativos.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonora/core/theme/app_palette.dart';
import 'package:sonora/core/theme/app_theme.dart';
import 'package:sonora/data/models/mini_glass_style.dart';
import 'package:sonora/data/models/mini_player_layout.dart';
import 'package:sonora/providers/miniplayer_providers.dart';

/// Razão de contraste WCAG entre duas cores (1 a 21).
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('AppPalettes', () {
    test('ids são únicos', () {
      final ids = AppPalettes.all.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('byId devolve a paleta pedida; id nulo ou desconhecido cai na padrão', () {
      expect(AppPalettes.byId('oceano'), AppPalettes.oceano);
      expect(AppPalettes.byId('violeta'), AppPalettes.violeta);
      expect(AppPalettes.byId(null), AppPalettes.defaultPalette);
      expect(AppPalettes.byId('nao_existe'), AppPalettes.defaultPalette);
    });

    test('a paleta padrão é a Violeta (a original do app)', () {
      expect(AppPalettes.defaultPalette, AppPalettes.violeta);
      expect(AppPalettes.violeta.accent, const Color(0xFF8B5CF6));
      expect(AppPalettes.violeta.background, const Color(0xFF0F0B14));
    });

    test('lerp nas pontas devolve cada paleta', () {
      final start = AppPalettes.violeta.lerp(AppPalettes.oceano, 0);
      final end = AppPalettes.violeta.lerp(AppPalettes.oceano, 1);
      expect(start.background, AppPalettes.violeta.background);
      expect(start.accent, AppPalettes.violeta.accent);
      expect(end.background, AppPalettes.oceano.background);
      expect(end.accent, AppPalettes.oceano.accent);
      expect(end.id, 'oceano');
    });
  });

  // Garante que NENHUMA paleta (as atuais e as que forem adicionadas
  // depois) fique ilegível — texto fraco sobre o fundo, ou destaque que some
  // no fundo. Os mínimos seguem o WCAG (7 = texto principal, 4.5 = texto
  // secundário/títulos destacados, 3 = ícones e controles).
  group('contraste das paletas', () {
    for (final palette in AppPalettes.all) {
      test(palette.name, () {
        final backgrounds = {
          'background': palette.background,
          'surface': palette.surface,
          'surfaceVariant': palette.surfaceVariant,
        };
        backgrounds.forEach((name, bg) {
          expect(_contrast(palette.textPrimary, bg), greaterThanOrEqualTo(7),
              reason: 'textPrimary sobre $name');
          expect(_contrast(palette.textSecondary, bg), greaterThanOrEqualTo(4.5),
              reason: 'textSecondary sobre $name');
        });
        expect(_contrast(palette.textSecondary, palette.surfaceHighlight), greaterThanOrEqualTo(4.5),
            reason: 'textSecondary sobre surfaceHighlight');

        for (final bg in [palette.background, palette.surface]) {
          expect(_contrast(palette.accent, bg), greaterThanOrEqualTo(3), reason: 'accent');
          expect(_contrast(palette.accentVariant, bg), greaterThanOrEqualTo(4.5),
              reason: 'accentVariant (usado em texto)');
        }
        expect(_contrast(palette.accentVariant, palette.surfaceHighlight), greaterThanOrEqualTo(4.5),
            reason: 'accentVariant sobre surfaceHighlight (item selecionado)');
        expect(_contrast(palette.labelOnAccent, palette.accent), greaterThanOrEqualTo(3),
            reason: 'rótulo sobre o destaque');
      });
    }
  });

  group('tema claro e escuro', () {
    test('cada paleta declara o modo certo', () {
      expect(AppPalettes.violeta.isDark, isTrue);
      expect(AppPalettes.alvorada.isDark, isFalse);
      expect(AppPalettes.lavanda.isDark, isFalse);
    });

    test('o ThemeData acompanha o modo da paleta', () {
      expect(AppTheme.fromPalette(AppPalettes.violeta).brightness, Brightness.dark);
      expect(AppTheme.fromPalette(AppPalettes.alvorada).brightness, Brightness.light);
      expect(AppTheme.fromPalette(AppPalettes.alvorada).scaffoldBackgroundColor,
          AppPalettes.alvorada.background);
    });

    test('labelOnAccent: branco por padrão, ou o definido pela paleta', () {
      expect(AppPalettes.violeta.labelOnAccent, Colors.white);
      expect(AppPalettes.esmeralda.labelOnAccent, AppPalettes.esmeralda.onAccent);
    });

    test('lerp entre uma paleta escura e uma clara chega nas duas pontas', () {
      final end = AppPalettes.violeta.lerp(AppPalettes.alvorada, 1);
      expect(end.background, AppPalettes.alvorada.background);
      expect(end.brightness, Brightness.light);
    });
  });

  test('AppTheme.fromPalette monta o tema a partir da paleta', () {
    final theme = AppTheme.fromPalette(AppPalettes.oceano);
    expect(theme.extension<AppPalette>(), AppPalettes.oceano);
    expect(theme.scaffoldBackgroundColor, AppPalettes.oceano.background);
    expect(theme.colorScheme.primary, AppPalettes.oceano.accent);
  });

  testWidgets('context.palette lê a paleta do tema', (tester) async {
    late AppPalette read;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromPalette(AppPalettes.oceano),
        home: Builder(
          builder: (context) {
            read = context.palette;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(read.id, 'oceano');
  });

  testWidgets('context.palette cai na padrão se o tema não tiver a extensão', (tester) async {
    late AppPalette read;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            read = context.palette;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(read.id, AppPalettes.defaultPalette.id);
  });

  test('a opacidade padrão do fundo do Discreto está dentro dos limites', () {
    expect(kMiniGlassOpacityDefault, greaterThanOrEqualTo(kMiniGlassOpacityMin));
    expect(kMiniGlassOpacityDefault, lessThanOrEqualTo(kMiniGlassOpacityMax));
    // O padrão é bem transparente (pedido do dono do projeto): abaixo da metade.
    expect(kMiniGlassOpacityDefault, lessThan(0.5));
  });

  group('MiniGlassStyle', () {
    test('há os três estilos, com nomes únicos', () {
      expect(MiniGlassStyle.values.length, 3);
      expect(MiniGlassStyle.values.map((s) => s.name).toSet().length, 3);
    });

    test('fromName reconhece cada estilo', () {
      for (final style in MiniGlassStyle.values) {
        expect(MiniGlassStyle.fromName(style.name), style);
      }
    });

    test('fromName cai no vidro desfocado quando ausente ou desconhecido', () {
      expect(MiniGlassStyle.fromName(null), MiniGlassStyle.desfocado);
      expect(MiniGlassStyle.fromName('nao_existe'), MiniGlassStyle.desfocado);
    });
  });

  group('MiniPlayerLayout', () {
    test('fromName reconhece cada design', () {
      for (final layout in MiniPlayerLayout.values) {
        expect(MiniPlayerLayout.fromName(layout.name), layout);
      }
    });

    test('tamanhos: capa cheia é quadrada; discreto e limpo são menores que o clássico', () {
      final classico = MiniPlayerLayout.classico.windowSize;
      final capa = MiniPlayerLayout.capaCheia.windowSize;
      final discreto = MiniPlayerLayout.discreto.windowSize;
      final limpo = MiniPlayerLayout.limpo.windowSize;

      expect(capa.width, capa.height);
      expect(limpo.width, classico.width);
      expect(limpo.height, lessThan(classico.height));
      expect(discreto.width * discreto.height, lessThan(classico.width * classico.height / 2));
      // O compacto continua no tamanho original do painel.
      expect(MiniPlayerLayout.compacto.windowSize, classico);
    });

    test('só o discreto usa vidro', () {
      for (final layout in MiniPlayerLayout.values) {
        expect(layout.usesGlass, layout == MiniPlayerLayout.discreto);
      }
    });

    test('cada tamanho de painel tem a sua chave de posição salva', () {
      // Os dois designs antigos (mesmo tamanho) compartilham a chave de
      // sempre — assim a posição já salva continua valendo.
      expect(MiniPlayerLayout.classico.positionKeySuffix, '');
      expect(MiniPlayerLayout.compacto.positionKeySuffix, '');
      // Tamanhos diferentes nunca compartilham posição.
      final bySize = <String, Set<String>>{};
      for (final layout in MiniPlayerLayout.values) {
        final size = '${layout.windowSize.width}x${layout.windowSize.height}';
        bySize.putIfAbsent(size, () => {}).add(layout.positionKeySuffix);
      }
      final allSuffixes = MiniPlayerLayout.values.map((l) => l.positionKeySuffix).toList();
      for (final suffixes in bySize.values) {
        expect(suffixes.length, 1, reason: 'mesmo tamanho, mesma chave');
      }
      expect(bySize.length, allSuffixes.toSet().length, reason: 'tamanho diferente, chave diferente');
    });

    test('há os cinco designs, com nomes únicos', () {
      expect(MiniPlayerLayout.values.length, 5);
      final names = MiniPlayerLayout.values.map((l) => l.name).toSet();
      expect(names.length, 5);
    });

    test('fromName cai no clássico quando ausente ou desconhecido', () {
      expect(MiniPlayerLayout.fromName(null), MiniPlayerLayout.classico);
      expect(MiniPlayerLayout.fromName('nao_existe'), MiniPlayerLayout.classico);
    });
  });
}
