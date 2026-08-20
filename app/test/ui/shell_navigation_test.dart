/// A casca em funcionamento: navegar de verdade pelo roteador montado.
///
/// Os testes de estrutura provam propriedades do mapa; estes provam que o mapa
/// corresponde ao que o Flutter monta. Um manifesto perfeito ligado a um
/// `ShellRoute` mal configurado passaria naqueles e falharia aqui.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/l10n/app_localizations.dart';
import 'package:guia_ubs/prefs/locale_store.dart';
import 'package:guia_ubs/ui/app_router.dart';
import 'package:guia_ubs/ui/app_routes.dart';
import 'package:guia_ubs/content/data/content_repository.dart';
import 'package:guia_ubs/ui/app_scope.dart';
import 'package:guia_ubs/ui/theme/gubs_theme.dart';

Future<void> pumpApp(
  WidgetTester tester, {
  String initialLocation = '/',
  AppLocale locale = AppLocale.pt,
  ContentRepository? content,
}) async {
  final router = buildGubsRouter(initialLocation: initialLocation);
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localeStoreProvider.overrideWithValue(MemoryLocaleStore(locale)),
        contentProvider.overrideWithValue(content),
      ],
      child: MaterialApp.router(
        theme: gubsLightTheme,
        locale: Locale(locale.code),
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
          ],
        supportedLocales: L.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a barra de abas está presente em toda tela da casca',
      (tester) async {
    // "Casa sempre visível" (CAP-02) é exatamente isto: de qualquer tela, a
    // saída está a um toque, sem precisar descobrir um botão.
    for (final spec in gubsRoutes.where((r) => r.insideShell)) {
      await pumpApp(tester, initialLocation: spec.path);

      expect(
        find.byType(NavigationBar),
        findsOneWidget,
        reason: '${spec.path} não mostra a navegação principal',
      );
    }
  });

  testWidgets('os portões de idioma e setup NÃO mostram a barra', (tester) async {
    // São telas com uma decisão pendente. Oferecer navegação lateral ali
    // seria oferecer saídas que não levam a lugar nenhum.
    await pumpApp(tester, initialLocation: '/idioma');

    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('cada aba abre a tela correspondente', (tester) async {
    await pumpApp(tester);
    expect(find.text('Como você está?'), findsOneWidget);

    await tester.tap(find.text('Onde ir'));
    await tester.pumpAndSettle();
    expect(find.text('Onde ir?'), findsWidgets);

    await tester.tap(find.text('Documentos').first);
    await tester.pumpAndSettle();
    expect(find.text('O que levar?'), findsWidgets);

    await tester.tap(find.text('Início'));
    await tester.pumpAndSettle();
    expect(find.text('Como você está?'), findsOneWidget);
  });

  testWidgets('os ladrilhos da inicial levam ao destino certo', (tester) async {
    for (final (key, expected) in [
      ('home-whereto', 'Onde ir?'),
      ('home-docs', 'O que levar?'),
      ('home-flow', 'Na UBS é assim'),
      ('home-emergency', 'Procure emergência agora'),
    ]) {
      await pumpApp(tester);
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();

      expect(find.text(expected), findsWidgets, reason: 'ladrilho $key');
    }
  });

  testWidgets('toda tela abaixo de uma raiz oferece o botão voltar',
      (tester) async {
    // A prova prática do "zero dead-ends". Chega em cada tela por DEEP LINK, o
    // pior caso: sem pilha de navegação, `canPop()` é falso e a seta só existe
    // se vier do manifesto. Era assim que a tela de triagem aparecia no
    // aparelho — sem nenhum voltar — porque os ladrilhos navegam com `go`, que
    // substitui em vez de empilhar, e o teste antigo usava `push`.
    for (final spec in gubsRoutes.where(
      (r) => r.insideShell && r.parentPath != null,
    )) {
      // O resultado sem sessão é o caso especial coberto pelo teste seguinte:
      // ele não desenha seta, ele MANDA a pessoa para a inicial — que é a
      // saída certa para uma tela cujo conteúdo já não existe.
      if (spec.path == '/triagem/resultado') continue;

      await pumpApp(tester, initialLocation: spec.path);

      expect(
        find.byIcon(Icons.arrow_back),
        findsOneWidget,
        reason: '${spec.path} não tem como voltar',
      );
    }
  });

  testWidgets('resultado sem sessão devolve à inicial, não a uma tela vazia',
      (tester) async {
    // Acontece de verdade: o Android restaura a pilha depois de matar o
    // processo, e a sessão — que só vive em memória (INV-2) — não volta com
    // ela. Uma tela de resultado em branco seria o pior dead-end do app.
    await pumpApp(tester, initialLocation: '/triagem/resultado');

    expect(find.text('Como você está?'), findsOneWidget);
  });

  testWidgets('o voltar leva ao pai declarado no manifesto', (tester) async {
    // Deep link direto na triagem: sem pilha, o destino do voltar só pode vir
    // do manifesto.
    await pumpApp(tester, initialLocation: '/triagem');

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Como você está?'), findsOneWidget);
  });

  testWidgets('as raízes de aba NÃO mostram voltar', (tester) async {
    // Seta que não leva a lugar nenhum é ruído numa tela que precisa de no
    // máximo oito elementos.
    for (final tab in GubsTab.values) {
      await pumpApp(tester, initialLocation: tab.rootPath);

      expect(
        find.byIcon(Icons.arrow_back),
        findsNothing,
        reason: '${tab.rootPath} é raiz e não deveria ter voltar',
      );
    }
  });

  testWidgets('chegar por toque também oferece o voltar', (tester) async {
    // O caminho real do usuário: ladrilho da inicial, que navega com `go`.
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('home-emergency')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Como você está?'), findsOneWidget);
  });

  testWidgets('o app inteiro abre em espanhol', (tester) async {
    await pumpApp(tester, locale: AppLocale.es);

    expect(find.text('¿Cómo estás?'), findsOneWidget);
    expect(find.text('Inicio'), findsWidgets);
    expect(find.text('Adónde ir'), findsWidgets);
  });
}
