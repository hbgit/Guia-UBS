/// Leitura dos documentos legais embarcados no APK.
///
/// ## Por que embarcados, e não um link
///
/// Um app offline-only que manda a pessoa "consultar a política no site" não
/// tem política nenhuma para o público que ele existe para atender. Os quatro
/// arquivos vivem em `assets/legal/` e abrem com o rádio desligado.
///
/// ## A data da versão vem do texto, não do arquivo
///
/// Cada documento começa com `<!-- versao: AAAA-MM-DD -->`. Usar a data de
/// modificação do arquivo seria mais cômodo e estaria errado: mtime não
/// sobrevive ao empacotamento de forma determinística — é a mesma razão pela
/// qual o packer exige `SOURCE_DATE_EPOCH`. Duas builds do mesmo texto
/// mostrariam datas diferentes ao titular.
///
/// Documento sem essa linha é defeito, não caso a tratar: [parseLegalDocument]
/// devolve `versionDate` nulo e o teste reprova.
///
/// ## O "markdown" aqui é mínimo de propósito
///
/// Títulos, parágrafos e listas — só isso, porque só isso os documentos usam.
/// Uma dependência de renderizador de markdown completo custaria um pacote e
/// uma superfície inteira de tratamento de texto para formatar quatro arquivos
/// que este próprio repositório escreve.
library;

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// Um pedaço de documento já classificado para virar widget.
enum LegalBlockKind { title, heading, paragraph, bullet }

class LegalBlock {
  const LegalBlock(this.kind, this.text);

  final LegalBlockKind kind;
  final String text;
}

/// Um documento embarcado, pronto para a tela.
class LegalDocument {
  const LegalDocument({
    required this.asset,
    required this.versionDate,
    required this.blocks,
  });

  final String asset;

  /// `AAAA-MM-DD` como veio do arquivo, ou `null` se o cabeçalho faltou.
  final String? versionDate;

  final List<LegalBlock> blocks;

  /// Data em `DD/MM/AAAA`, formato que o público lê. Devolve `null` quando a
  /// data está ausente ou malformada — a tela então omite a linha, em vez de
  /// mostrar uma data inventada.
  String? get displayDate {
    final raw = versionDate;
    if (raw == null) return null;
    final parts = raw.split('-');
    if (parts.length != 3) return null;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }
}

final RegExp _versionHeader =
    RegExp(r'^<!--\s*versao:\s*(\d{4}-\d{2}-\d{2})\s*-->$');

/// Converte o texto de um `.md` embarcado em blocos.
LegalDocument parseLegalDocument(String asset, String source) {
  String? version;
  final blocks = <LegalBlock>[];
  final paragraph = StringBuffer();

  void flushParagraph() {
    final text = paragraph.toString().trim();
    if (text.isNotEmpty) {
      blocks.add(LegalBlock(LegalBlockKind.paragraph, text));
    }
    paragraph.clear();
  }

  for (final line in source.split('\n')) {
    final trimmed = line.trim();

    final header = _versionHeader.firstMatch(trimmed);
    if (header != null) {
      version = header.group(1);
      continue;
    }
    // Qualquer outro comentário HTML é anotação de quem escreve o documento e
    // não deve chegar ao leitor.
    if (trimmed.startsWith('<!--')) continue;

    if (trimmed.isEmpty) {
      flushParagraph();
      continue;
    }
    if (trimmed.startsWith('## ')) {
      flushParagraph();
      blocks.add(LegalBlock(LegalBlockKind.heading, trimmed.substring(3)));
      continue;
    }
    if (trimmed.startsWith('# ')) {
      flushParagraph();
      blocks.add(LegalBlock(LegalBlockKind.title, trimmed.substring(2)));
      continue;
    }
    if (trimmed.startsWith('- ')) {
      flushParagraph();
      blocks.add(LegalBlock(LegalBlockKind.bullet, trimmed.substring(2)));
      continue;
    }
    // Linha solta continua o parágrafo: os arquivos quebram em 80 colunas, e
    // respeitar essa quebra na tela produziria linhas cortadas no meio.
    if (paragraph.isNotEmpty) paragraph.write(' ');
    paragraph.write(trimmed);
  }
  flushParagraph();

  return LegalDocument(asset: asset, versionDate: version, blocks: blocks);
}

/// Os dois documentos do idioma pedido, na ordem em que a tela os mostra.
///
/// Idioma sem tradução recua para `pt` — mesma regra do conteúdo clínico
/// (`Localized.isFallback`): sumir com o aviso de privacidade de quem precisa
/// dele é pior que mostrá-lo em português.
List<String> legalAssetsFor(String languageCode) {
  const traduzidos = {'pt', 'es'};
  final code = traduzidos.contains(languageCode) ? languageCode : 'pt';
  return ['assets/legal/privacidade_$code.md', 'assets/legal/termos_$code.md'];
}

/// Carrega e converte. **Nunca lança:** asset faltando devolve lista vazia, e
/// a tela mostra que não conseguiu abrir. A INV-8 vale aqui como em todo o
/// resto, e uma exceção no meio de uma tela legal seria o pior lugar.
Future<List<LegalDocument>> loadLegalDocuments(
  String languageCode, {
  AssetBundle? bundle,
}) async {
  final source = bundle ?? rootBundle;
  final documents = <LegalDocument>[];

  for (final asset in legalAssetsFor(languageCode)) {
    try {
      documents.add(parseLegalDocument(asset, await source.loadString(asset)));
    } on Object {
      // Um documento ilegível não pode esconder o outro.
      continue;
    }
  }
  return documents;
}
