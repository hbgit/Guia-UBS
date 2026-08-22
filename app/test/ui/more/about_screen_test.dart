/// A tela "Sobre".
///
/// Especificada nesta tarefa: nao existia tela, spec nem CAP para ela.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/l10n/app_localizations.dart';
import 'package:guia_ubs/prefs/locale_store.dart';
import 'package:guia_ubs/ui/app_router.dart';
import 'package:guia_ubs/ui/app_scope.dart';
import 'package:guia_ubs/ui/more/about_screen.dart';
import 'package:guia_ubs/ui/theme/gubs_metrics.dart';
import 'package:guia_ubs/ui/theme/gubs_theme.dart';

void main() {
  /// [release] nulo simula plugin indisponivel — ROM cortada, canal ausente.
  Future<void> pump(
    WidgetTester tester, {
    AppLocale locale = AppLocale.pt,
    AppRelease? release = (version: '1.2.3', build: '42'),
  }) async {
    final router = buildGubsRouter(initialLocation: '/mais/sobre');
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localeStoreProvider.overrideWithValue(MemoryLocaleStore(locale)),
          contentProvider.overrideWithValue(null),
          // O plugin fica FORA do teste: canal de plataforma em teste de
          // widget testaria o mock, nao a tela.
          appReleaseProvider.overrideWith((ref) async => release),
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

  /// Rola ate o alvo. A lista e preguicosa: o que esta fora da tela nao existe
  /// na arvore, e `getSize` num finder vazio estoura com "No element".
  Future<void> reveal(WidgetTester tester, Finder alvo) async {
    await tester.scrollUntilVisible(alvo, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(alvo);
    await tester.pumpAndSettle();
  }

  testWidgets('mostra versao e build instalados', (tester) async {
    await pump(tester);

    expect(find.text('Versão 1.2.3'), findsOneWidget);
    expect(find.text('Build 42'), findsOneWidget);
  });

  testWidgets('plugin indisponivel nao derruba a tela', (tester) async {
    // INV-8: falha de componente opcional degrada, nao impede. A tela perde os
    // numeros e mantem creditos, aviso e licencas.
    await pump(tester, release: null);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('about-version')), findsNothing);
    expect(find.byKey(const ValueKey('about-clinical-notice')), findsOneWidget);
    await reveal(tester, find.byKey(const ValueKey('about-licenses')));
    expect(find.byKey(const ValueKey('about-licenses')), findsOneWidget);
  });

  testWidgets('o aviso de revisao clinica pendente esta na MESMA tela dos logos',
      (tester) async {
    // Logotipo de instituicao ao lado de orientacao de saude e lido como
    // endosso. Enquanto o conteudo for `clinical_source: "revisao clinica
    // pendente"`, o aviso precisa estar aqui.
    await pump(tester);

    expect(find.byKey(const ValueKey('about-clinical-notice')), findsOneWidget);
    expect(find.textContaining('revisão clínica'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(aboutLogos.length));
  });

  testWidgets('os creditos apontam para arquivos que existem', (tester) async {
    // Caminho de asset errado nao quebra o build nem lanca: aparece como
    // espaco vazio no aparelho de quem instalou. `runAsync` porque o bundle
    // faz I/O real, que nao anda dentro do relogio falso do teste.
    for (final logo in aboutLogos) {
      final bytes = await tester.runAsync(() => rootBundle.load(logo));
      expect(
        bytes?.lengthInBytes ?? 0,
        greaterThan(0),
        reason: '$logo nao esta no bundle — rode tool/gen_about_logos.sh',
      );
    }
  });

  testWidgets('o botao de licencas tem 64 dp', (tester) async {
    await pump(tester);

    final alvo = find.byKey(const ValueKey('about-licenses'));
    await reveal(tester, alvo);
    expect(tester.getSize(alvo).height, greaterThanOrEqualTo(64));
    expect(minTouchTarget, greaterThanOrEqualTo(64));
  });

  testWidgets('abre em espanhol', (tester) async {
    await pump(tester, locale: AppLocale.es);

    expect(find.text('Versión 1.2.3'), findsOneWidget);
    expect(find.text('Realización'), findsOneWidget);
  });

  testWidgets('sobrevive a fonte 2x em tela pequena', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pump(tester);

    expect(tester.takeException(), isNull);
  });
}
