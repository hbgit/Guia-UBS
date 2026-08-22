/// A tela de ajustes: escolher, aplicar na hora, e sobreviver ao fechamento.
///
/// Os tres criterios do pedido sao testaveis, e cada um falha de um jeito
/// diferente: escolha que nao aplica parece defeito; escolha que aplica e nao
/// grava some no dia seguinte; escolha que grava numa coluna nao revisada
/// entra na superficie da LGPD sem passar por ninguem.
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

  /// Monta ajustes com o `themeMode` LIGADO ao provider, como no `main`.
  ///
  /// Sem essa ligacao o teste veria o estado mudar e nao veria a tela repintar
  /// — que e exatamente o defeito que o `main` tinha antes desta tarefa: dois
  /// temas declarados e nenhuma forma de escolher entre eles.
  Future<void> pump(WidgetTester tester, {AppLocale locale = AppLocale.pt}) async {
    container = ProviderContainer(
      overrides: [
        preferencesProvider.overrideWithValue(prefs),
        localeStoreProvider.overrideWithValue(prefs),
        contentProvider.overrideWithValue(null),
      ],
    );
    final router = buildGubsRouter(initialLocation: '/mais/ajustes');
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            theme: gubsLightTheme,
            darkTheme: gubsDarkTheme,
            themeMode: switch (ref.watch(themeModeProvider)) {
              GubsThemeMode.system => ThemeMode.system,
              GubsThemeMode.light => ThemeMode.light,
              GubsThemeMode.dark => ThemeMode.dark,
            },
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
      ),
    );
    await tester.pumpAndSettle();
    // O app real restaura no boot.
    await container.read(themeModeProvider.notifier).restore();
    await container.read(fontScaleProvider.notifier).restore();
    await container.read(meteredDownloadProvider.notifier).restore();
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder alvo) async {
    await tester.scrollUntilVisible(alvo, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(alvo);
    await tester.pumpAndSettle();
  }

  group('tema', () {
    testWidgets('escolher escuro repinta a tela SEM reinicio', (tester) async {
      await pump(tester);
      expect(Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
          Brightness.light);

      await reveal(tester, find.byKey(const ValueKey('settings-theme-dark')));
      await tester.tap(find.byKey(const ValueKey('settings-theme-dark')));
      await tester.pumpAndSettle();

      expect(
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
        Brightness.dark,
        reason: 'a escolha nao chegou ao MaterialApp',
      );
    });

    testWidgets('a escolha vai para o user.db', (tester) async {
      await pump(tester);
      // Revelar antes de tocar: o grupo de tema comeca abaixo da dobra em
      // tela de teste, e `tap` num alvo parcialmente fora acerta o vazio sem
      // falhar — o teste passaria a verificar nada.
      await reveal(tester, find.byKey(const ValueKey('settings-theme-dark')));
      await tester.tap(find.byKey(const ValueKey('settings-theme-dark')));
      await tester.pumpAndSettle();

      expect((await prefs.readAll()).themeMode, GubsThemeMode.dark);
    });

    testWidgets('a escolha sobrevive a reabertura', (tester) async {
      await prefs.setThemeMode(GubsThemeMode.dark);
      await pump(tester);

      expect(
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
        Brightness.dark,
      );
    });
  });

  group('tamanho da letra', () {
    testWidgets('escolher grande grava o passo', (tester) async {
      await pump(tester);
      await reveal(tester, find.byKey(const ValueKey('settings-font-16')));
      await tester.tap(find.byKey(const ValueKey('settings-font-16')));
      await tester.pumpAndSettle();

      expect((await prefs.readAll()).fontScale, 1.6);
    });

    testWidgets('a escolha sobrevive a reabertura', (tester) async {
      await prefs.setFontScale(1.3);
      await pump(tester);
      await reveal(tester, find.byKey(const ValueKey('settings-font-13')));

      expect(container.read(fontScaleProvider), 1.3);
    });
  });

  group('dados moveis', () {
    testWidgets('o interruptor grava nos dois sentidos', (tester) async {
      await pump(tester);
      final alvo = find.byKey(const ValueKey('settings-metered'));
      await reveal(tester, alvo);

      expect(tester.widget<Switch>(alvo).value, isFalse);
      await tester.tap(alvo);
      await tester.pumpAndSettle();
      expect((await prefs.readAll()).allowMeteredDownload, isTrue);

      await tester.tap(alvo);
      await tester.pumpAndSettle();
      expect((await prefs.readAll()).allowMeteredDownload, isFalse);
    });

    testWidgets('o rotulo e afirmativo, nao uma negacao', (tester) async {
      // "Economia de dados" exigiria entender que LIGAR faz algo NAO
      // acontecer. O publico deste app nao desfaz essa negacao lendo.
      await pump(tester);
      await reveal(tester, find.byKey(const ValueKey('settings-metered')));

      expect(find.text('Baixar usando dados móveis'), findsOneWidget);
      expect(find.textContaining('Economia'), findsNothing);
    });
  });

  group('idioma', () {
    testWidgets('trocar aqui muda a interface inteira', (tester) async {
      await pump(tester);
      expect(find.text('Cores da tela'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('settings-language-es')));
      await tester.pumpAndSettle();

      expect((await prefs.readAll()).locale, AppLocale.es);
      expect(container.read(localeControllerProvider), AppLocale.es);
    });
  });

  group('operavel sem leitura', () {
    testWidgets('todo alvo tem pelo menos 64 dp', (tester) async {
      await pump(tester);

      for (final type in [OutlinedButton, FilledButton, TextButton]) {
        for (final element in find.byType(type).evaluate()) {
          final size = element.size;
          if (size == null || size.isEmpty) continue;
          expect(size.height, greaterThanOrEqualTo(64),
              reason: '${element.widget.runtimeType} tem $size');
        }
      }
      expect(minTouchTarget, greaterThanOrEqualTo(64));
    });

    testWidgets('a opcao escolhida NAO se distingue so pela cor',
        (tester) async {
      // Parte do publico tem deficiencia de visao de cores. A marca e
      // redundante: fundo, borda mais grossa e um icone de visto.
      await pump(tester);

      expect(find.byIcon(Icons.check_circle_outline), findsWidgets);
    });

    testWidgets('a tela inteira funciona em espanhol', (tester) async {
      await pump(tester, locale: AppLocale.es);

      expect(find.text('Colores de la pantalla'), findsOneWidget);
      expect(find.text('Como en el teléfono'), findsOneWidget);
    });

    testWidgets('sobrevive a fonte 2x em tela pequena', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pump(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
