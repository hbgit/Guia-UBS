/// "Li e concordo" na primeira abertura e a cada versão nova dos termos
/// (ADR-004, §3.1(1) dos Gemma Terms of Use).
///
/// A regra que não se negocia: recusar desliga SÓ o assistente. A tela tem
/// saída de um toque para a inicial, porque quem abre o app pode estar numa
/// emergência.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/l10n/app_localizations.dart';
import 'package:guia_ubs/prefs/locale_store.dart';
import 'package:guia_ubs/speech/speaker.dart';
import 'package:guia_ubs/ui/app_scope.dart';
import 'package:guia_ubs/ui/legal/terms_gate_screen.dart';
import 'package:guia_ubs/ui/more/legal_document.dart';
import 'package:guia_ubs/ui/theme/gubs_metrics.dart';
import 'package:guia_ubs/ui/theme/gubs_theme.dart';

class _Fala implements Speaker {
  final falas = <String>[];
  @override
  Future<void> speak(String text, SpeechLocale locale) async => falas.add(text);
  @override
  Future<void> stop() async {}
  @override
  Future<void> ensureInitialized() async {}
  @override
  Future<void> dispose() async {}
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Respostas em memória: o que a tela grava, sem banco.
class _Respostas extends TermsAnswerController {
  _Respostas(super.initial) : super.memory();
}

void main() {
  test('a versao vigente e a dos dois arquivos de termos', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final idioma in ['pt', 'es']) {
      final t = await rootBundle.loadString('assets/legal/termos_$idioma.md');
      expect(parseLegalDocument('x', t).versionDate, termsVersion,
          reason: 'termos_$idioma.md e termsVersion divergem: o "li e '
              'concordo" perguntaria pela versao errada');
    }
  });

  Future<(_Respostas, _Fala)> pump(WidgetTester tester,
      {TermsAnswer? inicial = const TermsAnswer(version: null, accepted: false),
      AppLocale locale = AppLocale.pt}) async {
    final respostas = _Respostas(inicial);
    final fala = _Fala();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localeStoreProvider.overrideWithValue(MemoryLocaleStore(locale)),
        termsAnswerProvider.overrideWith((ref) => respostas),
        speakerProvider.overrideWithValue(fala),
      ],
      child: MaterialApp(
        theme: gubsLightTheme,
        locale: Locale(locale.code),
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L.supportedLocales,
        home: const TermsGateScreen(),
      ),
    ));
    await tester.pump();
    return (respostas, fala);
  }

  testWidgets('primeira vez: mostra o resumo, o Notice e as quatro acoes',
      (tester) async {
    await pump(tester);

    expect(find.text('Termos de uso'), findsOneWidget);
    expect(find.text(gemmaNoticeLine), findsOneWidget);
    for (final key in ['terms-listen', 'terms-read', 'terms-accept', 'terms-decline']) {
      final alvo = find.byKey(ValueKey(key));
      await tester.ensureVisible(alvo);
      expect(tester.getSize(alvo).height, greaterThanOrEqualTo(minTouchTarget),
          reason: key);
    }
    final acionaveis = find.byWidgetPredicate((w) => w is ButtonStyleButton);
    expect(acionaveis.evaluate().length, lessThanOrEqualTo(maxElementsPerScreen));
  });

  testWidgets('versao nova para quem ja respondeu: diz que os termos mudaram',
      (tester) async {
    await pump(tester,
        inicial: const TermsAnswer(version: '2026-08-22', accepted: true));
    expect(find.text('Os termos de uso mudaram'), findsOneWidget);
  });

  testWidgets('li e concordo grava a versao vigente e aceita', (tester) async {
    final (respostas, _) = await pump(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('terms-accept')));
    await tester.tap(find.byKey(const ValueKey('terms-accept')));
    await tester.pump();

    expect(respostas.state,
        const TermsAnswer(version: termsVersion, accepted: true));
  });

  testWidgets('usar sem o assistente grava a recusa, para a versao vigente',
      (tester) async {
    final (respostas, _) = await pump(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('terms-decline')));
    await tester.tap(find.byKey(const ValueKey('terms-decline')));
    await tester.pump();

    expect(respostas.state,
        const TermsAnswer(version: termsVersion, accepted: false));
  });

  testWidgets('o botao Ouvir fala o resumo', (tester) async {
    final (_, fala) = await pump(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('terms-listen')));
    await tester.tap(find.byKey(const ValueKey('terms-listen')));
    await tester.pump();

    expect(fala.falas.single, contains('Gemma'));
  });

  testWidgets('abre em espanhol', (tester) async {
    await pump(tester, locale: AppLocale.es);
    expect(find.text('Términos de uso'), findsOneWidget);
  });

  testWidgets('sobrevive a tela pequena', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester);
    expect(tester.takeException(), isNull);
  });

  group('assistantAllowedProvider', () {
    bool permitido(TermsAnswer? a) {
      final c = ProviderContainer(overrides: [
        termsAnswerProvider.overrideWith((ref) => _Respostas(a)),
      ]);
      addTearDown(c.dispose);
      return c.read(assistantAllowedProvider);
    }

    test('so com aceite da versao vigente', () {
      expect(permitido(const TermsAnswer(version: termsVersion, accepted: true)),
          isTrue);
      expect(permitido(const TermsAnswer(version: termsVersion, accepted: false)),
          isFalse);
      expect(permitido(const TermsAnswer(version: '2026-08-22', accepted: true)),
          isFalse, reason: 'aceite de versao antiga nao vale para a nova');
      expect(permitido(null), isFalse,
          reason: 'antes de ler as preferencias, o modelo nao sobe');
    });
  });
}
