/// A página pública da política e dos termos (`spec/implantacao.md` §2.9).
///
/// Três condições do dono do projeto: o texto servido é o MESMO arquivo que o
/// app embarca, não uma cópia; a página mostra a versão e a data, as mesmas
/// do `termsVersion`; e nada de analytics nem recurso de outro domínio.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/legal/legal_text.dart';
import 'package:guia_ubs/legal/terms.dart';

import '../../tool/legal_pages.dart';

void main() {
  late Directory out;

  setUp(() => out = Directory.systemTemp.createTempSync('gubs_pages_'));
  tearDown(() => out.deleteSync(recursive: true));

  group('renderLegalPage', () {
    final doc = parseLegalDocument('x.md', '''
<!-- versao: 2026-11-02 -->
# Política de privacidade

<!-- anotacao de quem escreve -->
## O que fica no aparelho

Linha um do parágrafo
continua aqui, com <tag> & "aspas".

- item da lista
''');

    String page() => renderLegalPage(doc,
        lang: 'pt', otherLanguageHref: 'es/', otherLanguageLabel: 'Español');

    test('mostra a versao e a data, as do proprio arquivo', () {
      expect(page(), contains('2026-11-02'));
      expect(page(), contains('02/11/2026'));
    });

    test('todo bloco do documento aparece, escapado, sem markdown novo', () {
      final html = page();
      expect(html, contains('<h1>Política de privacidade</h1>'));
      expect(html, contains('<h2>O que fica no aparelho</h2>'));
      expect(
          html,
          contains('<p>Linha um do parágrafo continua aqui, com &lt;tag&gt; '
              '&amp; &quot;aspas&quot;.</p>'));
      expect(html, contains('<li>item da lista</li>'));
      expect(html, isNot(contains('anotacao de quem escreve')));
    });

    test('nenhum recurso de outro dominio e nenhum script', () {
      final html = page();
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('<link')));
      expect(html, isNot(contains('<img')));
      expect(html, isNot(contains('src=')));
      expect(html, isNot(contains('@import')));
      // A CSP fecha a porta para qualquer edicao futura que tente carregar
      // algo de fora: o navegador recusa, mesmo que o teste deixe passar. A
      // diretiva e EXATAMENTE esta: sem o `style-src 'unsafe-inline'`, o
      // navegador descarta o <style> e a pagina sai em texto cru; com algo
      // a mais, abre porta para recurso externo.
      expect(
          html,
          contains('<meta http-equiv="Content-Security-Policy" '
              "content=\"default-src 'none'; style-src 'unsafe-inline'\">"));
    });

    test('lang do documento e link para o outro idioma', () {
      final html = page();
      expect(html, contains('<html lang="pt-BR">'));
      expect(html, contains('href="es/"'));
    });
  });

  group('buildLegalSite', () {
    // https://guiasaude.prismrr.com.br/ (§2.9): um subdominio por projeto, e
    // o apex reservado ao grupo. As paginas ficam na RAIZ do site.
    test('publica os quatro documentos e a pagina inicial, nos caminhos da §2.9',
        () {
      buildLegalSite(legalDir: Directory('assets/legal'), out: out);

      for (final caminho in [
        'index.html',
        'privacidade/index.html',
        'termos/index.html',
        'es/privacidade/index.html',
        'es/termos/index.html',
      ]) {
        expect(File('${out.path}/$caminho').existsSync(), isTrue,
            reason: caminho);
      }
    });

    test('a pagina dos termos e o arquivo do app tem a mesma versao, a do '
        'termsVersion', () {
      buildLegalSite(legalDir: Directory('assets/legal'), out: out);

      for (final idioma in ['pt', 'es']) {
        final arquivo = File('assets/legal/termos_$idioma.md').readAsStringSync();
        final doc = parseLegalDocument('termos_$idioma.md', arquivo);
        expect(doc.versionDate, termsVersion);

        final caminho =
            idioma == 'pt' ? 'termos/index.html' : 'es/termos/index.html';
        final html = File('${out.path}/$caminho').readAsStringSync();
        expect(html, contains(termsVersion), reason: caminho);
        // O MESMO texto: cada bloco do arquivo do app esta na pagina.
        for (final bloco in doc.blocks) {
          expect(html, contains(htmlEscape(bloco.text)), reason: bloco.text);
        }
      }
    });

    test('a pagina inicial diz o que o projeto e e aponta para as quatro, '
        'com a mesma CSP e sem nada de fora', () {
      buildLegalSite(legalDir: Directory('assets/legal'), out: out);
      final html = File('${out.path}/index.html').readAsStringSync();

      expect(html, contains('projeto educativo'));
      expect(html, contains('não é serviço de saúde'));
      for (final href in [
        'privacidade/',
        'termos/',
        'es/privacidade/',
        'es/termos/',
      ]) {
        expect(html, contains('href="$href"'), reason: href);
      }
      expect(
          html,
          contains('<meta http-equiv="Content-Security-Policy" '
              "content=\"default-src 'none'; style-src 'unsafe-inline'\">"));
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('src=')));
    });

    test('o link de idioma de cada documento leva ao outro idioma', () {
      buildLegalSite(legalDir: Directory('assets/legal'), out: out);
      // Relativos, para funcionarem em qualquer host e no preview do PR.
      expect(File('${out.path}/privacidade/index.html').readAsStringSync(),
          contains('href="../es/privacidade/"'));
      expect(File('${out.path}/es/privacidade/index.html').readAsStringSync(),
          contains('href="../../privacidade/"'));
    });

    test('documento sem versao reprova, em vez de publicar sem data', () {
      final legal = Directory('${out.path}/legal')..createSync();
      for (final nome in [
        'privacidade_pt.md',
        'privacidade_es.md',
        'termos_pt.md',
        'termos_es.md',
      ]) {
        File('${legal.path}/$nome').writeAsStringSync(
            nome == 'privacidade_es.md'
                ? '# Sem versao\n'
                : '<!-- versao: $termsVersion -->\n# Doc\n');
      }
      expect(
          () => buildLegalSite(
              legalDir: legal, out: Directory('${out.path}/site')),
          throwsA(isA<LegalPagesException>()
              .having((e) => e.message, 'message', contains('privacidade_es'))));
    });

    test('termos com versao diferente do termsVersion reprovam', () {
      final legal = Directory('${out.path}/legal')..createSync();
      for (final nome in [
        'privacidade_pt.md',
        'privacidade_es.md',
        'termos_pt.md',
        'termos_es.md',
      ]) {
        File('${legal.path}/$nome').writeAsStringSync(nome == 'termos_pt.md'
            ? '<!-- versao: 2000-01-01 -->\n# Doc\n'
            : '<!-- versao: $termsVersion -->\n# Doc\n');
      }
      expect(
          () => buildLegalSite(
              legalDir: legal, out: Directory('${out.path}/site')),
          throwsA(isA<LegalPagesException>()
              .having((e) => e.message, 'message', contains('termsVersion'))));
    });
  });
}
