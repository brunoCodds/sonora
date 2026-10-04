import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme/app_palette.dart';

/// Avatar circular do usuário: a foto de perfil, ou um ícone genérico de
/// pessoa enquanto nenhuma foto tiver sido escolhida (ou se o arquivo da
/// foto sumir do disco).
class UserAvatar extends StatelessWidget {
  final String? photoPath;
  final double size;

  const UserAvatar({super.key, required this.photoPath, this.size = 96});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final fallback = Icon(
      Icons.person_rounded,
      size: size * 0.55,
      color: palette.textSecondary,
    );

    final path = photoPath;
    final Widget content;
    if (path != null && File(path).existsSync()) {
      content = Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Decodifica já reduzida: uma foto de câmera (vários MP) não
        // precisa ocupar memória inteira pra caber num círculo pequeno.
        cacheWidth: 512,
        errorBuilder: (_, __, ___) => fallback,
      );
    } else {
      content = fallback;
    }

    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: palette.surfaceHighlight,
        alignment: Alignment.center,
        child: content,
      ),
    );
  }
}
