/// A casca: bottom nav de três abas, sempre visível.
///
/// ## Uma pilha só, não uma por aba
///
/// O padrão do Material é cada aba guardar sua própria pilha de navegação
/// (`StatefulShellRoute`). Aqui é uma pilha só, deliberadamente. Com pilhas
/// por aba, voltar para uma aba a devolve onde o usuário parou — o que num app
/// para quem não lê significa reabrir "Documentos" no meio de uma subtela que
/// a pessoa não lembra ter aberto, sem texto que explique onde ela está. Com
/// pilha única, tocar numa aba sempre mostra o topo daquela aba: previsível,
/// e alinhado à "navegação linear" que a CAP-02 pede.
///
/// O custo é perder o "continuar de onde parei" entre abas. Para triagem isso
/// nem seria desejável: a FSM-A devolve a sessão ao repouso por inatividade
/// (120 s) de qualquer forma, e a sequência de sintomas morre em memória.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../app_routes.dart';
import '../theme/gubs_colors.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.child, required this.location, super.key});

  final Widget child;

  /// Caminho atual, para decidir qual aba fica acesa.
  final String location;

  /// Aba correspondente a um caminho.
  ///
  /// Casa é o padrão porque é a raiz de tudo que não pertence às outras duas —
  /// triagem, emergência, fluxo, privacidade. Assim nenhuma tela fica com a
  /// barra apagada, o que deixaria o usuário sem indicação de onde está.
  static GubsTab tabFor(String location) {
    for (final tab in GubsTab.values) {
      if (tab == GubsTab.home) continue;
      if (location == tab.rootPath || location.startsWith('${tab.rootPath}/')) {
        return tab;
      }
    }
    return GubsTab.home;
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final colors = context.gubs;
    final current = tabFor(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.line)),
        ),
        child: NavigationBar(
          selectedIndex: GubsTab.values.indexOf(current),
          onDestinationSelected: (index) =>
              context.go(GubsTab.values[index].rootPath),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: l.navHome,
            ),
            NavigationDestination(
              icon: const Icon(Icons.place_outlined),
              selectedIcon: const Icon(Icons.place),
              label: l.navWhereTo,
            ),
            NavigationDestination(
              icon: const Icon(Icons.badge_outlined),
              selectedIcon: const Icon(Icons.badge),
              label: l.navDocuments,
            ),
          ],
        ),
      ),
    );
  }
}
