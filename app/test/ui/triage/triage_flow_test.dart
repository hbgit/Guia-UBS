/// A triagem de ponta a ponta na interface, contra as regras REAIS do pack.
///
/// Os testes da FSM provam o grafo; os da sessão provam o driver. Estes provam
/// que o que aparece na TELA corresponde ao que a máquina decidiu — inclusive
/// a cor, que é o canal que quem não lê realmente usa.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/content/data/content_repository.dart';
import 'package:guia_ubs/content/data/pack_rule_source.dart';
import 'package:guia_ubs/l10n/app_localizations.dart';
import 'package:guia_ubs/prefs/locale_store.dart';
import 'package:guia_ubs/triage/domain/severity.dart';
import 'package:guia_ubs/triage/engine/triage_engine.dart';
import 'package:guia_ubs/ui/app_router.dart';
import 'package:guia_ubs/ui/app_scope.dart';
import 'package:guia_ubs/ui/theme/gubs_colors.dart';
import 'package:guia_ubs/ui/theme/gubs_theme.dart';
import 'package:guia_ubs/ui/triage/triage_controller.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../support/sqlite_test_libs.dart';
import '../../support/wcag.dart';

class _FakeEngine implements TriageEngine {
  _FakeEngine({this.available = true, this.suggestion});

  bool available;
  EngineSuggestion? suggestion;
  int inferCalls = 0;

  @override
  String get id => 'fake';
  @override
  bool get isAvailable => available;
  @override
  Duration get timeout => const Duration(milliseconds: 200);
  @override
  Future<EngineSuggestion?> infer(Set<String> tokens) async {
    inferCalls++;
    return suggestion;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late Directory tmp;
  late Database db;
  late ContentRepository content;

  setUpAll(configureSqliteForTests);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gubs_flow_');
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
    WidgetTester tester, {
    TriageEngine? engine,
    AppLocale locale = AppLocale.pt,
  }) async {
    final router = buildGubsRouter(initialLocation: '/triagem');
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localeStoreProvider.overrideWithValue(MemoryLocaleStore(locale)),
          contentProvider.overrideWithValue(content),
          triageEngineProvider.overrideWithValue(engine),
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

  /// Toca os ícones e avança até o cartão.
  Future<void> compose(WidgetTester tester, List<String> tokens) async {
    for (var step = 0; step < 3; step++) {
      for (final token in tokens) {
        final finder = find.byKey(ValueKey('token-$token'));
        if (finder.evaluate().isNotEmpty) {
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }
      }
      await tester.tap(find.byKey(const ValueKey('triage-primary')));
      await tester.pumpAndSettle();
    }
  }

  group('composição', () {
    testWidgets('os três passos mostram as três famílias da ontologia',
        (tester) async {
      await pump(tester);

      expect(find.text('Onde dói ou incomoda?'), findsOneWidget);
      expect(find.byKey(const ValueKey('token-chest')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('token-chest')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('triage-primary')));
      await tester.pumpAndSettle();

      expect(find.text('O que você sente?'), findsOneWidget);
      expect(find.byKey(const ValueKey('token-pain')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('triage-primary')));
      await tester.pumpAndSettle();

      expect(find.text('Como está?'), findsOneWidget);
      expect(find.byKey(const ValueKey('token-severe')), findsOneWidget);
    });

    testWidgets('o sexto ícone é recusado e os demais ficam esmaecidos',
        (tester) async {
      await pump(tester);

      // Cinco partes do corpo esgotam o teto do CAP-03.
      for (final token in ['head', 'throat', 'chest', 'belly', 'back']) {
        await tester.tap(find.byKey(ValueKey('token-$token')));
        await tester.pumpAndSettle();
      }

      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('token-arm')))
            .onPressed,
        isNull,
        reason: 'um ícone que não pode mais ser escolhido precisa PARECER '
            'indisponível, senão o toque some sem explicação',
      );
    });

