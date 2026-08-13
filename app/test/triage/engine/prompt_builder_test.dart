/// O prompt precisa ser função dos tokens, não da ordem em que o usuário tocou
/// nos ícones.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/triage/domain/routing_rule.dart';
import 'package:guia_ubs/triage/engine/prompt_builder.dart';

RuleModel _model(Map<String, int> outcomes) => RuleModel(
      rules: const [],
      outcomes: {
        for (final entry in outcomes.entries)
          entry.key: RoutingOutcome(id: entry.key, severityLevel: entry.value),
      },
      defaultOutcomeId: outcomes.keys.first,
    );

final _seedLike = _model({'ROUTINE_UBS': 10, 'EMERGENCY': 100});

void main() {
  group('buildTriagePrompt', () {
    test('a ordem dos toques não muda o prompt', () {
      // `Set` preserva ordem de inserção: sem ordenação explícita, tocar
      // "peito" antes de "dor" produziria outro prompt — e possivelmente outra
      // resposta — para a mesma queixa.
      final a = buildTriagePrompt({'sym.chest', 'sym.pain', 'sym.fever'}, _seedLike);
      final b = buildTriagePrompt({'sym.fever', 'sym.chest', 'sym.pain'}, _seedLike);
      final c = buildTriagePrompt({'sym.pain', 'sym.fever', 'sym.chest'}, _seedLike);

      expect(a, b);
      expect(b, c);
    });

    test('mesma entrada, mesma saída em chamadas repetidas', () {
      final tokens = {'sym.chest', 'sym.pain'};

      expect(
        buildTriagePrompt(tokens, _seedLike),
        buildTriagePrompt(tokens, _seedLike),
      );
    });

    test('a ordem dos desfechos no pacote também é normalizada', () {
      final invertido = _model({'EMERGENCY': 100, 'ROUTINE_UBS': 10});

      expect(
        buildTriagePrompt({'sym.pain'}, _seedLike),
        buildTriagePrompt({'sym.pain'}, invertido),
      );
    });

    test('todos os identificadores do pacote entram na lista permitida', () {
      final prompt = buildTriagePrompt({'sym.pain'}, _seedLike);

      expect(prompt, contains('ROUTINE_UBS'));
      expect(prompt, contains('EMERGENCY'));
    });

    test('excesso de tokens é truncado no teto da sessão', () {
      final excesso = <String>{
        for (var i = 0; i < maxSessionTokens + 4; i++) 'sym.t$i',
      };

      final prompt = buildTriagePrompt(excesso, _seedLike);
      final sinais = RegExp(r'^- sym\.', multiLine: true).allMatches(prompt).length;

      expect(sinais, maxSessionTokens);
    });

    test('sessão vazia ainda produz um prompt válido', () {
      expect(buildTriagePrompt(<String>{}, _seedLike), contains('EMERGENCY'));
    });

    test('estouro do orçamento de contexto falha alto', () {
      // Um catálogo grande demais degradaria a latência p95 em silêncio; aqui
      // ele quebra o teste em vez de quebrar o RNF-02 em campo.
      final inchado = _model({
        for (var i = 0; i < 100; i++) 'DESFECHO_MUITO_LONGO_NUMERO_$i': i,
      });

      expect(() => buildTriagePrompt({'sym.pain'}, inchado), throwsStateError);
    });
  });
}
