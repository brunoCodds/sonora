import 'package:flutter/material.dart';

import '../core/theme/app_palette.dart';

class AppIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final String? tooltip;
  final bool active;
  final Color? activeColor;

  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 22,
    this.tooltip,
    this.active = false,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = active
        ? (activeColor ?? palette.accent)
        : (onPressed == null ? palette.textDisabled : palette.textPrimary);

    final button = IconButton(
      icon: Icon(icon, size: size, color: color),
      onPressed: onPressed,
      splashRadius: size,
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
