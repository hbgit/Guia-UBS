/// Testes unitários do gate. Espelham `packer/test/packer.test.ts`: qualquer
/// divergência de comportamento entre as duas implementações aparece aqui ou
/// no teste golden, nunca em produção.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/triage/domain/routing_rule.dart';
import 'package:guia_ubs/triage/gate/red_flag_gate.dart';

final _outcomes = <String, RoutingOutcome>{
  'ROUTINE_UBS': const RoutingOutcome(id: 'ROUTINE_UBS', severityLevel: 10),
  'EMERGENCY': const RoutingOutcome(id: 'EMERGENCY', severityLevel: 100),
};

RoutingRule _rule(
  String id,
  int priority,
  String outcomeId,
  List<(int, String, bool)> terms,
) {
  return RoutingRule(
    id: id,
    priority: priority,
    outcomeId: outcomeId,
    terms: [
      for (final (groupNo, tokenId, negated) in terms)
        RuleTerm(groupNo: groupNo, tokenId: tokenId, negated: negated),
    ],
  );
}

RuleModel _model(List<RoutingRule> rules) => RuleModel(
      rules: rules,
      outcomes: _outcomes,
      defaultOutcomeId: 'ROUTINE_UBS',
    );

void main() {
  group('ruleMatches', () {
    test('termos do mesmo grupo são conjunção (E)', () {
      final r = _rule('r', 10, 'EMERGENCY', [
        (0, 'chest', false),
        (0, 'pain', false),
      ]);
      expect(ruleMatches(r, {'chest', 'pain'}), isTrue);
      expect(ruleMatches(r, {'chest'}), isFalse);
      expect(ruleMatches(r, {'pain'}), isFalse);
    });

    test('grupos distintos são disjunção (OU)', () {
      final r = _rule('r', 10, 'EMERGENCY', [
        (0, 'bleeding', false),
        (0, 'severe', false),
        (1, 'bleeding', false),
        (1, 'pregnant', false),
      ]);
      expect(ruleMatches(r, {'bleeding', 'severe'}), isTrue);
      expect(ruleMatches(r, {'bleeding', 'pregnant'}), isTrue);
      expect(ruleMatches(r, {'bleeding'}), isFalse);
    });

    test('termo negado exige ausência do token', () {
      final r = _rule('r', 100, 'ROUTINE_UBS', [
        (0, 'head', false),
        (0, 'pain', false),
        (0, 'sudden', true),
      ]);
      expect(ruleMatches(r, {'head', 'pain'}), isTrue);
      expect(ruleMatches(r, {'head', 'pain', 'sudden'}), isFalse);
    });

    test('regra sem termos nunca dispara', () {
      expect(ruleMatches(_rule('vazia', 1, 'EMERGENCY', []), {'qualquer'}), isFalse);
    });
  });

  group('evaluate', () {
    test('maior severidade vence mesmo com prioridade pior — INV-1 estrutural', () {
      // Erro de autoria: regra de rotina com a MENOR prioridade possível.
      final model = _model([
        _rule('rotina.prioritaria', 1, 'ROUTINE_UBS', [(0, 'chest', false)]),
        _rule('red.flag', 999, 'EMERGENCY', [
          (0, 'chest', false),
          (0, 'pain', false),
        ]),
      ]);
      final verdict = evaluate({'chest', 'pain'}, model);
      expect(
        verdict.outcomeId,
        'EMERGENCY',
        reason: 'nenhuma prioridade pode rebaixar uma red flag',
      );
      expect(isRedFlag(verdict, model), isTrue);
    });

    test('prioridade desempata dentro do mesmo nível de severidade', () {
      final model = _model([
        _rule('a', 50, 'ROUTINE_UBS', [(0, 'fever', false)]),
        _rule('b', 10, 'ROUTINE_UBS', [(0, 'fever', false)]),
      ]);
      expect(evaluate({'fever'}, model).matchedRuleId, 'b');
    });

    test('sem regra correspondente assume o desfecho padrão — nunca silêncio', () {
      final verdict = evaluate({'desconhecido'}, _model([]));
      expect(verdict.outcomeId, 'ROUTINE_UBS');
      expect(verdict.matchedRuleId, isNull);
    });

    test('conjunto vazio de tokens ainda produz orientação', () {
      expect(evaluate(<String>{}, _model([])).outcomeId, 'ROUTINE_UBS');
    });

    test('desfecho padrão inexistente falha ruidosamente', () {
      final model = RuleModel(
        rules: const [],
        outcomes: _outcomes,
        defaultOutcomeId: 'NAO_EXISTE',
      );
      expect(() => evaluate(<String>{}, model), throwsStateError);
    });

    test('token desconhecido não altera o resultado de uma red flag', () {
      final model = _model([
        _rule('red.flag', 10, 'EMERGENCY', [
          (0, 'chest', false),
          (0, 'pain', false),
        ]),
      ]);
      expect(evaluate({'chest', 'pain', 'token_inventado'}, model).outcomeId, 'EMERGENCY');
    });
  });
}
