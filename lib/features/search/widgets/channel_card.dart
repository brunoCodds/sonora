import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../data/models/youtube_channel.dart';
import '../../../shared_widgets/cover_art.dart';

/// Card do canal (artista/banda) que aparece logo abaixo das 2 músicas do
/// topo do resultado de uma busca. Tocar nele abre a área do canal ali
/// mesmo, na tela Buscar (ver `ChannelBrowserView`).
///
/// A busca em si não traz o logo do canal: ele é lido em segundo plano
/// logo depois que os resultados aparecem (ver
/// `WebSearchNotifier._loadChannelArt`) e entra no card quando chegar.
/// Até lá — ou se não vier — o card mostra um ícone de pessoa.
class ChannelCard extends StatelessWidget {
  final YoutubeChannelRef channel;
  final VoidCallback onTap;

  const ChannelCard({super.key, required this.channel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Material(
        color: palette.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CoverArt(
                  path: null,
                  imageUrl: channel.avatarUrl,
                  size: 56,
                  borderRadius: 28, // metade do tamanho = círculo.
                  placeholderIcon: Icons.person_rounded,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Canal',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: palette.accentVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Músicas, álbuns, ao vivo e shows',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: palette.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
