import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../data/models/playlist.dart';
import '../../../shared_widgets/cover_art.dart';

class PlaylistTile extends StatelessWidget {
  final Playlist playlist;
  final String? coverPath;
  final String? coverUrl;
  final VoidCallback onTap;

  const PlaylistTile({
    super.key,
    required this.playlist,
    required this.coverPath,
    this.coverUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: CoverArt(
                  path: coverPath,
                  imageUrl: coverUrl,
                  size: double.infinity,
                  borderRadius: 8,
                  placeholderIcon: Icons.queue_music_rounded,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                '${playlist.songIds.length} música${playlist.songIds.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
