/// O selo de procedência na tela de resultado.
///
/// Percorre o fluxo REAL — compor sintomas até o cartão — porque o estado do
/// selo é consequência do que a FSM produziu, e um teste que injetasse o
/// resultado direto verificaria o selo contra um dado que a máquina clínica
/// talvez nunca produza.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/content/data/content_repository.dart';
import 'package:guia_ubs/content/data/pack_rule_source.dart';
import 'package:guia_ubs/l10n/app_localizations.dart';
import 'package:guia_ubs/l10n/app_localizations_pt.dart';
import 'package:guia_ubs/prefs/locale_store.dart';
import 'package:guia_ubs/triage/domain/guidance_provenance.dart';
import 'package:guia_ubs/triage/domain/severity.dart';
import 'package:guia_ubs/triage/engine/triage_engine.dart';
import 'package:guia_ubs/ui/app_router.dart';
import 'package:guia_ubs/ui/app_scope.dart';
import 'package:guia_ubs/ui/theme/gubs_colors.dart';
import 'package:guia_ubs/ui/theme/gubs_theme.dart';
import 'package:guia_ubs/ui/triage/result_screen.dart';
import 'package:guia_ubs/ui/triage/triage_controller.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/sqlite_test_libs.dart';
import '../../support/wcag.dart';

class _FakeEngine implements TriageEngine {
  _FakeEngine({this.available = true, this.suggestion});

  final bool available;
  final EngineSuggestion? suggestion;
  int inferCalls = 0;

  @override
  String get id => 'fake';

  @override
  bool get isAvailable => available;

  @override
  Duration get timeout => const Duration(seconds: 5);

