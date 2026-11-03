/// Gera a página pública da política de privacidade e dos termos de uso
/// (`spec/implantacao.md` §2.9), a partir dos MESMOS arquivos que o app
/// embarca em `assets/legal/`.
///
/// ```sh
/// dart run tool/legal_pages.dart --out _site
/// ```
///
/// Saídas, servidas pelo GitHub Pages em `https://prismrr.com.br/`:
///
/// | caminho | arquivo do app |
/// |---|---|
/// | `guiasaude/privacidade/` | `privacidade_pt.md` |
/// | `guiasaude/privacidade/es/` | `privacidade_es.md` |
/// | `guiasaude/termos/` | `termos_pt.md` |
/// | `guiasaude/termos/es/` | `termos_es.md` |
///
/// Três regras do dono do projeto (2026-11-03):
///
/// * **Mesmo texto, não cópia.** O parser é o do app
///   (`lib/legal/legal_text.dart`), e a página só escapa o texto. Se o app
///   mostra `**`, a página também mostra: as duas não podem divergir.
/// * **Versão e data visíveis**, as mesmas do `<!-- versao -->`. A dos termos
///   tem de ser a do `termsVersion`; documento sem versão reprova.
/// * **Nada de analytics nem recurso de outro domínio.** Nenhum script, nenhuma
///   fonte externa, nenhuma imagem; CSS inline; e uma CSP `default-src 'none'`
///   para que o navegador recuse o que uma edição futura tentar carregar.
///
/// Saída: 0 ok; 1 documento reprovado; 64 uso.
library;

import 'dart:io';

import 'package:guia_ubs/legal/legal_text.dart';
import 'package:guia_ubs/legal/terms.dart';

