/// Nenhum texto do app sugere endosso ou vínculo que não existe (ADR-004,
/// ADR-005).
///
/// Três relações que um texto descuidado distorceria:
///
/// * com o **Google**: a §4.2 dos Gemma Terms of Use proíbe sugerir endosso;
/// * com a **UFRR**: o projeto é do Grupo de Pesquisa PRISM (UFRR), em
///   cooperação com o PET-Saúde, ainda em formalização (ADR-005, Decisão 1).
///   A cooperação é declarada, mas a UFRR, como instituição, não responde pelo
///   app. Por isso "UFRR" só aparece onde se identifica quem mantém o app e se
///   diz que apoio institucional não é responsabilidade institucional:
///   [origensQueCitamUfrr]. O logo do Telessaúde na tela "Sobre" é crédito
///   (ADR-004), e o aviso de não afiliação fica ao lado dele;
/// * com o **curso de Medicina**: só citado depois de os colaboradores
///   concordarem, e numa chave própria.
///
/// E uma quarta, que não existe de jeito nenhum: com **unidade de saúde**
/// (ADR-005, Decisão 4). "UBS" e "posto" são categorias de serviço do SUS,
/// conteúdo educativo legítimo; o que se proíbe é ATRIBUIR a uma unidade
/// regra, decisão ou configuração do app. Os padrões frásicos do fim deste
/// arquivo pegam isso, e o corpus prova que eles não pegam o resto.
///
/// As listas abaixo são as ÚNICAS exceções, cada uma com o motivo. Valor novo
/// que cite "Google" ou "Gemma" fora delas reprova: é assim que a lista não
/// envelhece calada.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/ui/more/about_screen.dart';

/// Chaves em que o nome aparece só como TÍTULO de documento ou rótulo.
const Map<String, String> mencaoNeutra = {
  'aboutModelDocuments': 'nomes dos documentos (Notice, Gemma Terms of Use)',
};

/// Arquivos que citam o Google só como a LOJA (ADR-006): quem instala pelo
/// Google Play tem os dados da instalação tratados pela Google, conforme a
/// política dela. Cada "Google" do arquivo precisa estar dentro de uma destas
/// frases; fora delas, reprova. E "Gemma" não entra: o modelo é descrito nos
/// termos, que negam o endosso.
const Map<String, List<String>> mencaoDaLoja = {
  'privacidade_pt.md': [
    'Google Play',
    'pela Google, conforme a política de privacidade dela',
  ],
  'privacidade_es.md': [
    'Google Play',
    'por Google, según su política de privacidad',
  ],
};

/// Chaves e arquivos que FALAM do modelo: precisam negar o endosso.
const Map<String, String> textoDescritivo = {
  'aboutModelCredit': 'credito ao modelo na tela Sobre',
  'termsGateBody': 'resumo do "li e concordo" (Task 4b), tambem falado',
  'termos_pt.md': 'clausula do Gemma nos termos do app (Task 4)',
  'termos_es.md': 'idem, em espanhol',
};

/// Exceção para "UFRR" em qualquer texto: o endereço do projeto o carrega.
const String projectContactEmail = 'prismufrr@gmail.com';

/// Origens que podem citar a UFRR (ADR-005, Decisão 1; RF-16). Fora delas,
/// citar a universidade sugeriria responsabilidade institucional pelo app.
const Map<String, String> origensQueCitamUfrr = {
  'aboutNoAffiliation': 'aviso de nao afiliacao (RF-16): identifica o grupo e '
      'diz que apoio institucional nao e responsabilidade institucional',
  'termos_pt.md': 'identificam o responsavel (grupo PRISM, UFRR)',
  'termos_es.md': 'idem, em espanhol',
  'privacidade_pt.md': 'identifica quem mantem o app e o servidor de conteudo',
  'privacidade_es.md': 'idem, em espanhol',
};

const Map<String, String> negaEndosso = {
  'pt': 'não desenvolveu, não revisou e não endossa',
  'es': 'no desarrolló, no revisó y no respalda',
};

final RegExp _citaModelo = RegExp(r'\b(Google|Gemma)\b');

