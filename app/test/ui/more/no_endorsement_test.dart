/// Nenhum texto do app sugere endosso ou vínculo que não existe (ADR-004).
///
/// Três relações que o app NÃO tem, e que um texto descuidado sugeriria:
///
/// * com o **Google**: a §4.2 dos Gemma Terms of Use proíbe sugerir endosso;
/// * com a **UFRR**: o projeto é do grupo PRISM, sem vínculo formal (o logo do
///   PET Telessaúde na tela "Sobre" é crédito, decidido no ADR-004);
/// * com o **curso de Medicina**: só citado depois de os colaboradores
///   concordarem, e numa chave própria.
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

/// Chaves e arquivos que FALAM do modelo: precisam negar o endosso.
const Map<String, String> textoDescritivo = {
  'aboutModelCredit': 'credito ao modelo na tela Sobre',
  'termsGateBody': 'resumo do "li e concordo" (Task 4b), tambem falado',
  'termos_pt.md': 'clausula do Gemma nos termos do app (Task 4)',
  'termos_es.md': 'idem, em espanhol',
};

/// Única exceção nomeada para "UFRR": o endereço do projeto o carrega.
const String projectContactEmail = 'prismufrr@gmail.com';

const Map<String, String> negaEndosso = {
  'pt': 'não desenvolveu, não revisou e não endossa',
  'es': 'no desarrolló, no revisó y no respalda',
};

final RegExp _citaModelo = RegExp(r'\b(Google|Gemma)\b');

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
    } else if (textoDescritivo.containsKey(origem)) {
      if (!plano.contains(negaEndosso[idioma]!)) {
        erros.add('$origem fala do modelo e nao nega o endosso do Google');
      }
    } else {
      erros.add('$origem cita Google/Gemma fora das listas permitidas');
    }
  }
  final semEmail = plano.replaceAll(projectContactEmail, '');
  if (RegExp(r'UFRR|Universidade Federal|Universidad Federal',
          caseSensitive: false)
      .hasMatch(semEmail)) {
    erros.add('$origem cita a UFRR: o projeto nao tem vinculo formal');
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
      for (final chave in [...mencaoNeutra.keys, ...textoDescritivo.keys]) {
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
    test('texto descritivo sem negar o endosso: reprova', () {
      expect(problemas('aboutModelCredit', 'pt', 'Usa o Gemma, do Google.'),
          isNotEmpty);
    });
    test('UFRR fora do e-mail: reprova; no e-mail, passa', () {
      expect(problemas('x', 'pt', 'grupo da UFRR'), isNotEmpty);
      expect(problemas('x', 'pt', 'Contato: $projectContactEmail'), isEmpty);
    });
    test('Medicina fora da chave propria: reprova', () {
      expect(problemas('x', 'pt', 'revisado pelo curso de Medicina'), isNotEmpty);
    });
  });
}
