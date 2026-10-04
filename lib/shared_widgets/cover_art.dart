import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme/app_palette.dart';

/// Mostra a capa de uma música/álbum/artista. Quando não há capa
/// embutida no arquivo, desenha um placeholder com gradiente + ícone,
/// em vez de depender de um asset de imagem padrão — mais simples de
/// manter e sempre disponível.
///
/// Prioridade quando os dois estão disponíveis: arquivo local ([path])
/// primeiro, depois imagem de rede ([imageUrl]) — músicas locais nunca
/// têm [imageUrl], e músicas da web raramente têm [path] (só depois de
/// baixadas, se algum dia cachearmos a capa em disco), então na
/// prática cada música só alimenta um dos dois.
class CoverArt extends StatelessWidget {
  final String? path;
  final String? imageUrl;
  final double size;
  final double borderRadius;
  final IconData placeholderIcon;

  const CoverArt({
    super.key,
    required this.path,
    this.imageUrl,
    required this.size,
    this.borderRadius = 6,
    this.placeholderIcon = Icons.music_note_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    Widget child;
    final currentPath = path;
    final currentUrl = imageUrl;
    if (currentPath != null && File(currentPath).existsSync()) {
      child = Image.file(
        File(currentPath),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(context),
      );
    } else if (currentUrl != null && currentUrl.isNotEmpty) {
      child = Image.network(
        currentUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(context),
        loadingBuilder: (context, imageChild, progress) {
          if (progress == null) return imageChild;
          return _placeholder(context);
        },
      );
    } else {
      child = _placeholder(context);
    }

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(width: size, height: size, child: child),
    );
  }

  Widget _placeholder(BuildContext context) {
    final palette = context.palette;
    // Quando `size` é infinito (ex: dentro de um AspectRatio em um grid),
    // usamos um tamanho fixo para o ícone em vez de `size * 0.42`, que
    // resultaria em um valor inválido (infinito) e quebraria o layout.
    final iconSize = size.isFinite ? size * 0.42 : 32.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette.coverGradient,
        ),
      ),
      child: Center(
        child: Icon(
          placeholderIcon,
          size: iconSize,
          color: Colors.white.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}
