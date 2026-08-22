/// A aba "Mais": ajustes, ajuda, privacidade e sobre.
///
/// ## Quatro linhas, e o mapa delas é dado
///
/// A lista mora numa constante ([moreEntries]) em vez de sair espalhada por
/// widgets. É o mesmo movimento do mapa de rotas e das matrizes de FSM: quando
/// o requisito é uma propriedade do CONJUNTO — "todo item tem ícone", "todos os
/// ícones são da mesma família", "nenhum destino é rota inexistente" — o teste
/// percorre a lista em vez de inflar cada tela.
///
/// ## Por que os rótulos não truncam
///
/// Nenhum `Text` daqui recebe `maxLines` ou `TextOverflow.ellipsis`: o rótulo
/// quebra em duas linhas e a LINHA cresce em altura. Em espanhol os textos são
/// mais longos ("Privacidad y términos" contra "Privacidade e termos") e com
/// fonte ampliada isso estoura qualquer altura fixa. Reticências num app para
/// quem tem dificuldade de ler são pior que uma lista mais alta: cortam
/// justamente a palavra que daria sentido ao ícone.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../app_routes.dart';
import '../shell/gubs_scaffold.dart';
import '../theme/gubs_colors.dart';
import '../theme/gubs_metrics.dart';

/// Uma linha da lista.
@immutable
class MoreEntry {
  const MoreEntry({
    required this.id,
    required this.icon,
    required this.route,
    required this.label,
    required this.description,
  });

  /// Chave de teste, estável mesmo que rótulo e rota mudem.
  final String id;

  /// **Família outlined, sem exceção.** `help_outline` e `info_outline` são
  /// dessa família apesar do nome sem "d" — não "corrija" para
  /// `help_outlined`, que é o glifo cheio e quebraria o peso óptico da lista.
  final IconData icon;

  /// Nome da rota, não caminho: sobrevive a uma reorganização de URLs.
  final String route;

  final String Function(L l) label;
  final String Function(L l) description;
}

/// A lista, na ordem em que aparece.
///
/// Ordem por frequência de uso esperada, não alfabética: quem abre este menu
/// quase sempre vem trocar idioma ou tamanho de letra. "Sobre" fica por último
/// porque é a única que ninguém abre duas vezes.
const List<MoreEntry> moreEntries = [
  MoreEntry(
    id: 'more-settings',
    icon: Icons.settings_outlined,
    route: Routes.settings,
    label: _settingsLabel,
    description: _settingsDescription,
  ),
  MoreEntry(
    id: 'more-howto',
    icon: Icons.help_outline,
    route: Routes.howTo,
    label: _howToLabel,
    description: _howToDescription,
  ),
  MoreEntry(
    id: 'more-privacy',
    // Escudo COM linhas de documento — é o "escudo com documento" pedido e
    // continua na mesma família dos outros três.
    icon: Icons.policy_outlined,
    route: Routes.privacy,
    label: _privacyLabel,
    description: _privacyDescription,
  ),
  MoreEntry(
    id: 'more-about',
    icon: Icons.info_outline,
    route: Routes.about,
    label: _aboutLabel,
    description: _aboutDescription,
  ),
];

// Funções de topo porque `const` não aceita closure. O ganho de manter
// [moreEntries] constante é que o teste a percorre sem construir nada.
String _settingsLabel(L l) => l.moreSettings;
String _settingsDescription(L l) => l.moreSettingsHint;
String _howToLabel(L l) => l.moreHowTo;
String _howToDescription(L l) => l.moreHowToHint;
String _privacyLabel(L l) => l.morePrivacy;
String _privacyDescription(L l) => l.morePrivacyHint;
String _aboutLabel(L l) => l.moreAbout;
String _aboutDescription(L l) => l.moreAboutHint;

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return GubsScaffold(
      title: l.moreTitle,
      subtitle: l.moreHint,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: moreEntries.length,
        separatorBuilder: (context, index) => const SizedBox(height: spacing),
        itemBuilder: (context, index) => _MoreTile(entry: moreEntries[index]),
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.entry});

  final MoreEntry entry;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final colors = context.gubs;
    final text = Theme.of(context).textTheme;

    return OutlinedButton(
      key: ValueKey(entry.id),
      onPressed: () => context.goNamed(entry.route),
      style: OutlinedButton.styleFrom(
        backgroundColor: colors.surface,
        side: BorderSide(color: colors.line, width: 2),
        padding: const EdgeInsets.symmetric(
          horizontal: spacing * 2,
          vertical: spacing * 1.5,
        ),
        // Altura MÍNIMA, não fixa: o alvo nunca fica abaixo dos 64 dp da
        // RNF-06 e cresce livremente quando o rótulo quebra linha.
        minimumSize: const Size.fromHeight(minTouchTarget),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: [
          Icon(entry.icon, size: 28, color: colors.blue),
          const SizedBox(width: spacing * 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.label(l),
                  style: text.titleMedium?.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: spacing * 0.25),
                Text(
                  entry.description(l),
                  style: text.bodyMedium?.copyWith(color: colors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: spacing),
          // Affordance de avanço. Decorativa: quem usa leitor de tela já ouve
          // o rótulo do botão, e anunciar "seta para a direita" depois dele
          // só acrescentaria ruído.
          ExcludeSemantics(
            child: Icon(Icons.chevron_right, size: 28, color: colors.inkSoft),
          ),
        ],
      ),
    );
  }
}
