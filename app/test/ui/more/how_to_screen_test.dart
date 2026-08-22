/// O tutorial.
///
/// O que este teste protege, acima de tudo: **nao ha audio embarcado**. A
/// narracao sai do TTS do sistema, e por isso a transcricao nao pode divergir
/// do que esta na tela — ela E o que esta na tela.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/l10n/app_localizations.dart';
import 'package:guia_ubs/prefs/locale_store.dart';
import 'package:guia_ubs/speech/speaker.dart';
import 'package:guia_ubs/ui/app_router.dart';
import 'package:guia_ubs/ui/app_scope.dart';
import 'package:guia_ubs/ui/more/how_to_screen.dart';
import 'package:guia_ubs/ui/theme/gubs_metrics.dart';
import 'package:guia_ubs/ui/theme/gubs_theme.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    AppLocale locale = AppLocale.pt,
    double textScale = 1,
    Speaker speaker = const SilentSpeaker(),
  }) async {
    final router = buildGubsRouter(initialLocation: '/mais/como-usar');
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localeStoreProvider.overrideWithValue(MemoryLocaleStore(locale)),
          contentProvider.overrideWithValue(null),
          speakerProvider.overrideWithValue(speaker),
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

  group('os passos', () {
    test('sao cinco, cada um com icone proprio', () {
      expect(howToSteps, hasLength(5));

      final icones = howToSteps.map((s) => s.icon.codePoint).toList();
      expect(
        icones.toSet(),
        hasLength(icones.length),
        reason: 'dois passos com o mesmo desenho sao indistinguiveis para '
            'quem nao le o texto',
      );
    });

    testWidgets('o primeiro aparece, com titulo, frase e posicao',
        (tester) async {
      await pump(tester);

      expect(find.text('Toque no boneco'), findsOneWidget);
      expect(find.textContaining('apontando no corpo'), findsOneWidget);
      expect(find.text('Passo 1 de 5'), findsOneWidget);
    });

    testWidgets('a seta avanca e o voltar some no primeiro', (tester) async {
      // As setas existem alem do arrastar: arrastar para o lado e gesto
      // aprendido, e parte do publico nunca usou um app com carrossel.
      await pump(tester);
      expect(find.byKey(const ValueKey('howto-previous')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('howto-next')));
      await tester.pumpAndSettle();

      expect(find.text('Passo 2 de 5'), findsOneWidget);
      expect(find.byKey(const ValueKey('howto-previous')), findsOneWidget);
    });

    testWidgets('no ultimo passo nao ha para onde avancar', (tester) async {
      await pump(tester);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const ValueKey('howto-next')));
        await tester.pumpAndSettle();
      }

      expect(find.text('Passo 5 de 5'), findsOneWidget);
      expect(find.byKey(const ValueKey('howto-next')), findsNothing);
    });
  });

  group('audio', () {
    testWidgets('sem engine de TTS, o tutorial fica APENAS visual',
        (tester) async {
      // ROM cortada sem engine e risco previsto (A3). Botao que nao fala e
      // pior que botao nenhum: quem depende do audio tocaria nele e concluiria
      // que o app esta quebrado.
      await pump(tester);

      expect(find.byIcon(Icons.volume_up), findsNothing);
      expect(find.text('Toque no boneco'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('com engine, o botao fala o MESMO texto da tela',
        (tester) async {
      // A transcricao nao e um arquivo a parte que possa envelhecer: o texto
      // na tela e a fonte da fala.
      final speaker = _RecordingSpeaker();
      await pump(tester, speaker: speaker);

      await tester.tap(find.byIcon(Icons.volume_up).first);
      await tester.pumpAndSettle();

      expect(speaker.spoken.single, contains('Toque no boneco'));
      expect(speaker.spoken.single, contains('apontando no corpo'));
    });
  });

  group('acessibilidade', () {
    testWidgets('as setas tem 64 dp', (tester) async {
      await pump(tester);

      final proxima = find.byKey(const ValueKey('howto-next'));
      expect(tester.getSize(proxima).shortestSide, greaterThanOrEqualTo(64));
      expect(minTouchTarget, greaterThanOrEqualTo(64));
    });

    testWidgets('abre em espanhol', (tester) async {
      await pump(tester, locale: AppLocale.es);

      expect(find.text('Toque el muñeco'), findsOneWidget);
      expect(find.text('Paso 1 de 5'), findsOneWidget);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('sobrevive a fonte ${scale}x em tela de 360x640',
          (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await pump(tester, textScale: scale);

        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// Guarda o que foi falado, para provar que e o texto da tela.
class _RecordingSpeaker implements Speaker {
  final List<String> spoken = [];

  @override
  bool get isAvailable => true;

  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<void> speak(String text, SpeechLocale locale) async => spoken.add(text);

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