class LegalPagesException implements Exception {
  const LegalPagesException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Escapa texto para HTML. É a ÚNICA transformação que o texto sofre.
String htmlEscape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

const String _css = '''
:root{color-scheme:light dark;--ink:#16221d;--soft:#4a5a53;--bg:#f4f7f5;--line:#d5ded9}
@media (prefers-color-scheme:dark){:root{--ink:#e6eee9;--soft:#a9b8b0;--bg:#121a16;--line:#2c3a33}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:1.0625rem/1.6 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:44rem;margin:0 auto;padding:2rem 1rem 4rem}
h1{font-size:1.75rem;line-height:1.25;margin:0 0 .5rem}
h2{font-size:1.2rem;margin:2rem 0 .5rem}
p,li{margin:0 0 .9rem}
ul{padding-left:1.25rem}
.versao{color:var(--soft);border-bottom:1px solid var(--line);padding-bottom:1rem;margin-bottom:1.5rem}
nav{margin-bottom:1rem}
a{color:inherit}
footer{color:var(--soft);font-size:.9rem;border-top:1px solid var(--line);margin-top:2.5rem;padding-top:1rem}
''';

/// Uma página de um documento legal. [lang] é `pt` ou `es`.
String renderLegalPage(
  LegalDocument doc, {
  required String lang,
  required String otherLanguageHref,
  required String otherLanguageLabel,
}) {
  final title = doc.blocks
          .where((b) => b.kind == LegalBlockKind.title)
          .map((b) => b.text)
          .firstOrNull ??
      'Guia UBS';
  final pt = lang == 'pt';
  final b = StringBuffer()
    ..writeln('<!doctype html>')
    ..writeln('<html lang="${pt ? 'pt-BR' : 'es'}">')
    ..writeln('<head>')
    ..writeln('<meta charset="utf-8">')
    ..writeln('<meta name="viewport" content="width=device-width, '
        'initial-scale=1">')
    ..writeln('<meta http-equiv="Content-Security-Policy" '
        "content=\"default-src 'none'; style-src 'unsafe-inline'\">")
    ..writeln('<meta name="referrer" content="no-referrer">')
    ..writeln('<title>${htmlEscape(title)} · Guia UBS</title>')
    ..writeln('<style>$_css</style>')
    ..writeln('</head>')
    ..writeln('<body>')
    ..writeln('<main>')
    ..writeln('<nav><a href="$otherLanguageHref" hreflang="${pt ? 'es' : 'pt-BR'}">'
        '${htmlEscape(otherLanguageLabel)}</a></nav>');

  var emLista = false;
  var tituloEscrito = false;
  for (final block in doc.blocks) {
    if (block.kind != LegalBlockKind.bullet && emLista) {
      b.writeln('</ul>');
      emLista = false;
    }
    final t = htmlEscape(block.text);
    switch (block.kind) {
      case LegalBlockKind.title:
        b.writeln('<h1>$t</h1>');
        if (!tituloEscrito) {
          b.writeln('<p class="versao">${pt ? 'Versão de' : 'Versión del'} '
              '${doc.displayDate} (<code>${doc.versionDate}</code>). '
              '${pt ? 'É o mesmo texto que o aplicativo mostra.' : 'Es el mismo texto que muestra la aplicación.'}'
              '</p>');
          tituloEscrito = true;
        }
      case LegalBlockKind.heading:
        b.writeln('<h2>$t</h2>');
      case LegalBlockKind.paragraph:
        b.writeln('<p>$t</p>');
      case LegalBlockKind.bullet:
        if (!emLista) {
          b.writeln('<ul>');
          emLista = true;
        }
        b.writeln('<li>$t</li>');
    }
  }
  if (emLista) b.writeln('</ul>');
  b
    ..writeln('<footer>${pt ? 'Guia UBS · projeto educativo aberto do Grupo de '
            'Pesquisa PRISM (UFRR). Esta página não usa cookies, scripts nem '
            'rastreamento.' : 'Guia UBS · proyecto educativo abierto del Grupo de '
            'Investigación PRISM (UFRR). Esta página no usa cookies, scripts ni '
            'rastreo.'}</footer>')
    ..writeln('</main>')
    ..writeln('</body>')
    ..writeln('</html>');
  return b.toString();
}

/// Lê os quatro documentos de [legalDir] e escreve o site em [out].
///
/// Lança [LegalPagesException] se um documento não tiver versão, ou se a dos
/// termos não for o [termsVersion]: publicar uma política sem data, ou com
/// data diferente da que o app mostra, é pior que não publicar.
void buildLegalSite({required Directory legalDir, required Directory out}) {
  const paginas = [
    ('privacidade', 'pt', 'guiasaude/privacidade', 'es/', 'Español'),
    ('privacidade', 'es', 'guiasaude/privacidade/es', '../', 'Português'),
    ('termos', 'pt', 'guiasaude/termos', 'es/', 'Español'),
    ('termos', 'es', 'guiasaude/termos/es', '../', 'Português'),
  ];
  final renderizadas = <String, String>{};
  for (final (nome, lang, caminho, outro, rotulo) in paginas) {
    final arquivo = '${nome}_$lang.md';
    final fonte = File('${legalDir.path}/$arquivo');
    if (!fonte.existsSync()) {
      throw LegalPagesException('$arquivo nao existe em ${legalDir.path}');
    }
    final doc = parseLegalDocument(arquivo, fonte.readAsStringSync());
    if (doc.versionDate == null) {
      throw LegalPagesException(
          '$arquivo sem "<!-- versao: AAAA-MM-DD -->": a pagina publica a data');
    }
    if (nome == 'termos' && doc.versionDate != termsVersion) {
      throw LegalPagesException('$arquivo tem versao ${doc.versionDate}, mas o '
          'termsVersion do app e $termsVersion: a pagina e o app divergiriam');
    }
    renderizadas[caminho] = renderLegalPage(doc,
        lang: lang, otherLanguageHref: outro, otherLanguageLabel: rotulo);
  }
  // So escreve depois de tudo validado: nada de site pela metade.
  for (final MapEntry(key: caminho, value: html) in renderizadas.entries) {
    final destino = File('${out.path}/$caminho/index.html');
    destino.parent.createSync(recursive: true);
    destino.writeAsStringSync(html);
  }
}

void main(List<String> args) {
  final i = args.indexOf('--out');
  if (i < 0 || i + 1 >= args.length) {
    stderr.writeln('uso: dart run tool/legal_pages.dart --out <diretorio>');
    exit(64);
  }
  try {
    buildLegalSite(
        legalDir: Directory('assets/legal'), out: Directory(args[i + 1]));
  } on LegalPagesException catch (e) {
    stderr.writeln('FALHOU  $e');
    exit(1);
  }
  stdout.writeln('ok: politica e termos em ${args[i + 1]}/guiasaude/');
}
