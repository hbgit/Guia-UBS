/// Marcador das telas que os itens 12 e 13 preenchem.
///
/// Não é enfeite: ele mantém a árvore de rotas COMPLETA desde o item 10, o que
/// permite ao teste de navegação provar agora — e não depois de tudo pronto —
/// que não existe dead-end e que a profundidade cabe no orçamento da CAP-02.
/// Uma rota que só nasce junto com a tela nunca é testada contra a estrutura.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'shell/gubs_scaffold.dart';
import 'theme/gubs_colors.dart';
import 'theme/gubs_metrics.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    required this.title,
    required this.icon,
    this.accent,
    super.key,
  });

  final String title;
  final IconData icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.gubs;
    return GubsScaffold(
      title: title,
      accent: accent,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 96, color: accent ?? colors.blue),
            const SizedBox(height: spacing * 3),
            Text(
              L.of(context).screenUnderConstruction,
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