/// Atribuição de regra, decisão ou configuração do app a uma unidade de saúde
/// (ADR-005, Decisão 4). Padrões do plano de realinhamento (T8a), conferidos
/// contra o corpus no fim deste arquivo.
///
/// O `\b` no fim do grupo de complemento é obrigatório: sem ele, `red` casaria
/// dentro de "redução". "orientação", `permit*` e `habilit*` ficam FORA de
/// propósito: "siga as orientações da sua UBS" e "a UBS permite levar
/// acompanhante" são informação educativa sobre o SUS.
///
/// O `\b` e o `\w` do Dart são ASCII, como os do Python com `re.A`, onde o
/// corpus foi validado: "ã", "ç" e "ó" contam como fronteira de palavra.
final List<RegExp> padroesDeAtribuicao = [
  // (1) regra/decisão/configuração "de/do/da/del/de la" unidade
  RegExp(
      r'\b(regras?|reglas?|decis(ão|ões|ión|iones)|configura(ção|ções|ción|ciones))\s+'
      r'(d[oa]|de|del|de la)\s+(sua\s+|tu\s+|su\s+)?'
      r'(posto|puesto|UBS|unidade|unidad|centro de salud)\b',
      caseSensitive: false),
  // (2) unidade ou administrador que libera/configura/autoriza DADOS, REDE ou
  //     APARELHO, ou que "não tem Wi-Fi": a gestão do aparelho atribuída a uma
  //     unidade
  RegExp(
      r'\b(o|a|el|la)\s+(posto|puesto|UBS|unidade|unidad|administrador)\s+'
      r'(?:(?:liber|configur|autoriz)\w*\b[^.]{0,40}?\b'
      r'(dados|datos|rede|red|aparelho|aparato|celular|downloads?|baixar|descargar|Wi-?Fi)\b'
      r'|não tem Wi-?Fi\b|no tiene Wi-?Fi\b)',
      caseSensitive: false),
  // (3) voz passiva: download/dados/Wi-Fi/aparelho "liberado pelo posto"
  RegExp(
      r'\b(downloads?|descarga|dados móveis|datos móviles|Wi-?Fi|aparelho|aparato)\b'
      r'[^.]{0,30}?\b(liberad|autorizad|configurad|habilitad)\w*\s+'
      r'(pel[oa]|por\s+(el|la))\s+(posto|puesto|UBS|unidade|unidad|administrador)\b',
      caseSensitive: false),
];

/// Casa algum dos [padroesDeAtribuicao]?
bool atribuiAUnidade(String frase) =>
    padroesDeAtribuicao.any((p) => p.hasMatch(frase));

/// Corpus do plano (T8a). Frase nova legítima que reprove entra em
/// [permitidas] E o padrão é corrigido no mesmo PR.
const List<String> permitidas = [
  'Procure o posto de saúde mais próximo.',
  'Siga as orientações da sua UBS.',
  'A UBS costuma atender em horário comercial; confirme na sua.',
  'Leve o cartão do SUS ao posto.',
  'Busque el puesto de salud más cercano.',
  'Siga las orientaciones de su UBS.',
  'A UBS permite levar acompanhante.',
  'A unidade habilita a vacinação sem agendamento.',
  'La unidad permite llevar acompañante.',
  'A UBS autoriza a retirada do remédio por outra pessoa com receita.',
  'A unidade autoriza a redução da dose.',
  'O exame é autorizado pela UBS.',
  'La vacuna es autorizada por la unidad.',
];

const List<String> proibidas = [
  'Orientação das regras do posto',
  'Regras da UBS',
  'Se o posto liberou baixar por dados móveis',
  'Ligue se o posto não tem Wi-Fi',
  'Decisão da unidade',
  'Reglas del puesto',
  'Si el puesto no tiene Wi-Fi',
  'Configuración de la unidad',
  'O administrador configurou o aparelho',
  'Si el puesto autorizó descargar por datos móviles',
  'Download liberado pelo posto',
  'Descarga autorizada por el puesto',
  'A UBS liberou os downloads',
];

/// `(origem, idioma, texto)` de cada valor de ARB e de cada documento legal
/// que não seja do próprio Gemma (os `gemma_*` SÃO os textos do Google).
List<(String, String, String)> textos() {
  final saida = <(String, String, String)>[];
  for (final idioma in ['pt', 'es']) {
    final arb = jsonDecode(File('lib/l10n/app_$idioma.arb').readAsStringSync())
        as Map<String, dynamic>;
    for (final MapEntry(:key, :value) in arb.entries) {
      if (key.startsWith('@') || value is! String) continue;
      saida.add((key, idioma, value));
    }
  }
  for (final f in Directory('assets/legal').listSync().whereType<File>()) {
    final nome = f.uri.pathSegments.last;
    if (nome.startsWith('gemma_') || !nome.endsWith('.md')) continue;
    final idioma = nome.endsWith('_es.md') ? 'es' : 'pt';
    saida.add((nome, idioma, f.readAsStringSync()));
  }
  return saida;
}

