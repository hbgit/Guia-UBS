/// O parser dos documentos legais embarcados, sem Flutter.
///
/// Mora aqui, e não em `ui/more/legal_document.dart`, para que a MESMA função
/// que monta a tela do app monte a página pública da política e dos termos
/// (`tool/legal_pages.dart`, `spec/implantacao.md` §2.9). Duas implementações
/// do mesmo texto acabariam mostrando coisas diferentes ao titular.
///
/// O "markdown" é mínimo de propósito: título, subtítulo, parágrafo e item.
/// Ver `ui/more/legal_document.dart` para o porquê.
library;

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