  @override
  Future<EngineSuggestion?> infer(Set<String> tokens) async {
    inferCalls++;
    return suggestion;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  setUpAll(configureSqliteForTests);

  late Directory tmp;
  late Database db;
  late ContentRepository content;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gubs_selo_');
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
    Brightness brightness = Brightness.light,
  }) async {
    final router = buildGubsRouter(initialLocation: '/triagem');
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localeStoreProvider.overrideWithValue(MemoryLocaleStore(locale)),
          contentProvider.overrideWithValue(content),
          triageEngineProvider.overrideWith((ref) => engine),
        ],
        child: MaterialApp.router(
          theme: brightness == Brightness.light ? gubsLightTheme : gubsDarkTheme,
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

  /// O `Container` do cartão de resultado (o primeiro da rolagem).
  BoxDecoration cardDecoration(WidgetTester tester) {
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Container),
          )
          .first,
    );
    return container.decoration! as BoxDecoration;
  }

  group('cada mecanismo mostra o seu selo', () {
    testWidgets('assistente indisponível: regras do posto sem assistente',
        (tester) async {
      await pump(tester, engine: _FakeEngine(available: false));
      await compose(tester, ['throat', 'pain']);

      expect(find.byKey(const ValueKey('provenance-rulesOnly')), findsOneWidget);
      expect(find.text('Regras do posto, sem o assistente'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });

    testWidgets('red flag: regras do posto, sem o modelo participar',
        (tester) async {
      // Este e o UNICO caminho que produz (gate, nao degradado): a regra de
      // seguranca dispara, a FSM vai direto ao resultado e o modelo nem e
      // consultado (INV-1).
      //
      // "Modelo sem opiniao" NAO cai aqui — a sessao o manda para o fallback e
      // marca degradado, o que e honesto: o assistente nao contribuiu.
      final engine = _FakeEngine();
      await pump(tester, engine: engine);
      await compose(tester, ['chest', 'pain', 'severe']);

      expect(engine.inferCalls, 0, reason: 'INV-1: red flag ignora o modelo');
      expect(find.byKey(const ValueKey('provenance-rules')), findsOneWidget);
      expect(find.text('Orientação das regras do posto'), findsOneWidget);
      expect(find.byIcon(Icons.rule), findsOneWidget);
    });

    testWidgets('modelo sem opinião conta como SEM assistente', (tester) async {
      // O modelo respondeu, mas nao mudou nada. Dizer "gerado por assistente"
      // seria falso, e dizer "regras do posto" esconderia que ele foi
      // consultado e nao ajudou.
      await pump(tester, engine: _FakeEngine());
      await compose(tester, ['throat', 'pain']);

      expect(find.byKey(const ValueKey('provenance-rulesOnly')), findsOneWidget);
    });

    testWidgets('motor escalou a severidade: assistente virtual',
        (tester) async {
      // O modelo sobe acima do gate — é o único caminho para `source == engine`.
      await pump(
        tester,
        engine: _FakeEngine(
          suggestion: const EngineSuggestion(
            outcomeId: 'EMERGENCY_UPA',
            severityLevel: 100,
          ),
        ),
      );
      await compose(tester, ['throat', 'pain']);

      expect(find.byKey(const ValueKey('provenance-assistant')), findsOneWidget);
      expect(find.text('Gerado por assistente virtual'), findsOneWidget);
      expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
    });
  });

  group('o selo não invade a codificação de gravidade', () {
    testWidgets('rotina continua VERDE com o selo presente', (tester) async {
      await pump(tester, engine: _FakeEngine(available: false));
      await compose(tester, ['throat', 'pain']);

      final d = cardDecoration(tester);
      expect(d.color, GubsColors.light.greenSoft);
      expect(d.border!.top.color, GubsColors.light.green);
      expect(find.byKey(const ValueKey('provenance-rulesOnly')), findsOneWidget);
    });

    testWidgets('emergência continua VERMELHA com o selo presente',
        (tester) async {
      await pump(tester, engine: _FakeEngine());
      await compose(tester, ['chest', 'pain', 'severe']);

      final d = cardDecoration(tester);
      expect(d.color, GubsColors.light.redSoft);
      expect(d.border!.top.color, GubsColors.light.red);
      expect(find.text('Ligue 192'), findsOneWidget);
    });

    testWidgets('o lílas fica DENTRO do selo, nunca no cartão', (tester) async {
      await pump(tester, engine: _FakeEngine(available: false));
      await compose(tester, ['throat', 'pain']);

      final cartao = cardDecoration(tester);
      for (final proibida in [
        GubsColors.light.lilac,
        GubsColors.light.lilacSoft,
        GubsColors.light.onLilac,
      ]) {
        expect(cartao.color, isNot(proibida));
        expect(cartao.border!.top.color, isNot(proibida));
      }

      // E o selo, esse sim, usa o papel MD3.
      final selo = tester.widget<Container>(
        find.byKey(const ValueKey('provenance-rulesOnly')),
      );
      final seloDeco = selo.decoration! as BoxDecoration;
      expect(seloDeco.color, GubsColors.light.lilacSoft);
      expect(seloDeco.border!.top.color, GubsColors.light.lilac);
    });
  });

  group('aviso de falibilidade', () {
    testWidgets('aparece na rotina', (tester) async {
      await pump(tester, engine: _FakeEngine(available: false));
      await compose(tester, ['throat', 'pain']);

      expect(find.byKey(const ValueKey('result-fallibility')), findsOneWidget);
      expect(find.textContaining('podem conter erros'), findsOneWidget);
    });

    testWidgets('SOME na emergência', (tester) async {
      // Exceção declarada: ao lado de "Ligue 192", uma ressalva enfraquece a
      // única instrução do app que não admite hesitação.
      await pump(tester, engine: _FakeEngine());
      await compose(tester, ['chest', 'pain', 'severe']);

      expect(find.byKey(const ValueKey('result-fallibility')), findsNothing);
      expect(find.text('Ligue 192'), findsOneWidget);
    });

    testWidgets('não manda "procurar um médico"', (tester) async {
      // Descreve consulta eletiva, não urgência.
      await pump(tester, engine: _FakeEngine(available: false));
      await compose(tester, ['throat', 'pain']);

      expect(find.textContaining('médico'), findsNothing);
    });
  });

  group('ordem anunciada ao leitor de tela', () {
    test('procedência, status, título, orientação, aviso', () {
      // Ordem verificada por ÍNDICE, não por presença: um `join` reordenado
      // continuaria contendo tudo e passaria num teste de `contains`.
      final l = LPt();
      final frase = resultAnnouncement(
        l,
        provenance: GuidanceProvenance.assistant,
        severity: GubsSeverity.attention,
        title: 'Procure a UBS hoje',
        body: 'Leve documento.',
        withNote: true,
      );

      final iProc = frase.indexOf('Gerado por assistente virtual');
      final iStatus = frase.indexOf('Atenção');
      final iTitulo = frase.indexOf('Procure a UBS hoje');
      final iCorpo = frase.indexOf('Leve documento');
      final iAviso = frase.indexOf('podem conter erros');

      expect(iProc, 0, reason: 'a procedência vem PRIMEIRO');
      expect(iStatus, greaterThan(iProc));
      expect(iTitulo, greaterThan(iStatus));
      expect(iCorpo, greaterThan(iTitulo));
      expect(iAviso, greaterThan(iCorpo), reason: 'o aviso vem por ÚLTIMO');
    });

    test('sem aviso, a frase termina na orientação', () {
      final frase = resultAnnouncement(
        LPt(),
        provenance: GuidanceProvenance.rules,
        severity: GubsSeverity.emergency,
        title: 'Procure emergência agora',
        body: null,
        withNote: false,
      );

      expect(frase, 'Orientação das regras do posto. Emergência. '
          'Procure emergência agora');
    });
  });

  group('contraste do selo, medido no renderizado', () {
    for (final (nome, brilho, paleta) in [
      ('claro', Brightness.light, GubsColors.light),
      ('escuro', Brightness.dark, GubsColors.dark),
    ]) {
      testWidgets('tema $nome: texto 4,5:1 e borda 3:1', (tester) async {
        await pump(
          tester,
          engine: _FakeEngine(available: false),
          brightness: brilho,
        );
        await compose(tester, ['throat', 'pain']);

        final texto = tester.renderObject<RenderParagraph>(
          find.text('Regras do posto, sem o assistente'),
        );
        expect(
          contrastRatio(texto.text.style!.color!, paleta.lilacSoft),
          greaterThanOrEqualTo(aaNormalText),
        );
        expect(
          contrastRatio(paleta.lilac, paleta.greenSoft),
          greaterThanOrEqualTo(aaLargeTextOrUi),
          reason: 'a borda do selo contra o fundo do cartão de rotina',
        );
      });
    }
  });

  testWidgets('o selo funciona em espanhol', (tester) async {
    await pump(
      tester,
      engine: _FakeEngine(available: false),
      locale: AppLocale.es,
    );
    await compose(tester, ['throat', 'pain']);

    expect(find.text('Reglas del puesto, sin el asistente'), findsOneWidget);
  });
}
