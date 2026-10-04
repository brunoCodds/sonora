import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../data/models/mini_glass_style.dart';
import '../../data/models/mini_player_layout.dart';
import '../../providers/miniplayer_providers.dart';
import '../../providers/profile_providers.dart';
import '../../providers/theme_providers.dart';
import '../../shared_widgets/user_avatar.dart';

/// Tela de Perfil: reúne o que deixa o app com a cara do usuário — nome,
/// foto, cores do tema e o design do painel do modo bandeira.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: ref.read(profileProvider).name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Escolher foto de perfil',
      type: FileType.image,
      allowMultiple: false,
    );
    final path = result?.files.firstOrNull?.path;
    if (path == null) return; // usuário cancelou.

    final ok = await ref.read(profileProvider.notifier).setPhotoFromFile(path);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Não foi possível usar essa imagem. Tente outra.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final profile = ref.watch(profileProvider);
    final currentPalette = ref.watch(currentPaletteProvider);
    final currentLayout = ref.watch(miniPlayerLayoutProvider);
    final currentGlassStyle = ref.watch(miniGlassStyleProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const Text('Perfil', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 24),
        _Section(
          title: 'Você',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(photoPath: profile.photoPath, size: 96),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name.isEmpty ? 'Sem nome ainda' : profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: profile.name.isEmpty ? palette.textSecondary : palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Nome de usuário',
                      style: TextStyle(fontSize: 12, color: palette.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameController,
                      inputFormatters: [LengthLimitingTextInputFormatter(32)],
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        hintText: 'Como você quer ser chamado?',
                        prefixIcon: Icon(Icons.badge_outlined, size: 20),
                      ),
                      onChanged: (value) => ref.read(profileProvider.notifier).setName(value),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _pickPhoto,
                          icon: const Icon(Icons.photo_camera_outlined, size: 18),
                          label: Text(profile.hasPhoto ? 'Trocar foto' : 'Escolher foto'),
                        ),
                        if (profile.hasPhoto)
                          OutlinedButton.icon(
                            onPressed: () => ref.read(profileProvider.notifier).removePhoto(),
                            icon: const Icon(Icons.delete_outline_rounded, size: 18),
                            label: const Text('Remover foto'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _Section(
          title: 'Tema',
          description: 'As cores do app inteiro. A mudança é aplicada na hora e fica salva.',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final option in AppPalettes.all)
                _PaletteOption(
                  option: option,
                  selected: option.id == currentPalette.id,
                  onTap: () => ref.read(currentPaletteProvider.notifier).select(option),
                ),
            ],
          ),
        ),
        _Section(
          title: 'Modo bandeira',
          description: 'O painel pequeno que aparece ao clicar no ícone da Sonora na bandeja '
              'do sistema (perto do relógio), com o app fechado ou minimizado. '
              'Cada design tem o seu tamanho e lembra a própria posição. '
              'O escolhido vale na próxima vez que o painel abrir.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final layout in MiniPlayerLayout.values)
                    _LayoutOption(
                      layout: layout,
                      selected: layout == currentLayout,
                      onTap: () => ref.read(miniPlayerLayoutProvider.notifier).select(layout),
                    ),
                ],
              ),
              // O fundo só existe no Discreto, então só aparece com ele escolhido.
              if (currentLayout == MiniPlayerLayout.discreto) ...[
                const SizedBox(height: 20),
                const Text(
                  'Fundo do painel Discreto',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Se o vidro não aparecer ou deixar a janela lenta ao arrastar, '
                  'experimente Transparente ou Sólido.',
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final style in MiniGlassStyle.values)
                      _GlassStyleOption(
                        style: style,
                        selected: style == currentGlassStyle,
                        onTap: () => ref.read(miniGlassStyleProvider.notifier).select(style),
                      ),
                  ],
                ),
                // Sem transparência (estilo Sólido) a opacidade não faz sentido.
                if (currentGlassStyle != MiniGlassStyle.solido) ...[
                  const SizedBox(height: 20),
                  const _GlassOpacitySlider(),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Cartão de seção — mesmo visual das seções da tela de Configurações.
class _Section extends StatelessWidget {
  final String title;
  final String? description;
  final Widget child;

  const _Section({required this.title, this.description, required this.child});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final description = this.description;

    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (description != null) ...[
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: palette.textSecondary),
                  ),
                  const SizedBox(height: 14),
                ],
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opção de tema: um cartão pintado com as cores da própria paleta
/// (prévia), com destaque e um "check" na que está ativa.
class _PaletteOption extends StatelessWidget {
  final AppPalette option;
  final bool selected;
  final VoidCallback onTap;

