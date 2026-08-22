/// Os documentos legais embarcados.
///
/// Tres coisas precisam ser verdade e nenhuma delas e obvia olhando a tela:
/// os arquivos ESTAO no bundle, cada um declara a data da propria versao, e
/// nada disso toca a rede.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:guia_ubs/l10n/app_localizations.dart';
import 'package:guia_ubs/prefs/locale_store.dart';
import 'package:guia_ubs/ui/app_router.dart';
import 'package:guia_ubs/ui/app_scope.dart';
import 'package:guia_ubs/ui/more/legal_document.dart';
import 'package:guia_ubs/ui/more/legal_documents_screen.dart';
import 'package:guia_ubs/ui/theme/gubs_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('os arquivos estao mesmo no bundle', () {
    for (final idioma in ['pt', 'es']) {
      test('os dois documentos em $idioma carregam', () async {
        final documentos = await loadLegalDocuments(idioma);

        expect(
          documentos,
          hasLength(2),
          reason: 'faltou aviso de privacidade ou termos em $idioma — '
              'provavelmente o pubspec nao declara assets/legal/',
        );
        for (final documento in documentos) {
          expect(documento.blocks, isNotEmpty, reason: documento.asset);
        }
      });

      test('cada documento em $idioma declara a data da versao', () async {
        // Data ausente nao e caso a tratar, e defeito: o titular perde a
        // unica forma de saber qual versao esta lendo.
        for (final documento in await loadLegalDocuments(idioma)) {
          expect(
            documento.versionDate,
            matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
            reason: '${documento.asset} sem cabecalho "<!-- versao: ... -->"',
          );
          expect(documento.displayDate, matches(RegExp(r'^\d{2}/\d{2}/\d{4}$')));
        }
      });
    }

    test('idioma sem traducao recua para pt, e nao some com o documento', () {
      // Sumir com o aviso de privacidade de quem precisa dele e pior que
      // mostra-lo em portugues — mesma regra do conteudo clinico.
      expect(legalAssetsFor('fr'), legalAssetsFor('pt'));
      expect(legalAssetsFor('es').first, contains('_es'));
    });

    test('os documentos ainda estao marcados como minuta', () async {
      // Este teste SAI junto com a aprovacao juridica. Enquanto ele passa, o
      // texto nao pode ser apresentado como definitivo.
      final pt = await rootBundle.loadString('assets/legal/privacidade_pt.md');
      expect(pt.toUpperCase(), contains('MINUTA'));
    });
  });

  group('o parser', () {
    test('separa titulo, subtitulo, paragrafo e item', () {
      final doc = parseLegalDocument('x.md', '''
<!-- versao: 2026-01-31 -->
# Titulo

Um paragrafo
quebrado em duas linhas.

## Subtitulo

- primeiro
- segundo
''');

      expect(doc.versionDate, '2026-01-31');
      expect(doc.displayDate, '31/01/2026');
      expect(doc.blocks.map((b) => b.kind), [
        LegalBlockKind.title,
        LegalBlockKind.paragraph,
        LegalBlockKind.heading,
        LegalBlockKind.bullet,
        LegalBlockKind.bullet,
      ]);
    });

    test('junta linhas do mesmo paragrafo', () {
      // Os arquivos quebram em 80 colunas. Respeitar essa quebra na tela
      // produziria linhas cortadas no meio da frase.
      final doc = parseLegalDocument('x.md', 'uma frase\nque continua.');

      expect(doc.blocks.single.text, 'uma frase que continua.');
    });

    test('comentario que nao e a versao nao chega ao leitor', () {
      final doc = parseLegalDocument('x.md', '<!-- revisar isto -->\ntexto');

      expect(doc.blocks.single.text, 'texto');
      expect(doc.versionDate, isNull);
    });

    test('data malformada vira ausencia, nao data inventada', () {
      final doc = parseLegalDocument('x.md', '<!-- versao: ontem -->\ntexto');

      expect(doc.versionDate, isNull);
      expect(doc.displayDate, isNull);
    });
  });

  group('a tela', () {
    Future<void> pump(WidgetTester tester,
        {AppLocale locale = AppLocale.pt}) async {
      // Os assets sao lidos com I/O REAL, fora do relogio falso do teste, e
      // injetados prontos.
      //
      // Nao e conveniencia: `rootBundle` conversa por canal de plataforma, e
      // dentro de `pumpAndSettle` esse future NUNCA completa. Como a tela em
      // carregamento nao anima nada, `pumpAndSettle` volta sem esperar e o
      // teste veria uma tela vazia, sem excecao nenhuma, para sempre.
      //
      // O caminho real (provider -> loadLegalDocuments -> bundle) esta coberto
      // pelos testes de bundle acima, que rodam sem widget.
      final carregados =
          await tester.runAsync(() => loadLegalDocuments(locale.code));

      final router =
          buildGubsRouter(initialLocation: '/mais/privacidade/documentos');
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localeStoreProvider.overrideWithValue(MemoryLocaleStore(locale)),
            contentProvider.overrideWithValue(null),
            legalDocumentsProvider.overrideWith((ref, arg) => carregados!),
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

    testWidgets('mostra o texto e a data da versao local', (tester) async {
      await pump(tester);
      expect(find.text('Aviso de privacidade'), findsOneWidget);
      expect(find.textContaining('Versão de'), findsOneWidget);
    });

    testWidgets('avisa que o texto e minuta', (tester) async {
      await pump(tester);

      expect(find.textContaining('revisão jurídica'), findsWidgets);
    });

    testWidgets('abre em espanhol', (tester) async {
      await pump(tester, locale: AppLocale.es);

      expect(find.text('Aviso de privacidad'), findsOneWidget);
    });

    testWidgets('sobrevive a fonte 2x em tela pequena', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pump(tester);

      expect(tester.takeException(), isNull);
    });
  });
}
