/// Leitura dos documentos legais embarcados no APK.
///
/// ## Por que embarcados, e não um link
///
/// Um app offline-only que manda a pessoa "consultar a política no site" não
/// tem política nenhuma para o público que ele existe para atender. Os onze
/// arquivos vivem em `assets/legal/` e abrem com o rádio desligado: privacidade
/// e termos em pt/es, e os documentos do Gemma (ADR-004).
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

import '../../legal/legal_text.dart';

export '../../legal/legal_text.dart';
export '../../legal/terms.dart';

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


/// O arquivo "Notice" que a §3.1(4) dos Gemma Terms of Use exige, literal e em
/// inglês (ADR-004). Não tem cabeçalho de versão: é o texto que os termos
/// pedem, e ele não muda.
const String gemmaNoticeAsset = 'assets/legal/gemma_notice.txt';

/// A primeira linha de [gemmaNoticeAsset], para os portões que não podem
/// esperar uma leitura de asset (onboarding, "li e concordo"). Um teste
/// confere que é idêntica à do arquivo.
const String gemmaNoticeLine = 'Gemma is provided under and subject to the '
    'Gemma Terms of Use found at gemma.ai/resources/terms';

/// Os documentos do Gemma, na ordem da tela: o resumo e a Política traduzidos
/// (cortesia), depois os dois originais em inglês, que são os que valem.
///
/// Mesmo recuo para `pt` de [legalAssetsFor].
List<String> gemmaAssetsFor(String languageCode) {
  const traduzidos = {'pt', 'es'};
  final code = traduzidos.contains(languageCode) ? languageCode : 'pt';
  return [
    'assets/legal/gemma_terms_$code.md',
    'assets/legal/gemma_prohibited_use_$code.md',
    'assets/legal/gemma_terms_en.md',
    'assets/legal/gemma_prohibited_use_en.md',
  ];
}

/// O Notice e os documentos do Gemma, prontos para a tela.
typedef GemmaDocuments = ({String notice, List<LegalDocument> documents});

/// Carrega e converte. **Nunca lança**, como [loadLegalDocuments]: Notice
/// ausente vira `''` e documento ilegível some da lista, sem esconder os outros.
Future<GemmaDocuments> loadGemmaDocuments(
  String languageCode, {
  AssetBundle? bundle,
}) async {
  final source = bundle ?? rootBundle;
  var notice = '';
  try {
    notice = (await source.loadString(gemmaNoticeAsset)).trim();
  } on Object {
    // A tela mostra que não conseguiu abrir.
  }
  final documents = <LegalDocument>[];
  for (final asset in gemmaAssetsFor(languageCode)) {
    try {
      documents.add(parseLegalDocument(asset, await source.loadString(asset)));
    } on Object {
      continue;
    }
  }
  return (notice: notice, documents: documents);
}
