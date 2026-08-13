/// O kill switch (RF-12) não pode discordar do gate.
///
/// Hoje ele não discorda por construção — chama o mesmo `evaluate()`. Estes
/// testes existem para o dia em que alguém "otimizar" o fallback com uma
/// heurística própria: a divergência aparece aqui, não no aparelho de um
/// usuário em modo degradado.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/content/data/pack_rule_source.dart';
import 'package:guia_ubs/triage/domain/routing_rule.dart';
import 'package:guia_ubs/triage/engine/rule_only_engine.dart';
import 'package:guia_ubs/triage/gate/red_flag_gate.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/in_memory_pack.dart';

/// Todos os tokens citados por alguma regra do pacote.
List<String> _tokensInRules(RuleModel model) {
  final tokens = <String>{};
  for (final rule in model.rules) {
    for (final term in rule.terms) {
      tokens.add(term.tokenId);
    }
  }
  return tokens.toList()..sort();
}

/// Subconjuntos de tamanho 0..3 — cobre toda combinação que uma sessão curta
/// consegue produzir dentro do vocabulário que as regras realmente usam.
Iterable<Set<String>> _subsets(List<String> tokens) sync* {
  yield <String>{};
  for (var i = 0; i < tokens.length; i++) {
    yield {tokens[i]};
    for (var j = i + 1; j < tokens.length; j++) {
      yield {tokens[i], tokens[j]};
      for (var k = j + 1; k < tokens.length; k++) {
        yield {tokens[i], tokens[j], tokens[k]};
      }
    }
  }
}

void main() {
  late Database db;
  late RuleModel model;
  late RuleOnlyEngine engine;

  setUpAll(() {
    db = buildInMemoryPack();
    model = loadRuleModel(db);
    engine = RuleOnlyEngine(model);
  });

  tearDownAll(() => db.dispose());

  test('está sempre disponível — é o piso da escada de degradação', () {
    expect(engine.isAvailable, isTrue);
  });

  test('concorda com o gate em toda combinação de até 3 tokens', () {
    final tokens = _tokensInRules(model);
    expect(tokens, isNotEmpty, reason: 'pacote semente sem termos de regra');

    var checked = 0;
    for (final subset in _subsets(tokens)) {
      final fromGate = evaluate(subset, model);
      final fromEngine = engine.decide(subset);

      expect(
        fromEngine.outcomeId,
        fromGate.outcomeId,
        reason: 'divergência em [${subset.join(' + ')}]',
      );
      expect(fromEngine.severityLevel, fromGate.severityLevel);
      checked++;
    }

    // Guarda contra a varredura silenciosamente virar nada.
    expect(checked, greaterThan(100));
  });

  test('é total: responde para qualquer entrada, inclusive desconhecida', () {
    for (final tokens in <Set<String>>[
      <String>{},
      {'token.que.nao.existe'},
      {'', ' '},
      {'chest', 'pain', 'token.que.nao.existe'},
    ]) {
      final suggestion = engine.decide(tokens);
      expect(suggestion.outcomeId, isNotEmpty);
      expect(model.outcomes.containsKey(suggestion.outcomeId), isTrue,
          reason: 'sugeriu desfecho fora do pacote para [${tokens.join(' + ')}]');
    }
  });

  test('é determinístico entre chamadas', () {
    // Dor torácica: red flag da semente, o caso em que estabilidade importa.
    final tokens = {'chest', 'pain'};
    final first = engine.decide(tokens);

    expect(first.severityLevel, model.maxSeverity,
        reason: 'o fallback precisa reconhecer red flag como o gate reconhece');

    for (var i = 0; i < 20; i++) {
      final again = engine.decide(tokens);
      expect(again.outcomeId, first.outcomeId);
      expect(again.severityLevel, first.severityLevel);
    }
  });

  test('a via assíncrona da interface concorda com a síncrona', () async {
    final tokens = {'chest', 'pain'};

    expect((await engine.infer(tokens))!.outcomeId, engine.decide(tokens).outcomeId);
  });
}