/// Problemas de [texto]; vazio quando está tudo certo. Pura, para o próprio
/// guarda poder ser testado com texto em memória.
List<String> problemas(String origem, String idioma, String texto) {
  final plano = texto.replaceAll(RegExp(r'\s+'), ' ');
  final erros = <String>[];
  if (_citaModelo.hasMatch(plano)) {
    if (mencaoNeutra.containsKey(origem)) {
      if (plano.contains('Google') || plano.length > 40) {
        erros.add('$origem e mencao neutra: so o nome do documento, sem '
            '"Google", ate 40 caracteres');
      }
    } else if (mencaoDaLoja.containsKey(origem)) {
      var resto = plano;
      for (final frase in mencaoDaLoja[origem]!) {
        resto = resto.replaceAll(frase, '');
      }
      if (_citaModelo.hasMatch(resto)) {
        erros.add('$origem cita Google/Gemma fora das frases da loja');
      }
    } else if (textoDescritivo.containsKey(origem)) {
      if (!plano.contains(negaEndosso[idioma]!)) {
        erros.add('$origem fala do modelo e nao nega o endosso do Google');
      }
    } else {
      erros.add('$origem cita Google/Gemma fora das listas permitidas');
    }
  }
  final semEmail = plano.replaceAll(projectContactEmail, '');
  if (!origensQueCitamUfrr.containsKey(origem) &&
      RegExp(r'UFRR|Universidade Federal|Universidad Federal',
              caseSensitive: false)
          .hasMatch(semEmail)) {
    erros.add('$origem cita a UFRR fora das origens permitidas: a UFRR nao '
        'responde pelo app (ADR-005)');
  }
  if (RegExp(r'\bMedicina\b').hasMatch(plano) &&
      origem != 'aboutClinicalReviewCredit') {
    erros.add('$origem cita o curso de Medicina fora da chave propria');
  }
  return erros;
}

void main() {
  test('nenhum texto sugere endosso ou vinculo que nao existe', () {
    final todos = [
      for (final (origem, idioma, texto) in textos())
        ...problemas(origem, idioma, texto),
    ];
    expect(todos, isEmpty);
  });

  test('nenhum logotipo do Google na tela Sobre', () {
    expect(aboutLogos.where((l) => l.toLowerCase().contains('google')), isEmpty);
  });

  test('as chaves das listas existem nos dois ARB', () {
    // Exceção para chave que não existe mais é exceção morta: some com ela.
    for (final idioma in ['pt', 'es']) {
      final arb = jsonDecode(File('lib/l10n/app_$idioma.arb').readAsStringSync())
          as Map<String, dynamic>;
      for (final chave in [
        ...mencaoNeutra.keys,
        ...textoDescritivo.keys,
        ...origensQueCitamUfrr.keys,
      ]) {
        if (chave.endsWith('.md')) continue;
        expect(arb, contains(chave), reason: '$chave em app_$idioma.arb');
      }
    }
  });

  group('o proprio guarda', () {
    test('cita o modelo fora das listas: reprova', () {
      expect(problemas('x', 'pt', 'Feito com Gemma'), isNotEmpty);
    });
    test('mencao neutra que vira texto descritivo: reprova', () {
      expect(problemas('aboutModelDocuments', 'pt', 'Em parceria com o Google'),
          isNotEmpty);
    });
    test('mencao da loja fora das frases: reprova; dentro, passa', () {
      expect(problemas('privacidade_pt.md', 'pt', 'Instale pelo Google Play.'),
          isEmpty);
      expect(problemas('privacidade_pt.md', 'pt', 'Feito com o Google.'),
          isNotEmpty);
      expect(problemas('privacidade_pt.md', 'pt', 'Usa o Gemma.'), isNotEmpty);
    });
    test('texto descritivo sem negar o endosso: reprova', () {
      expect(problemas('aboutModelCredit', 'pt', 'Usa o Gemma, do Google.'),
          isNotEmpty);
    });
    test('UFRR fora do e-mail e das origens permitidas: reprova', () {
      expect(problemas('x', 'pt', 'grupo da UFRR'), isNotEmpty);
      expect(problemas('termsGateBody', 'pt', 'grupo da UFRR'), isNotEmpty);
      expect(problemas('x', 'pt', 'Contato: $projectContactEmail'), isEmpty);
    });
    test('UFRR nas origens permitidas: passa', () {
      for (final origem in origensQueCitamUfrr.keys) {
        expect(problemas(origem, 'pt', 'Grupo de Pesquisa PRISM (UFRR)'),
            isEmpty,
            reason: origem);
      }
    });
    test('Medicina fora da chave propria: reprova', () {
      expect(problemas('x', 'pt', 'revisado pelo curso de Medicina'), isNotEmpty);
    });
  });

  test('nenhum texto atribui regra, decisao ou configuracao a posto ou '
      'unidade', () {
    final achados = [
      for (final (origem, _, texto) in textos())
        for (final p in padroesDeAtribuicao)
          if (p.firstMatch(texto.replaceAll(RegExp(r'\s+'), ' '))
              case final m?)
            '$origem: "${m[0]}"',
    ];
    expect(achados, isEmpty);
  });

  test('padroes frasicos: permitidas passam, proibidas reprovam', () {
    expect([for (final f in permitidas) if (atribuiAUnidade(f)) f], isEmpty,
        reason: 'frase educativa legitima reprovada');
    expect([for (final f in proibidas) if (!atribuiAUnidade(f)) f], isEmpty,
        reason: 'atribuicao a unidade que passou');
  });
}
