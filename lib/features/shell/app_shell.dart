import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../providers/audio_providers.dart';
import '../../providers/navigation_providers.dart';
import '../albums/albums_screen.dart';
import '../artists/artists_screen.dart';
import '../favorites/favorites_screen.dart';
import '../library/library_screen.dart';
import '../player/player_bar.dart';
import '../player/widgets/queue_panel.dart';
import '../playlists/playlists_screen.dart';
import '../profile/profile_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import 'sidebar.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const _sections = [
    AppSection.library,
    AppSection.playlists,
    AppSection.albums,
    AppSection.artists,
    AppSection.favorites,
    AppSection.search,
    AppSection.profile,
    AppSection.settings,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final currentSection = ref.watch(currentSectionProvider);
    final queuePanelOpen = ref.watch(queuePanelOpenProvider);
    final index = _sections.indexOf(currentSection);

    ref.listen(queueControllerProvider, (previous, next) {
      final error = next.playbackError;
      if (error != null && error != previous?.playbackError) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error)));
      }
    });

    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Sidebar(),
                Expanded(
                  child: IndexedStack(
                    index: index,
                    children: const [
                      LibraryScreen(),
                      PlaylistsScreen(),
                      AlbumsScreen(),
                      ArtistsScreen(),
                      FavoritesScreen(),
                      SearchScreen(),
                      ProfileScreen(),
                      SettingsScreen(),
                    ],
                  ),
                ),
                if (queuePanelOpen) ...[
                  VerticalDivider(width: 1, color: palette.divider),
                  const QueuePanel(),
                ],
              ],
            ),
          ),
          const PlayerBar(),
        ],
      ),
    );
  }
}