  const _PaletteOption({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: option.surfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? option.accent : option.divider,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 150,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Dot(color: option.accent, border: option.textPrimary),
                    const SizedBox(width: 6),
                    _Dot(color: option.accentVariant, border: option.textPrimary),
                    const SizedBox(width: 6),
                    _Dot(color: option.surfaceHighlight, border: option.textPrimary),
                    const Spacer(),
                    if (selected)
                      Icon(Icons.check_circle_rounded, size: 18, color: option.accent),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  option.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: option.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  option.isDark ? 'Escuro' : 'Claro',
                  style: TextStyle(fontSize: 11, color: option.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;

  /// Cor da borda (com transparência): vem da própria paleta mostrada, pra
  /// a bolinha continuar visível tanto em fundo escuro quanto claro.
  final Color border;
  const _Dot({required this.color, required this.border});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: border.withValues(alpha: 0.25)),
      ),
    );
  }
}

/// Opção de design do painel do modo bandeira: um desenho esquemático do
/// painel + nome + descrição.
class _LayoutOption extends StatelessWidget {
  final MiniPlayerLayout layout;
  final bool selected;
  final VoidCallback onTap;

  const _LayoutOption({
    required this.layout,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Material(
      color: palette.surfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? palette.accent : palette.divider,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 290,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LayoutPreview(layout: layout),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              layout.label,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (selected)
                            Icon(Icons.check_circle_rounded, size: 18, color: palette.accent),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        layout.description,
                        style: TextStyle(fontSize: 12, color: palette.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Controle da opacidade do fundo do painel Discreto: da esquerda (mais
/// transparente) pra direita (mais sólido). Mostra o valor enquanto arrasta e
/// só grava ao soltar (gravar a cada pixel do arrasto seria escrever no banco
/// dezenas de vezes por segundo).
class _GlassOpacitySlider extends ConsumerStatefulWidget {
  const _GlassOpacitySlider();

  @override
  ConsumerState<_GlassOpacitySlider> createState() => _GlassOpacitySliderState();
}

class _GlassOpacitySliderState extends ConsumerState<_GlassOpacitySlider> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final saved = ref.watch(miniGlassOpacityProvider);
    final value = _dragValue ?? saved;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Opacidade do fundo',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${(value * 100).round()}%',
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Menos = mais transparente (e mais difícil de ler sobre um fundo claro). '
          'Vale na próxima vez que o painel abrir.',
          style: TextStyle(fontSize: 12, color: palette.textSecondary),
        ),
        Slider(
          min: kMiniGlassOpacityMin,
          max: kMiniGlassOpacityMax,
          value: value.clamp(kMiniGlassOpacityMin, kMiniGlassOpacityMax).toDouble(),
          onChanged: (v) => setState(() => _dragValue = v),
          onChangeEnd: (v) {
            ref.read(miniGlassOpacityProvider.notifier).set(v);
            setState(() => _dragValue = null);
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Mais transparente', style: TextStyle(fontSize: 11, color: palette.textSecondary)),
            Text('Mais sólido', style: TextStyle(fontSize: 11, color: palette.textSecondary)),
          ],
        ),
      ],
    );
  }
}

/// Opção de fundo do painel Discreto: nome + descrição curta, no mesmo
/// visual das outras opções (destaque e "check" na escolhida).
class _GlassStyleOption extends StatelessWidget {
  final MiniGlassStyle style;
  final bool selected;
  final VoidCallback onTap;

