/// A lista da aba "Mais".
///
/// As regras que esta tela precisa cumprir são de conjunto — "toda linha tem
/// ícone", "nenhum rótulo trunca", "todo destino existe" —, e por isso a maior
/// parte delas é verificada percorrendo `moreEntries` em vez de inflar quatro
/// telas.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/l10n/app_localizations.dart';
import 'package:guia_ubs/prefs/locale_store.dart';
import 'package:guia_ubs/ui/app_router.dart';
import 'package:guia_ubs/ui/app_scope.dart';
import 'package:guia_ubs/ui/more/more_screen.dart';
import 'package:guia_ubs/ui/theme/gubs_metrics.dart';
import 'package:guia_ubs/ui/theme/gubs_theme.dart';

/// Monta a tela pelo ROTEADOR REAL, e não isolada.
///
/// `GubsScaffold` resolve o botão voltar consultando o `GoRouter` do contexto,
/// então uma tela deste app não existe sem roteador — montá-la solta testaria
/// uma configuração que nunca acontece em produção.
Future<void> pumpMore(
  WidgetTester tester, {
  AppLocale locale = AppLocale.pt,
  double textScale = 1,
}) async {
  final router = buildGubsRouter(initialLocation: '/mais');
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localeStoreProvider.overrideWithValue(MemoryLocaleStore(locale)),
        contentProvider.overrideWithValue(null),
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
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('a lista como dado', () {
    test('as quatro entradas pedidas estão lá, na ordem', () {
      expect(
        moreEntries.map((e) => e.id),
        ['more-settings', 'more-howto', 'more-privacy', 'more-about'],
      );
    });

    test('todo destino é uma rota que existe', () {
      // Um nome de rota errado só apareceria como exceção no toque — e numa
      // tela que a pessoa abriu justamente por estar perdida.
      final nomes = gubsRoutes.map((r) => r.name).toSet();
      for (final entry in moreEntries) {
        expect(
          nomes,
          contains(entry.route),
          reason: '${entry.id} aponta para "${entry.route}", que não existe',
        );
      }
    });

    test('nenhum destino repete', () {
      final rotas = moreEntries.map((e) => e.route).toList();
      expect(rotas.toSet(), hasLength(rotas.length));
    });

    test('todos os ícones são do conjunto vazado, e nenhum repete', () {
      // O pedido é explícito: mesmo conjunto e mesmo peso óptico, sem misturar
      // outlined com filled. `help_outline` e `info_outline` são vazados
      // apesar do nome sem "d" — a comparação é pelo CODE POINT, não pelo
      // nome, porque o nome não existe em tempo de execução.
      final vazados = <int>{
        Icons.settings_outlined.codePoint,
        Icons.help_outline.codePoint,
        Icons.policy_outlined.codePoint,
        Icons.info_outline.codePoint,
      };
      for (final entry in moreEntries) {
        expect(
          vazados,
          contains(entry.icon.codePoint),
          reason: '${entry.id} usa um ícone fora do conjunto vazado declarado',
        );
      }
      final pontos = moreEntries.map((e) => e.icon.codePoint).toList();
      expect(pontos.toSet(), hasLength(pontos.length));
    });
  });

  group('a tela renderizada', () {
    testWidgets('cada linha tem ícone, rótulo e seta', (tester) async {
      await pumpMore(tester);

      for (final entry in moreEntries) {
        expect(
          find.byKey(ValueKey(entry.id)),
          findsOneWidget,
          reason: '${entry.id} não foi desenhada',
        );
        expect(
          find.descendant(
            of: find.byKey(ValueKey(entry.id)),
            matching: find.byIcon(entry.icon),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(ValueKey(entry.id)),
            matching: find.byIcon(Icons.chevron_right),
          ),
          findsOneWidget,
          reason: 'sem affordance de avanço, a linha não parece tocável',
        );
      }
    });

    testWidgets('todo alvo tem pelo menos 64 dp', (tester) async {
      // O pedido dizia 48 dp de alvo e 56 dp de linha; a RNF-06 deste projeto
      // é mais estrita, e onde as duas divergem vale a mais estrita. O número
      // está escrito aqui, e não lido de `minTouchTarget`, para que baixar a
      // constante não faça o teste baixar junto.
      await pumpMore(tester);

      for (final entry in moreEntries) {
        final size = tester.getSize(find.byKey(ValueKey(entry.id)));
        expect(size.height, greaterThanOrEqualTo(64), reason: entry.id);
        expect(size.width, greaterThanOrEqualTo(64), reason: entry.id);
      }
      expect(minTouchTarget, greaterThanOrEqualTo(64));
    });

    testWidgets('nenhum rótulo é truncado com reticências', (tester) async {
      // Reticências cortariam justamente a palavra que dá sentido ao ícone.
      await pumpMore(tester);

      for (final element in find.byType(Text).evaluate()) {
        final text = element.widget as Text;
        expect(
          text.overflow,
          isNot(TextOverflow.ellipsis),
          reason: '"${text.data}" está configurado para truncar',
        );
        expect(text.maxLines, isNull, reason: '"${text.data}" limita linhas');
      }
    });

    testWidgets('em espanhol os rótulos crescem em ALTURA, não truncam',
        (tester) async {
      // "Privacidad y términos" é mais longo que "Privacidade e termos". Se a
      // linha tivesse altura fixa, a diferença viraria corte.
      await pumpMore(tester);
      final alturaPt =
          tester.getSize(find.byKey(const ValueKey('more-privacy'))).height;

      await pumpMore(tester, locale: AppLocale.es);

      expect(find.text('Privacidad y términos'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('more-privacy'))).height,
        greaterThanOrEqualTo(alturaPt),
      );
      expect(tester.takeException(), isNull);
    });

    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets('sobrevive à fonte ${scale}x em tela de 360x640',
          (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await pumpMore(tester, textScale: scale);

        expect(tester.takeException(), isNull);
        // A lista rola; o que importa é que a primeira entrada continue lá e
        // nada estoure.
        expect(find.byKey(const ValueKey('more-settings')), findsOneWidget);
      });
    }

    testWidgets('quatro escolhas cabem no teto de oito elementos',
        (tester) async {
      await pumpMore(tester);

      final botoes = find.byType(OutlinedButton).evaluate().length;
      // As 3 abas da casca somam ao orçamento, como na tela inicial.
      expect(botoes + 3, lessThanOrEqualTo(maxElementsPerScreen));
    });
  });
}