    testWidgets('tocar de novo desmarca — errar não obriga a recomeçar',
        (tester) async {
      await pump(tester);
      final chest = find.byKey(const ValueKey('token-chest'));

      await tester.tap(chest);
      await tester.pumpAndSettle();
      await tester.tap(chest);
      await tester.pumpAndSettle();

      // Sem seleção no primeiro passo, o botão ainda avança (a composição
      // completa é que precisa de ao menos um token).
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('voltar no primeiro passo sai da triagem', (tester) async {
      await pump(tester);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Como você está?'), findsOneWidget);
    });
  });

  group('resultado', () {
    testWidgets('red flag pinta o cartão de VERMELHO e não chama o modelo',
        (tester) async {
      final engine = _FakeEngine(
        suggestion: const EngineSuggestion(
          outcomeId: 'ROUTINE_UBS',
          severityLevel: 10,
        ),
      );
      await pump(tester, engine: engine);

      await compose(tester, ['chest', 'pain', 'severe']);

      expect(engine.inferCalls, 0, reason: 'INV-1: red flag ignora o modelo');
      expect(find.byKey(const ValueKey('result-done')), findsOneWidget);
      expect(find.text('Ligue 192'), findsOneWidget);

      // A cor é o canal primário para quem não lê. Se o cartão de emergência
      // sair verde, a mensagem que essa pessoa recebe é a oposta da correta.
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border!.top.color, GubsColors.light.red);
    });

    testWidgets('rotina pinta de VERDE e não oferece o 192', (tester) async {
      await pump(tester, engine: _FakeEngine(available: false));

      await compose(tester, ['throat', 'pain']);

      expect(find.text('Ligue 192'), findsNothing);
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border!.top.color, GubsColors.light.green);
    });

    testWidgets('sem modelo, o aviso de degradação aparece — discreto',
        (tester) async {
      await pump(tester, engine: _FakeEngine(available: false));

      await compose(tester, ['throat', 'pain']);

      expect(find.text('Orientação feita só com as regras do posto'),
          findsOneWidget);
    });

    testWidgets('o texto do cartão é legível sobre o fundo da severidade',
        (tester) async {
      await pump(tester);
      await compose(tester, ['chest', 'pain', 'severe']);

      final role = GubsColors.light.forSeverity(GubsSeverity.emergency);
      final title = tester.renderObject<RenderParagraph>(
        find.text('Procure emergência agora').first,
      );
      expect(
        contrastRatio(title.text.style!.color!, role.background),
        greaterThanOrEqualTo(aaNormalText),
      );
    });

    testWidgets('sair do resultado apaga a sessão e volta à inicial',
        (tester) async {
      await pump(tester);
      await compose(tester, ['chest', 'pain', 'severe']);

      await tester.tap(find.byKey(const ValueKey('result-done')));
      await tester.pumpAndSettle();

      expect(find.text('Como você está?'), findsOneWidget);

      // Voltar à triagem começa do zero: nenhum ícone marcado do atendimento
      // anterior. Num posto, o aparelho é compartilhado.
      await tester.tap(find.byKey(const ValueKey('home-triage')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('a triagem inteira funciona em espanhol', (tester) async {
      await pump(tester, locale: AppLocale.es);

      expect(find.text('¿Dónde te duele o molesta?'), findsOneWidget);
      await compose(tester, ['chest', 'pain', 'severe']);

      expect(find.text('Llama al 192'), findsOneWidget);
    });
  });

  testWidgets('sem pack, a triagem diz que não há conteúdo e não quebra',
      (tester) async {
    final router = buildGubsRouter(initialLocation: '/triagem');
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localeStoreProvider.overrideWithValue(MemoryLocaleStore(AppLocale.pt)),
          contentProvider.overrideWithValue(null),
        ],
        child: MaterialApp.router(
          theme: gubsLightTheme,
          locale: const Locale('pt'),
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

    expect(tester.takeException(), isNull);
    expect(find.text('Conteúdo ainda não disponível'), findsOneWidget);
  });
}
