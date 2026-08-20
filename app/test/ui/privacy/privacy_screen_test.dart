/// A tela de privacidade (CAP-13, LGPD-RF03).
///
/// Os critérios de aceitação da LGPD-RF03 são três, e os três são testáveis:
/// o opt-out zera a coleta, "apagar meus dados" é irreversível e alcança o
/// `user.db`, e a tela é operável sem leitura. Um requisito legal que só existe
/// em prosa é um requisito que ninguém verifica.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/l10n/app_localizations.dart';
import 'package:guia_ubs/prefs/locale_store.dart';
import 'package:guia_ubs/prefs/preferences_repository.dart';
import 'package:guia_ubs/prefs/user_database.dart';
import 'package:guia_ubs/prefs/user_database_connection.dart';
import 'package:guia_ubs/telemetry/metric_key.dart';
import 'package:guia_ubs/ui/app_router.dart';
import 'package:guia_ubs/ui/app_scope.dart';
import 'package:guia_ubs/ui/theme/gubs_metrics.dart';
import 'package:guia_ubs/ui/theme/gubs_theme.dart';

import '../../support/sqlite_test_libs.dart';

void main() {
  late UserDatabase db;
  late PreferencesRepository prefs;
  late ProviderContainer container;

  setUpAll(configureSqliteForTests);

  setUp(() {
    db = inMemoryUserDatabase();
    prefs = PreferencesRepository(db);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> pump(WidgetTester tester, {AppLocale locale = AppLocale.pt}) async {
    container = ProviderContainer(
      overrides: [
        preferencesProvider.overrideWithValue(prefs),
        localeStoreProvider.overrideWithValue(prefs),
        contentProvider.overrideWithValue(null),
      ],
    );
    // Roteador SEM os portões: `GubsScaffold` precisa de um `GoRouter` no
    // contexto para resolver o voltar, mas os portões de idioma e de modelo
    // são assunto de `redirect_test`, não desta tela.
    final router = buildGubsRouter(initialLocation: '/privacidade');
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
    // O app real restaura o consentimento no boot; sem isto a tela abriria
    // sempre em "ligado", mesmo com o `user.db` dizendo o contrário.
    await container.read(telemetryConsentProvider.notifier).restore();
    await tester.pumpAndSettle();
  }

  /// Rola até o alvo. A lista é preguiçosa: o que está fora da tela não existe
  /// na árvore. Aqui isso é aceitável — e até desejável para a ação
  /// destrutiva, que não deve estar sob o polegar por acidente.
  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // `scrollUntilVisible` para quando o widget é CONSTRUÍDO, e ele pode ficar
    // sob a barra de abas. `ensureVisible` termina de trazê-lo.
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  group('o que a tela diz que fica no aparelho', () {
    testWidgets('lista uma entrada por preferência realmente guardada',
        (tester) async {
      // A lista da tela e as colunas do `user.db` precisam andar juntas: uma
      // lista redigida à parte envelhece e passa a mentir para o usuário em
      // português claro, com toda a aparência de verdade.
      await pump(tester);

      const declared = [
        'O idioma que você escolheu',
        'Se você aceita ajudar com números de uso',
        'Se o aplicativo já foi preparado',
        'Se o posto liberou baixar por dados móveis',
      ];
      for (final item in declared) {
        expect(find.text(item), findsOneWidget);
      }

      // `id` é chave técnica, não dado sobre a pessoa.
      final columns = db.preferences.$columns
          .map((c) => c.name)
          .where((name) => name != 'id');
      expect(
        columns,
        hasLength(declared.length),
        reason: 'o user.db tem ${columns.length} preferências e a tela explica '
            '${declared.length} — uma delas está invisível para o titular',
      );
    });

    testWidgets('diz que os sintomas não ficam guardados', (tester) async {
      await pump(tester);

      expect(find.textContaining('somem quando a tela fecha'), findsOneWidget);
    });
  });

  group('opt-out de telemetria', () {
    testWidgets('começa ligado e desliga no toque', (tester) async {
      await pump(tester);
      final toggle = find.byKey(const ValueKey('privacy-telemetry'));
      expect(tester.widget<Switch>(toggle).value, isTrue);

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(toggle).value, isFalse);
      expect((await prefs.readAll()).telemetryEnabled, isFalse);
    });

    testWidgets('desligar zera a coleta imediatamente', (tester) async {
      // O critério da LGPD-RF03 fala em zerar envios; aqui zera a CONTAGEM,
      // que é mais forte — quem desligou não tem nem número em memória a
      // respeito de si.
      await pump(tester);
      final recorder = container.read(telemetryProvider);
      recorder.increment(MetricKey.triageCompletedTotal);
      expect(recorder.snapshot().isEmpty, isFalse);

      await tester.tap(find.byKey(const ValueKey('privacy-telemetry')));
      await tester.pumpAndSettle();

      expect(
        recorder.snapshot().isEmpty,
        isTrue,
        reason: 'o que já tinha sido contado precisa sumir junto',
      );
      recorder.increment(MetricKey.triageCompletedTotal);
      expect(
        recorder.snapshot().isEmpty,
        isTrue,
        reason: 'e nada novo pode ser contado depois',
      );
    });

    testWidgets('a escolha sobrevive à reabertura da tela', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('privacy-telemetry')));
      await tester.pumpAndSettle();

      await pump(tester);

      expect(
        tester.widget<Switch>(find.byKey(const ValueKey('privacy-telemetry')))
            .value,
        isFalse,
      );
    });
  });

  group('apagar meus dados', () {
    testWidgets('exige confirmação — um toque não apaga nada', (tester) async {
      // Quem não lê não pode descobrir por engano o botão que apaga tudo.
      await pump(tester);
      await prefs.write(AppLocale.es);

      await reveal(tester, find.byKey(const ValueKey('privacy-wipe')));
      await tester.tap(find.byKey(const ValueKey('privacy-wipe')));
      await tester.pumpAndSettle();

      expect((await prefs.readAll()).locale, AppLocale.es);
      expect(find.byKey(const ValueKey('privacy-wipe-confirm')), findsOneWidget);
    });

    testWidgets('a saída sem destruir é a opção destacada', (tester) async {
      // Numa ação irreversível, o caminho fácil tem de ser o que não destrói.
      await pump(tester);
      await reveal(tester, find.byKey(const ValueKey('privacy-wipe')));
      await tester.tap(find.byKey(const ValueKey('privacy-wipe')));
      await tester.pumpAndSettle();

      final cancel = find.byKey(const ValueKey('privacy-wipe-cancel'));
      final confirm = find.byKey(const ValueKey('privacy-wipe-confirm'));

      expect(tester.widget(cancel), isA<FilledButton>());
      expect(tester.widget(confirm), isA<TextButton>());
      expect(
        tester.getTopLeft(cancel).dy,
        lessThan(tester.getTopLeft(confirm).dy),
        reason: 'a saída segura precisa vir primeiro',
      );
    });

    testWidgets('cancelar volta ao estado anterior', (tester) async {
      await pump(tester);
      await reveal(tester, find.byKey(const ValueKey('privacy-wipe')));
      await tester.tap(find.byKey(const ValueKey('privacy-wipe')));
      await tester.pumpAndSettle();

      await reveal(tester, find.byKey(const ValueKey('privacy-wipe-cancel')));
      await tester.tap(find.byKey(const ValueKey('privacy-wipe-cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('privacy-wipe')), findsOneWidget);
      expect(find.byKey(const ValueKey('privacy-wipe-confirm')), findsNothing);
    });

    testWidgets('confirmar apaga o user.db e a telemetria', (tester) async {
      await pump(tester);
      await prefs.write(AppLocale.es);
      await prefs.setTelemetryEnabled(enabled: true);
      await prefs.setSetupCompleted(completed: true);
      final recorder = container.read(telemetryProvider)
        ..increment(MetricKey.sessionTotal);

      await reveal(tester, find.byKey(const ValueKey('privacy-wipe')));
      await tester.tap(find.byKey(const ValueKey('privacy-wipe')));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('privacy-wipe-confirm')));
      await tester.tap(find.byKey(const ValueKey('privacy-wipe-confirm')));
      await tester.pumpAndSettle();

      final after = await prefs.readAll();
      expect(after.locale, isNull, reason: 'o app precisa perguntar de novo');
      expect(after.setupCompleted, isFalse);
      expect(recorder.snapshot().isEmpty, isTrue);
      expect(find.text('Tudo apagado'), findsOneWidget);
    });
  });

  group('operável sem leitura (LGPD-RF03)', () {
    testWidgets('todo alvo tem pelo menos 64 dp', (tester) async {
      await pump(tester);

      for (final type in [FilledButton, OutlinedButton, TextButton, IconButton]) {
        for (final element in find.byType(type).evaluate()) {
          final size = element.size;
          if (size == null || size.isEmpty) continue;
          expect(
            size.shortestSide,
            greaterThanOrEqualTo(minTouchTarget),
            reason: '${element.widget.runtimeType} tem $size',
          );
        }
      }
    });

    testWidgets('cada bloco tem ícone, não só texto', (tester) async {
      await pump(tester);

      expect(find.byIcon(Icons.shield_outlined), findsWidgets);
      expect(find.byIcon(Icons.translate), findsOneWidget);

      await reveal(tester, find.byIcon(Icons.delete_outline));
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('a tela inteira funciona em espanhol', (tester) async {
      await pump(tester, locale: AppLocale.es);

      expect(find.text('Ayudar a mejorar'), findsOneWidget);

      final wipe = find.text('Borrar mis datos');
      await tester.scrollUntilVisible(
        wipe,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(wipe, findsOneWidget);
    });

    testWidgets('sobrevive à fonte ampliada em tela pequena', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pump(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
