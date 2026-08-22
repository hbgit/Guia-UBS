/// Constrói o `GoRouter` a partir do manifesto de [gubsRoutes].
///
/// O manifesto é a fonte de verdade; este arquivo só o dobra em rotas. Quem
/// acrescentar uma tela mexe na lista, e os testes de estrutura passam a
/// cobri-la automaticamente — inclusive a checagem de dead-end.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_routes.dart';
import 'home/home_screen.dart';
import 'language/language_screen.dart';
import 'privacy/privacy_screen.dart';
import 'content/documents_screen.dart';
import 'content/emergency_screen.dart';
import 'content/flow_screen.dart';
import 'content/where_to_screen.dart';
import 'more/about_screen.dart';
import 'more/how_to_screen.dart';
import 'more/legal_documents_screen.dart';
import 'more/more_screen.dart';
import 'more/settings_screen.dart';
import 'setup/setup_screen.dart';
import 'triage/composition_screen.dart';
import 'triage/result_screen.dart';
import 'shell/app_shell.dart';

/// Todas as telas do app.
///
/// As de placeholder são substituídas pelos itens 12 (triagem) e 13
/// (encaminhamento, fluxo, documentos) — mas os caminhos já são estes, para
/// que a estrutura seja testável desde agora.
final List<GubsRouteSpec> gubsRoutes = [
  GubsRouteSpec(
    path: '/configuracao',
    name: Routes.setup,
    tab: null,
    insideShell: false,
    builder: (context, state) => const SetupScreen(),
  ),
  GubsRouteSpec(
    path: '/idioma',
    name: Routes.language,
    tab: null,
    insideShell: false,
    builder: (context, state) => const LanguageScreen(),
  ),
  GubsRouteSpec(
    path: '/',
    name: Routes.home,
    tab: GubsTab.home,
    builder: (context, state) => const HomeScreen(),
  ),
  // Os tres passos da composicao moram numa rota so: a FSM-A permanece em
  // S1_COMPOSING durante os tres, e dar uma rota a cada passo criaria estados
  // de navegacao que a maquina clinica nao reconhece — voltar pelo botao do
  // Android pularia para um passo sem a composicao correspondente.
  GubsRouteSpec(
    path: '/triagem',
    name: Routes.triageBody,
    tab: GubsTab.home,
    requiresModel: true,
    builder: (context, state) => const CompositionScreen(),
  ),
  GubsRouteSpec(
    path: '/triagem/resultado',
    name: Routes.triageResult,
    tab: GubsTab.home,
    requiresModel: true,
    builder: (context, state) => const ResultScreen(),
  ),
  GubsRouteSpec(
    path: '/emergencia',
    name: Routes.emergency,
    tab: GubsTab.home,
    builder: (context, state) => const EmergencyScreen(),
  ),
  GubsRouteSpec(
    path: '/fluxo',
    name: Routes.flow,
    tab: GubsTab.home,
    builder: (context, state) => const FlowScreen(),
  ),
  GubsRouteSpec(
    path: '/onde-ir',
    name: Routes.whereTo,
    tab: GubsTab.whereTo,
    builder: (context, state) => const WhereToScreen(),
  ),
  // "Documentos" deixou de ser raiz de aba (ver `GubsTab`) e passou a ser uma
  // tela da aba inicial. O efeito colateral é bom: `parentPath` agora devolve
  // `/`, e a tela ganha o botão voltar que raiz de aba não tem.
  GubsRouteSpec(
    path: '/documentos',
    name: Routes.documents,
    tab: GubsTab.home,
    builder: (context, state) => const DocumentsScreen(),
  ),
  GubsRouteSpec(
    path: '/mais',
    name: Routes.more,
    tab: GubsTab.more,
    builder: (context, state) => const MoreScreen(),
  ),
  GubsRouteSpec(
    path: '/mais/ajustes',
    name: Routes.settings,
    tab: GubsTab.more,
    builder: (context, state) => const SettingsScreen(),
  ),
  GubsRouteSpec(
    path: '/mais/como-usar',
    name: Routes.howTo,
    tab: GubsTab.more,
    builder: (context, state) => const HowToScreen(),
  ),
  // A tela da CAP-13 mudou de `/privacidade` para cá quando ganhou uma porta
  // no menu. O NOME é o mesmo, e é por ele que o escudo da inicial navega —
  // a LGPD-RF03 pede a tela alcançável, não que ela more num caminho fixo.
  GubsRouteSpec(
    path: '/mais/privacidade',
    name: Routes.privacy,
    tab: GubsTab.more,
    builder: (context, state) => const PrivacyScreen(),
  ),
  GubsRouteSpec(
    path: '/mais/privacidade/documentos',
    name: Routes.legalDocuments,
    tab: GubsTab.more,
    builder: (context, state) => const LegalDocumentsScreen(),
  ),
  GubsRouteSpec(
    path: '/mais/sobre',
    name: Routes.about,
    tab: GubsTab.more,
    builder: (context, state) => const AboutScreen(),
  ),
];

/// Monta o roteador.
///
/// [redirect] recebe o caminho pedido e devolve para onde ir, ou `null` para
/// deixar passar. É por ele que o portão de idioma e o de provisionamento do
/// modelo funcionam sem que nenhuma tela precise saber deles.
GoRouter buildGubsRouter({
  String? Function(String location)? redirect,
  String initialLocation = '/',
  Listenable? refreshListenable,
}) {
  final shellRoutes = gubsRoutes.where((r) => r.insideShell).toList();
  final looseRoutes = gubsRoutes.where((r) => !r.insideShell).toList();

  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: refreshListenable,
    redirect: redirect == null
        ? null
        : (context, state) => redirect(state.matchedLocation),
    routes: [
      for (final spec in looseRoutes)
        GoRoute(
          path: spec.path,
          name: spec.name,
          builder: spec.builder,
        ),
      ShellRoute(
        builder: (context, state, child) => AppShell(
          location: state.matchedLocation,
          child: child,
        ),
        routes: [
          for (final spec in shellRoutes)
            GoRoute(
              path: spec.path,
              name: spec.name,
              builder: spec.builder,
            ),
        ],
      ),
    ],
  );
}
