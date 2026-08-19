/// Constrói o `GoRouter` a partir do manifesto de [gubsRoutes].
///
/// O manifesto é a fonte de verdade; este arquivo só o dobra em rotas. Quem
/// acrescentar uma tela mexe na lista, e os testes de estrutura passam a
/// cobri-la automaticamente — inclusive a checagem de dead-end.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import 'app_routes.dart';
import 'home/home_screen.dart';
import 'language/language_screen.dart';
import 'placeholder_screen.dart';
import 'setup/setup_screen.dart';
import 'shell/app_shell.dart';
import 'theme/gubs_colors.dart';

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
  GubsRouteSpec(
    path: '/triagem',
    name: Routes.triageBody,
    tab: GubsTab.home,
    requiresModel: true,
    builder: (context, state) => PlaceholderScreen(
      title: L.of(context).homeStartTriage,
      icon: Icons.accessibility_new,
      accent: context.gubs.green,
    ),
  ),
  GubsRouteSpec(
    path: '/triagem/sintomas',
    name: Routes.triageSymptoms,
    tab: GubsTab.home,
    requiresModel: true,
    builder: (context, state) => PlaceholderScreen(
      title: L.of(context).homeStartTriage,
      icon: Icons.healing,
      accent: context.gubs.green,
    ),
  ),
  GubsRouteSpec(
    path: '/triagem/resultado',
    name: Routes.triageResult,
    tab: GubsTab.home,
    requiresModel: true,
    builder: (context, state) => PlaceholderScreen(
      title: L.of(context).homeStartTriage,
      icon: Icons.assignment_turned_in,
      accent: context.gubs.green,
    ),
  ),
  GubsRouteSpec(
    path: '/emergencia',
    name: Routes.emergency,
    tab: GubsTab.home,
    builder: (context, state) => PlaceholderScreen(
      title: L.of(context).emergencyTitle,
      icon: Icons.emergency,
      accent: context.gubs.red,
    ),
  ),
  GubsRouteSpec(
    path: '/fluxo',
    name: Routes.flow,
    tab: GubsTab.home,
    builder: (context, state) => PlaceholderScreen(
      title: L.of(context).flowTitle,
      icon: Icons.list_alt,
      accent: context.gubs.green,
    ),
  ),
  GubsRouteSpec(
    path: '/privacidade',
    name: Routes.privacy,
    tab: GubsTab.home,
    builder: (context, state) => PlaceholderScreen(
      title: L.of(context).privacyTitle,
      icon: Icons.lock,
    ),
  ),
  GubsRouteSpec(
    path: '/onde-ir',
    name: Routes.whereTo,
    tab: GubsTab.whereTo,
    builder: (context, state) => PlaceholderScreen(
      title: L.of(context).whereToTitle,
      icon: Icons.place,
    ),
  ),
  GubsRouteSpec(
    path: '/documentos',
    name: Routes.documents,
    tab: GubsTab.documents,
    builder: (context, state) => PlaceholderScreen(
      title: L.of(context).documentsTitle,
      icon: Icons.badge,
    ),
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