  const _GlassStyleOption({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Material(
      color: palette.surfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? palette.accent : palette.divider,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 200,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        style.label,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (selected) Icon(Icons.check_circle_rounded, size: 18, color: palette.accent),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  style.description,
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Desenho esquemático de cada design, na PROPORÇÃO real da janela dele
/// (`MiniPlayerLayout.windowSize`): o clássico é alto, a capa cheia é
/// quadrada, o discreto é um cartão baixinho. Só blocos de cor, sem texto.
/// Cabe sempre num espaço de 76x96.
class _LayoutPreview extends StatelessWidget {
  final MiniPlayerLayout layout;
  const _LayoutPreview({required this.layout});

  static const double _maxWidth = 76;
  static const double _maxHeight = 96;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final windowSize = layout.windowSize;
    final byWidth = _maxWidth / windowSize.width;
    final byHeight = _maxHeight / windowSize.height;
    final scale = byWidth < byHeight ? byWidth : byHeight;
    final width = windowSize.width * scale;
    final height = windowSize.height * scale;

    Widget block(double blockWidth, double blockHeight, {Color? color, double radius = 2}) {
      return Container(
        width: blockWidth,
        height: blockHeight,
        decoration: BoxDecoration(
          color: color ?? palette.surfaceHighlight,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }

    Widget dot(double diameter, Color color) {
      return Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }

    // Os cinco botões de controle (o do meio, o play, é maior).
    final controls = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 5; i++)
          dot(i == 2 ? 9 : 5, i == 2 ? palette.textPrimary : palette.textDisabled),
      ],
    );

    // Anterior / play / próxima, nos designs que só têm o básico.
    Widget basicControls(Color playColor) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            dot(5, palette.textDisabled),
            dot(9, playColor),
            dot(5, palette.textDisabled),
          ],
        );

    final Widget content = switch (layout) {
      MiniPlayerLayout.classico => Column(
          children: [
            block(double.infinity, 5, color: palette.surface),
            const SizedBox(height: 6),
            block(28, 28, radius: 4),
            const SizedBox(height: 6),
            block(34, 3.5, color: palette.textSecondary),
            const SizedBox(height: 3),
            block(22, 3, color: palette.textDisabled),
            const SizedBox(height: 6),
            block(double.infinity, 2.5, color: palette.accent),
            const SizedBox(height: 6),
            controls,
          ],
        ),
      MiniPlayerLayout.compacto => Column(
          children: [
            block(double.infinity, 5, color: palette.surface),
            const SizedBox(height: 6),
            Row(
              children: [
                block(16, 16, radius: 3),
                const SizedBox(width: 4),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    block(22, 3.5, color: palette.textSecondary),
                    const SizedBox(height: 3),
                    block(14, 3, color: palette.textDisabled),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 5),
            block(double.infinity, 2.5, color: palette.accent),
            const SizedBox(height: 5),
            controls,
            const SizedBox(height: 6),
            for (var i = 0; i < 2; i++) ...[
              Row(
                children: [
                  block(7, 7, radius: 1.5),
                  const SizedBox(width: 3),
                  block(i == 0 ? 28 : 20, 3, color: palette.textDisabled),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ],
        ),
      MiniPlayerLayout.limpo => Column(
          children: [
            block(double.infinity, 5, color: palette.surface),
            const SizedBox(height: 5),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: palette.surfaceHighlight, shape: BoxShape.circle),
            ),
            const SizedBox(height: 5),
            block(double.infinity, 2.5, color: palette.accent),
            const SizedBox(height: 4),
            block(30, 3.5, color: palette.textSecondary),
            const SizedBox(height: 3),
            block(20, 3, color: palette.textDisabled),
            const Spacer(),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              color: palette.surface,
              child: basicControls(palette.accent),
            ),
          ],
        ),
      MiniPlayerLayout.capaCheia => Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: palette.coverGradient,
                ),
              ),
            ),
            // Pastilha dos botões "abrir" e "fechar", no canto de cima.
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    dot(3, Colors.white),
                    const SizedBox(width: 3),
                    dot(3, Colors.white),
                  ],
                ),
              ),
            ),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  dot(5, Colors.white70),
                  const SizedBox(width: 5),
                  dot(13, Colors.white),
                  const SizedBox(width: 5),
                  dot(5, Colors.white70),
                ],
              ),
            ),
            Positioned(
              left: 5,
              bottom: 7,
              child: block(26, 3.5, color: Colors.white),
            ),
          ],
        ),
      MiniPlayerLayout.discreto => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                block(11, 11, radius: 2),
                const SizedBox(width: 3),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    block(24, 3, color: palette.textSecondary),
                    const SizedBox(height: 2),
                    block(15, 2.5, color: palette.textDisabled),
                  ],
                ),
                const Spacer(),
                dot(3, palette.textSecondary),
                const SizedBox(width: 2),
                dot(3, palette.textSecondary),
              ],
            ),
            const SizedBox(height: 2),
            block(double.infinity, 2, color: palette.accent),
            const SizedBox(height: 2),
            basicControls(palette.textPrimary),
          ],
        ),
    };

    // O discreto é de vidro: um degradê translúcido sugere "o que está atrás".
    final isGlass = layout == MiniPlayerLayout.discreto;
    final isFullBleed = layout == MiniPlayerLayout.capaCheia;

    return SizedBox(
      width: _maxWidth,
      height: _maxHeight,
      child: Center(
        child: Container(
          width: width,
          height: height,
          padding: isFullBleed ? EdgeInsets.zero : EdgeInsets.all(isGlass ? 3 : 5),
          decoration: BoxDecoration(
            color: isGlass ? null : palette.background,
            gradient: isGlass
                ? LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      palette.accent.withValues(alpha: 0.35),
                      palette.accentVariant.withValues(alpha: 0.18),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: palette.divider),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(isFullBleed ? 5 : 2),
            child: content,
          ),
        ),
      ),
    );
  }
}
