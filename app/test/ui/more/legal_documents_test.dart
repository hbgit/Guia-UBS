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
import 'package:guia_ubs/sync/model_catalog.dart';
import 'package:guia_ubs/ui/app_router.dart';
import 'package:guia_ubs/ui/app_scope.dart';
import 'package:guia_ubs/ui/more/legal_document.dart';
import 'package:guia_ubs/ui/more/legal_documents_screen.dart';
import 'package:guia_ubs/ui/theme/gubs_theme.dart';

/// E-mail compartilhado do projeto (ADR-004). Uma caixa do grupo, nunca de
/// uma pessoa: o repositorio e publico.
const String projectContactEmail = 'prismufrr@gmail.com';

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

    for (final (idioma, grupo) in [
      ('pt', 'grupo de pesquisa PRISM'),
      ('es', 'grupo de investigación PRISM'),
    ]) {
      test('termos_$idioma identificam o projeto, sem e-mail pessoal nem '
          'vinculo institucional', () async {
        // ADR-004: o responsavel e o PROJETO, identificado pelo grupo. A linha
        // identifica quem mantem o app; nao cria parte que assina contrato.
        // Espacos normalizados: os arquivos quebram em 80 colunas e o parser
        // junta as linhas do paragrafo, entao "grupo de pesquisa\nPRISM" e o
        // que o leitor ve como uma frase so.
        final termos =
            (await rootBundle.loadString('assets/legal/termos_$idioma.md'))
                .replaceAll(RegExp(r'\s+'), ' ');

        expect(termos, contains(grupo));
        expect(termos, contains(projectContactEmail));
        expect(termos, isNot(contains('A ser preenchido')));
        expect(termos, isNot(contains('Para completar')));

        // Unica excecao nomeada: o endereco do projeto carrega "ufrr". Fora
        // dele, citar a universidade sugeriria um vinculo formal que nao
        // existe (ADR-004).
        final semEndereco = termos.replaceAll(projectContactEmail, '');
        expect(semEndereco.toUpperCase(), isNot(contains('UFRR')));
        expect(semEndereco, isNot(contains('Universidad')));
      });
    }

    test('os documentos ainda estao marcados como minuta', () async {
      // Este teste SAI junto com a aprovacao juridica. Enquanto ele passa, o
      // texto nao pode ser apresentado como definitivo.
      final pt = await rootBundle.loadString('assets/legal/privacidade_pt.md');
      expect(pt.toUpperCase(), contains('MINUTA'));
    });
  });

  group('documentos do Gemma (ADR-004)', () {
    test('o Notice traz as duas frases literais da §3.1(4), na ordem da D-A',
        () async {
      final linhas =
          (await rootBundle.loadString(gemmaNoticeAsset)).split('\n');
      const frase = 'Gemma is provided under and subject to the Gemma Terms '
          'of Use found at ';
      expect(linhas[0], '${frase}gemma.ai/resources/terms');
      expect(linhas[1], '${frase}ai.google.dev/gemma/terms');
    });

    test('o Notice acompanha o modelo ativo', () async {
      final notice = await rootBundle.loadString(gemmaNoticeAsset);
      expect(notice, contains(activeModel.sha256));
      expect(notice, contains('gemma-3-1b-it-Q4_K_M.gguf'));
      expect(notice, contains('Notice of modification'));
    });

    for (final idioma in ['pt', 'es']) {
      test('os documentos do Gemma em $idioma carregam, com versao', () async {
        final r = await loadGemmaDocuments(idioma);
        expect(r.notice, isNotEmpty);
        expect(r.documents, hasLength(4),
            reason: 'resumo, Politica traduzida e os dois originais');
        for (final d in r.documents) {
          expect(d.versionDate, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
              reason: d.asset);
          expect(d.blocks, isNotEmpty, reason: d.asset);
        }
      });
    }

    test('a copia em ingles e integral', () async {
      // A §3.1(2) pede "a copy of this Agreement": o texto em ingles, inteiro.
      final t = await rootBundle.loadString('assets/legal/gemma_terms_en.md');
      expect(t, contains('Last modified: April 1, 2026'));
      for (final trecho in [
        '3.1 Distribution and Redistribution',
        '3.2 Use Restrictions',
        '3.3 Generated Output',
        '4.2 Trademarks',
        '## Appendix',
      ]) {
        expect(t, contains(trecho));
      }
      final p =
          await rootBundle.loadString('assets/legal/gemma_prohibited_use_en.md');
      expect(p, contains('Last modified: February 21, 2024'));
      expect(
          p,
          contains('Making automated decisions in domains that affect '
              'material or individual rights or well-being'));
    });

    for (final arquivo in ['gemma_terms', 'gemma_prohibited_use']) {
      test('$arquivo: a cortesia diz que o ingles prevalece', () async {
        final pt = (await rootBundle.loadString('assets/legal/${arquivo}_pt.md'))
            .replaceAll(RegExp(r'\s+'), ' ');
        final es = (await rootBundle.loadString('assets/legal/${arquivo}_es.md'))
            .replaceAll(RegExp(r'\s+'), ' ');
        expect(pt, contains('prevalece a versão em inglês'));
        expect(es, contains('prevalece la versión en inglés'));
      });
    }

    for (final (idioma, resumo, clausula, automatizada) in [
      ('pt', '## Resumo dos termos', 'Distribuição e Redistribuição',
          'decisões automatizadas'),
      ('es', '## Resumen de los términos', 'Distribución y Redistribución',
          'decisiones automatizadas'),
    ]) {
      test('o resumo em $idioma resume, e nao traduz, os termos', () async {
        final t =
            await rootBundle.loadString('assets/legal/gemma_terms_$idioma.md');
        expect(t, contains(resumo));
        // Resumo, nao traducao: o titulo da secao contratual traduzido nao
        // aparece. Traduzir o contrato criaria um segundo texto lido como
        // vinculante (mudanca de escopo registrada na #3).
        expect(t.toLowerCase(), isNot(contains(clausula.toLowerCase())));
      });

      test('a Politica em $idioma e traduzida inteira', () async {
        final p = await rootBundle
            .loadString('assets/legal/gemma_prohibited_use_$idioma.md');
        // Os quatro itens de topo, na numeracao do original, e o item 3.4.
        for (final n in ['1.', '2.', '3.', '4.']) {
          expect(
              RegExp('^- ${RegExp.escape(n)} ', multiLine: true).hasMatch(p),
              isTrue,
              reason: 'falta o item $n');
        }
        expect(RegExp(r'^- 3\.4\. ', multiLine: true).hasMatch(p), isTrue);
        expect(p.toLowerCase(), contains(automatizada));
      });
    }

    test('idioma sem traducao recua para pt', () {
      expect(gemmaAssetsFor('fr'), gemmaAssetsFor('pt'));
      expect(gemmaAssetsFor('es').first, contains('_es'));
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
