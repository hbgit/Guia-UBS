/// As telas de conteúdo estático (RF-07, RF-08, RF-09) contra o pack REAL.
///
/// Estas são as telas que a INV-8 protege: elas continuam de pé quando o
/// modelo, o sync e a rede falham. O que os testes verificam, então, não é só
/// "renderiza" — é que **nada nelas depende de nada**, e que o conteúdo que
/// aparece é o que o pack publicou, na ordem em que publicou.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/content/data/content_repository.dart';
import 'package:guia_ubs/content/domain/content_models.dart';
import 'package:guia_ubs/content/data/pack_rule_source.dart';
import 'package:guia_ubs/l10n/app_localizations.dart';
import 'package:guia_ubs/prefs/locale_store.dart';
import 'package:guia_ubs/ui/app_router.dart';
import 'package:guia_ubs/ui/app_scope.dart';
import 'package:guia_ubs/ui/content/content_providers.dart';
import 'package:guia_ubs/ui/content/widgets/content_color.dart';
import 'package:guia_ubs/ui/theme/gubs_colors.dart';
import 'package:guia_ubs/ui/theme/gubs_theme.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/sqlite_test_libs.dart';

void main() {
  late Directory tmp;
  late Database db;
  late ContentRepository content;

  setUpAll(configureSqliteForTests);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gubs_static_');
    final copy = File('${tmp.path}/pack.db');
    File('test/fixtures/sync/pack-v1.db').copySync(copy.path);
    db = openPack(copy.path);
    content = ContentRepository(db);
  });

  tearDown(() {
    db.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<void> pump(
    WidgetTester tester,
    String location, {
    ContentRepository? withContent,
    AppLocale locale = AppLocale.pt,
    bool provideContent = true,
  }) async {
    final router = buildGubsRouter(initialLocation: location);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localeStoreProvider.overrideWithValue(MemoryLocaleStore(locale)),
          contentProvider.overrideWithValue(
            provideContent ? (withContent ?? content) : null,
          ),
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

    // O app real chama `restore()` no boot; sem isso `localeControllerProvider`
    // fica em `null` e `contentLanguageProvider` devolve "pt" — ou seja, o
    // conteúdo do PACK nunca seria exercitado em espanhol, mesmo com a moldura
    // traduzida. Foi assim que este teste começou passando por engano.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await container.read(localeControllerProvider.notifier).restore();
    await tester.pumpAndSettle();
  }

  group('onde ir (RF-07)', () {
    testWidgets('mostra todos os locais do pack, com seus serviços',
        (tester) async {
      await pump(tester, '/onde-ir');
      final list = find.byType(Scrollable).first;

      for (final venue in content.venues()) {
        final card = find.byKey(ValueKey('venue-${venue.id}'));
        await tester.scrollUntilVisible(card, 240, scrollable: list);
        expect(card, findsOneWidget, reason: 'local ${venue.id} não apareceu');

        for (final service in content.servicesOf(venue.id)) {
          expect(
            find.byKey(ValueKey('service-${service.id}')),
            findsOneWidget,
            reason: 'serviço ${service.id} não apareceu',
          );
        }
      }
    });

    testWidgets('a UBS vem primeiro — a ordem é do pack, não alfabética',
        (tester) async {
      // Ordenar por `id` seria alfabético, e alfabético punha HOSPITAL no topo
      // da tela cujo propósito é encaminhar para a atenção básica quem não
      // precisa de pronto-socorro. Quem lidera é curadoria de conteúdo.
      await pump(tester, '/onde-ir');

      final ordered = content.venues().map((v) => v.id).toList();
      expect(ordered.first, 'UBS');
      expect(
        ordered,
        isNot(List.of(ordered)..sort()),
        reason: 'a ordem coincide com a alfabética; o teste não prova nada',
      );

      final firstCard = find.byKey(ValueKey('venue-${ordered.first}'));
      final secondCard = find.byKey(ValueKey('venue-${ordered[1]}'));
      expect(
        tester.getTopLeft(firstCard).dy,
        lessThan(tester.getTopLeft(secondCard).dy),
      );
    });

    testWidgets('a cor de cada local vem do token DO PACK', (tester) async {
      // O pack diz `green` para UBS e `red` para UPA/hospital. Se o binário
      // decidisse a cor, uma republicação não conseguiria corrigir um
      // encaminhamento pintado errado.
      await pump(tester, '/onde-ir');
      final list = find.byType(Scrollable).first;

      for (final venue in content.venues()) {
        final card = find.byKey(ValueKey('venue-${venue.id}'));
        await tester.scrollUntilVisible(card, 240, scrollable: list);
        final container = tester.widget<Container>(card);
        final border = (container.decoration! as BoxDecoration).border!.top;
        expect(
          border.color,
          colorsForToken(venue.colorToken, GubsColors.light).accent,
          reason: 'local ${venue.id} (token "${venue.colorToken}")',
        );
      }
    });

    test('token desconhecido vira AZUL, nunca verde nem vermelho', () {
      // Chutar verde diria "pode esperar"; chutar vermelho diria "corra".
      // Azul diz "isto é informação", que é o que de fato sabemos.
      const colors = GubsColors.light;

      expect(colorsForToken('cor-que-nao-existe', colors).accent, colors.blue);
      expect(colorsForToken('', colors).accent, colors.blue);
    });

    testWidgets('tocar um serviço leva aos documentos daquele atendimento',
        (tester) async {
      await pump(tester, '/onde-ir');
      final service = content.servicesOf('UBS').first;

      await tester.tap(find.byKey(ValueKey('service-${service.id}')));
      await tester.pumpAndSettle();

      expect(find.text('O que levar?'), findsWidgets);
      for (final doc in content.documentsFor(service.id)) {
        expect(find.byKey(ValueKey('document-${doc.id}')), findsOneWidget);
      }
    });
  });

  group('documentos (RF-08)', () {
    testWidgets('documentos mudam conforme o atendimento escolhido',
        (tester) async {
      // Mostrar uma lista única faria alguém desistir de ir à UBS por achar
      // que falta um papel que aquele atendimento não exige.
      await pump(tester, '/documentos');

      final vaccine = content.documentsFor('svc.vaccine');
      final urgency = content.documentsFor('svc.emergency');
      expect(
        vaccine.length,
        isNot(urgency.length),
        reason: 'o pack precisa ter listas diferentes para o teste valer',
      );

      // `ensureVisible` antes do toque: a régua de serviços rola na
      // horizontal, e um `ListView` não constrói o que está fora da tela.
      // Sem rolagem: todos os atendimentos ficam visíveis de uma vez. Foi
      // este teste que mostrou que o seletor rolante escondia o último — e
      // conteúdo fora da tela, para este público, é conteúdo que não existe.
      final chip = find.byKey(const ValueKey('doc-service-svc.emergency'));
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      expect(
        container.read(selectedServiceProvider),
        'svc.emergency',
        reason: 'o toque no seletor não trocou o atendimento',
      );

      for (final doc in urgency) {
        expect(find.byKey(ValueKey('document-${doc.id}')), findsOneWidget);
      }
      final missing = vaccine.where((d) => !urgency.any((u) => u.id == d.id));
      for (final doc in missing) {
        expect(find.byKey(ValueKey('document-${doc.id}')), findsNothing);
      }
    });

    testWidgets('obrigatórios aparecem antes dos opcionais na tela',
        (tester) async {
      await pump(tester, '/documentos');
      final docs = content.documentsFor(content.servicesOf('UBS').first.id);
      final required = docs.where((d) => d.required).toList();
      final optional = docs.where((d) => !d.required).toList();
      expect(required, isNotEmpty);
      expect(optional, isNotEmpty);

      final lastRequiredY = required
          .map((d) => tester.getTopLeft(find.byKey(ValueKey('document-${d.id}'))).dy)
          .reduce((a, b) => a > b ? a : b);
      final firstOptionalY = optional
          .map((d) => tester.getTopLeft(find.byKey(ValueKey('document-${d.id}'))).dy)
          .reduce((a, b) => a < b ? a : b);

      expect(
        lastRequiredY,
        lessThan(firstOptionalY),
        reason: 'quem tem cinco minutos de atenção precisa ver o que IMPEDE o '
            'atendimento antes do que apenas ajuda',
      );
    });

    testWidgets('todos os atendimentos ficam visíveis sem rolagem',
        (tester) async {
      await pump(tester, '/documentos');

      for (final service in servicesOfPack(content)) {
        final chip = find.byKey(ValueKey('doc-service-${service.id}'));
        expect(chip, findsOneWidget, reason: 'atendimento ${service.id}');
        final rect = tester.getRect(chip);
        expect(
          rect.right,
          lessThanOrEqualTo(800),
          reason: '${service.id} fica fora da tela e ninguém vai procurá-lo',
        );
      }
    });

    testWidgets('obrigatório e opcional se distinguem por rótulo, não só cor',
        (tester) async {
      await pump(tester, '/documentos');

      expect(find.text('Obrigatório'), findsWidgets);
      expect(find.text('Ajuda, mas não impede'), findsWidgets);
    });

    testWidgets('documento obrigatório NÃO usa vermelho', (tester) async {
      // Vermelho neste app significa emergência clínica. Falta de papel não é
      // emergência, e competir por esse significado o enfraquece.
      await pump(tester, '/documentos');
      final doc = content
          .documentsFor(content.servicesOf('UBS').first.id)
          .firstWhere((d) => d.required);

      final icon = tester.widget<Icon>(
        find
            .descendant(
              of: find.byKey(ValueKey('document-${doc.id}')),
              matching: find.byType(Icon),
            )
            .first,
      );
      expect(icon.color, isNot(GubsColors.light.red));
    });
  });

  group('fluxo (RF-09)', () {
    testWidgets('os passos aparecem na ordem publicada', (tester) async {
      await pump(tester, '/fluxo');
      final steps = content.flowOf('UBS');
      expect(steps, isNotEmpty);

      var previousY = -1.0;
      for (final step in steps) {
        final y = tester
            .getTopLeft(find.byKey(ValueKey('flow-step-${step.id}')))
            .dy;
        expect(y, greaterThan(previousY), reason: 'passo ${step.id} fora de ordem');
        previousY = y;
      }
    });

    testWidgets('cada passo mostra número, título e explicação', (tester) async {
      await pump(tester, '/fluxo');

      for (final (index, step) in content.flowOf('UBS').indexed) {
        expect(find.text('${index + 1}'), findsWidgets);
        expect(find.text(step.title.value), findsOneWidget);
        if (step.body != null) {
          expect(find.text(step.body!.value), findsOneWidget);
        }
      }
    });

    testWidgets('com um único local, o seletor não aparece', (tester) async {
      // Um seletor de uma opção é ruído numa tela com teto de oito elementos.
      await pump(tester, '/fluxo');

      expect(find.byKey(const ValueKey('flow-venue-UBS')), findsNothing);
    });
  });

  group('emergência', () {
    testWidgets('mostra o cartão vermelho, o 192 e os locais de urgência',
        (tester) async {
      await pump(tester, '/emergencia');

      expect(find.text('Ligue 192'), findsOneWidget);

      final list = find.byType(Scrollable).first;
      for (final venue in content.venues()) {
        final finder = find.byKey(ValueKey('emergency-venue-${venue.id}'));
        if (isEmergencyToken(venue.colorToken)) {
          await tester.scrollUntilVisible(finder, 200, scrollable: list);
          expect(
            finder,
            findsOneWidget,
            reason: 'local de urgência ${venue.id} não apareceu',
          );
        } else {
          expect(
            finder,
            findsNothing,
            reason: '${venue.id} não é local de urgência (token '
                '"${venue.colorToken}") e não deve aparecer aqui',
          );
        }
      }
    });

    testWidgets('o 192 NÃO é um botão que disca', (tester) async {
      // Discagem a partir de um toque acidental ocupa a linha do SAMU. A
      // decisão de ligar é da pessoa.
      await pump(tester, '/emergencia');

      expect(find.text('Ligue 192'), findsOneWidget);

      // `byWidgetPredicate`, e não `byType`: `find.byType` compara o tipo
      // EXATO, então `byType(ButtonStyleButton)` jamais casaria com um
      // `TextButton` — a primeira versão deste teste era estruturalmente
      // incapaz de falhar, e uma sabotagem que embrulhou o 192 num botão
      // passou ilesa.
      final tappable = find.ancestor(
        of: find.text('Ligue 192'),
        matching: find.byWidgetPredicate(
          (w) => w is ButtonStyleButton || w is InkWell || w is GestureDetector,
        ),
      );
      expect(
        tappable,
        findsNothing,
        reason: 'discagem a partir de um toque acidental ocupa a linha do SAMU',
      );
    });
  });

  group('INV-8 — estas telas não dependem de nada', () {
    testWidgets('funcionam sem modelo, sem sync e sem rede', (tester) async {
      // Nenhum provider de motor ou de sync é sobrescrito neste teste: se
      // alguma tela passasse a depender deles, ela lançaria aqui.
      for (final path in ['/onde-ir', '/documentos', '/fluxo', '/emergencia']) {
        await pump(tester, path);

        expect(tester.takeException(), isNull, reason: path);
      }
    });

    testWidgets('sem pack, cada uma diz que falta conteúdo e segue navegável',
        (tester) async {
      for (final path in ['/onde-ir', '/documentos', '/fluxo', '/emergencia']) {
        await pump(tester, path, provideContent: false);

        expect(tester.takeException(), isNull, reason: path);
        expect(
          find.text('Conteúdo ainda não disponível'),
          findsOneWidget,
          reason: path,
        );
        expect(find.byType(NavigationBar), findsOneWidget, reason: path);
      }
    });
  });

  testWidgets('todas as telas estáticas funcionam em espanhol', (tester) async {
    await pump(tester, '/onde-ir', locale: AppLocale.es);
    expect(find.text('UBS — centro de salud'), findsOneWidget);

    await pump(tester, '/documentos', locale: AppLocale.es);
    expect(find.text('Obligatorio'), findsWidgets);

    await pump(tester, '/fluxo', locale: AppLocale.es);
    expect(find.text('Recepción'), findsOneWidget);
  });
}

/// Todos os serviços do pack, na ordem em que a tela os mostra.
List<Service> servicesOfPack(ContentRepository content) => [
      for (final venue in content.venues()) ...content.servicesOf(venue.id),
    ];
