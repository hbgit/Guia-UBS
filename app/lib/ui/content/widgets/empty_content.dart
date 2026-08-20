/// Tela de conteúdo indisponível.
///
/// Acontece antes do primeiro sync e quando o pack ativo não passa na
/// verificação. Não é erro: é o app dizendo que ainda não recebeu conteúdo,
/// com a navegação inteira funcionando ao redor (INV-8).
library;

import 'package:flutter/material.dart';

import '../../shell/gubs_scaffold.dart';
import '../../theme/gubs_colors.dart';
import '../../theme/gubs_metrics.dart';

class EmptyContent extends StatelessWidget {
  const EmptyContent({required this.title, required this.message, super.key});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    return GubsScaffold(
      title: title,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 96, color: colors.inkSoft),
            const SizedBox(height: spacing * 3),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: colors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}
