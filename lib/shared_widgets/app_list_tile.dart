import 'package:flutter/material.dart';

/// Substituto do `ListTile` do Flutter para qualquer linha com uma
/// miniatura à esquerda (capa, ícone) — usado em Artistas, Busca, fila
/// de reprodução e no diálogo de "adicionar à playlist".
///
/// O `ListTile` de verdade tem um bug antigo do próprio Flutter, nunca
/// corrigido (flutter/flutter#37451, #66636, #78745, #85857, #159380 —
/// issues abertas desde 2019 até 2024): ele dispara uma asserção fatal
/// ("Leading widget consumes the entire tile width") sempre que a
/// largura disponível fica pequena demais durante QUALQUER
/// redimensionamento de janela — não precisa de nada exótico pra
/// reproduzir, um resize comum arrastando a borda já é o suficiente (é
/// literalmente o passo a passo que uma das issues do próprio Flutter
/// descreve). Um `Row` comum não tem essa asserção: numa largura pequena
/// demais ele só estoura visualmente (evitado aqui com `overflow:
/// ellipsis` nos textos de cada chamador), nunca derruba a árvore de
/// renderização.
class AppListTile extends StatelessWidget {
  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Espelha `ListTile.dense`: linha mais baixa, usada em painéis
  /// compactos (fila de reprodução, painel mini).
  final bool dense;

  const AppListTile({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: dense ? 6 : 10),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    title,
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      subtitle!,
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
