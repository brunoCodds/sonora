import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_palette.dart';
import '../../providers/navigation_providers.dart';

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key});

  static const _items = [
    (AppSection.library, Icons.library_music_rounded, 'Biblioteca'),
    (AppSection.playlists, Icons.queue_music_rounded, 'Playlists'),
    (AppSection.albums, Icons.album_rounded, 'Álbuns'),
    (AppSection.artists, Icons.person_rounded, 'Artistas'),
    (AppSection.favorites, Icons.favorite_rounded, 'Favoritos'),
    (AppSection.search, Icons.search_rounded, 'Buscar'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final currentSection = ref.watch(currentSectionProvider);

    return Container(
      width: AppConstants.sidebarWidth,
      color: palette.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                // Logo oficial (símbolo com fundo transparente): mantém as
                // mesmas cores em todos os temas, claros e escuros.
                Image.asset(
                  'assets/icons/logo_simbolo.png',
                  width: 30,
                  height: 30,
                  filterQuality: FilterQuality.medium,
                ),
                const SizedBox(width: 10),
                // Nome oficial (wordmark). O PNG é branco; `color` + srcIn
                // pinta com a cor de texto do tema, valendo pros temas claros
                // e escuros sem precisar de um segundo arquivo.
                Flexible(
                  child: Image.asset(
                    'assets/icons/logo_nome.png',
                    height: 14,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                    color: palette.textPrimary,
                    colorBlendMode: BlendMode.srcIn,
                    filterQuality: FilterQuality.medium,
                    semanticLabel: AppConstants.appName,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in _items)
                    _SidebarItem(
                      icon: item.$2,
                      label: item.$3,
                      selected: currentSection == item.$1,
                      onTap: () => _select(ref, item.$1),
                    ),
                ],
              ),
            ),
          ),
          _SidebarItem(
            icon: Icons.account_circle_rounded,
            label: 'Perfil',
            selected: currentSection == AppSection.profile,
            onTap: () => _select(ref, AppSection.profile),
          ),
          _SidebarItem(
            icon: Icons.settings_rounded,
            label: 'Configurações',
            selected: currentSection == AppSection.settings,
            onTap: () => _select(ref, AppSection.settings),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _select(WidgetRef ref, AppSection section) {
    ref.read(currentSectionProvider.notifier).state = section;
    ref.read(selectedPlaylistIdProvider.notifier).state = null;
    ref.read(selectedAlbumKeyProvider.notifier).state = null;
    ref.read(selectedArtistNameProvider.notifier).state = null;
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected ? palette.surfaceHighlight : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? palette.accentVariant : palette.textSecondary,
                ),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? palette.textPrimary : palette.textSecondary,
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
