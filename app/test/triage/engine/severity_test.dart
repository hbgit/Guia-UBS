/// INV-1 em forma de teste: `severidade_final = max(gate, llm)`.
///
/// Se algum destes casos falhar, existe um caminho no código em que um modelo
/// estatístico rodando no aparelho de alguém rebaixa uma emergência clínica.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/triage/domain/routing_rule.dart';
import 'package:guia_ubs/triage/domain/severity.dart';
import 'package:guia_ubs/triage/engine/triage_engine.dart';

const _emergencyGate = TriageVerdict(
  outcomeId: 'EMERGENCY',
  severityLevel: 100,
  matchedRuleId: 'rf.chest_pain',
);

const _routineGate = TriageVerdict(
  outcomeId: 'ROUTINE_UBS',
  severityLevel: 10,
  matchedRuleId: null,
);

const _routineSuggestion =
    EngineSuggestion(outcomeId: 'ROUTINE_UBS', severityLevel: 10);
const _emergencySuggestion =
    EngineSuggestion(outcomeId: 'EMERGENCY', severityLevel: 100);

void main() {
  group('mergeVerdict — INV-1', () {
    test('modelo NÃO rebaixa uma red flag', () {
      final result = mergeVerdict(_emergencyGate, _routineSuggestion, degraded: false);

      expect(
        result.outcomeId,
        'EMERGENCY',
        reason: 'o gate detectou red flag; nenhuma saída do modelo pode revertê-la',
      );
      expect(result.severityLevel, 100);
      expect(result.source, TriageSource.gate);
    });

    test('modelo escala quando o gate não achou nada grave', () {
      final result = mergeVerdict(_routineGate, _emergencySuggestion, degraded: false);

      expect(result.outcomeId, 'EMERGENCY');
      expect(result.severityLevel, 100);
      expect(result.source, TriageSource.engine);
    });

    test('sem opinião do modelo, o gate prevalece', () {
      final result = mergeVerdict(_routineGate, null, degraded: false);

      expect(result.outcomeId, 'ROUTINE_UBS');
      expect(result.source, TriageSource.gate);
      expect(result.matchedRuleId, isNull);
    });

    test('empate de severidade fica com o gate — o determinístico é a referência', () {
      final result = mergeVerdict(_routineGate, _routineSuggestion, degraded: false);

      expect(result.source, TriageSource.gate);
    });

    test('severidade final nunca é menor que a do gate, para qualquer sugestão', () {
      // Varredura sobre todo o intervalo de severidade que um pacote poderia
      // usar, incluindo valores absurdos: a propriedade tem de valer sempre,
      // não só para os dois desfechos que a semente tem hoje.
      for (var suggested = -50; suggested <= 200; suggested += 1) {
        final result = mergeVerdict(
          _emergencyGate,
          EngineSuggestion(outcomeId: 'X', severityLevel: suggested),
          degraded: false,
        );
        expect(
          result.severityLevel,
          greaterThanOrEqualTo(_emergencyGate.severityLevel),
          reason: 'sugestão de severidade $suggested rebaixou o gate',
        );
      }
    });

    test('degraded descreve o motor, não o desfecho', () {
      // Red flag resolvida sem consultar o modelo NÃO é degradação; já uma
      // triagem completada porque o motor caiu é, mesmo que o desfecho seja
      // idêntico.
      expect(mergeVerdict(_emergencyGate, null, degraded: false).degraded, isFalse);
      expect(mergeVerdict(_emergencyGate, null, degraded: true).degraded, isTrue);
    });

    test('a regra determinística vencedora é preservada para auditoria', () {
      final escalated =
          mergeVerdict(_routineGate, _emergencySuggestion, degraded: false);
      final kept = mergeVerdict(_emergencyGate, null, degraded: false);

      expect(kept.matchedRuleId, 'rf.chest_pain');
      // Mesmo quando o modelo escala, o que o gate concluiu continua registrado.
      expect(escalated.matchedRuleId, _routineGate.matchedRuleId);
    });
  });

  group('classe visual vem da escala DO PACK', () {
    // Aqui morava um defeito real: a conversão tinha limiares fixos em Dart
    // (`<= 1` rotina, `2` atenção, resto emergência). O pack semente usa 10 e
    // 100, então TODO resultado de rotina caía no `resto` e era pintado de
    // vermelho, com "Ligue 192" embaixo — a mensagem oposta à correta, para
    // quem depende da cor por não ler o texto.
    RuleModel modelWith(Map<String, int> levels) => RuleModel(
          rules: const [],
          outcomes: {
            for (final e in levels.entries)
              e.key: RoutingOutcome(id: e.key, severityLevel: e.value),
          },
          defaultOutcomeId: levels.keys.first,
        );

    test('escala 10/100 do pack semente classifica certo', () {
      final model = modelWith({'ROUTINE_UBS': 10, 'EMERGENCY': 100});

      expect(severityFor(10, model), GubsSeverity.routine);
      expect(severityFor(100, model), GubsSeverity.emergency);
    });

    test('escala 1/2/3 classifica certo — sem limiar em Dart', () {
      // A mesma função serve a um pack com outra escala. Era isto que os
      // limiares fixos impediam.
      final model = modelWith({'A': 1, 'B': 2, 'C': 3});

      expect(severityFor(1, model), GubsSeverity.routine);
      expect(severityFor(2, model), GubsSeverity.attention);
      expect(severityFor(3, model), GubsSeverity.emergency);
    });

    test('o nível intermediário vira atenção, não emergência', () {
      final model = modelWith({'R': 10, 'M': 50, 'E': 100});

      expect(severityFor(50, model), GubsSeverity.attention);
    });

    test('acima do máximo do pack ainda é emergência', () {
      final model = modelWith({'R': 10, 'E': 100});

      expect(severityFor(999, model), GubsSeverity.emergency);
    });

    test('abaixo do mínimo é rotina', () {
      final model = modelWith({'R': 10, 'E': 100});

      expect(severityFor(0, model), GubsSeverity.routine);
    });

    test('pack sem desfechos vira EMERGÊNCIA — fail-safe para cima', () {
      // Na dúvida, o conservador é mandar procurar atendimento: custa um
      // cartão vermelho a mais, e o contrário custa um encaminhamento errado.
      final degenerate = RuleModel(
        rules: const [],
        outcomes: const {},
        defaultOutcomeId: 'X',
      );

      expect(severityFor(10, degenerate), GubsSeverity.emergency);
    });

    test('pack com um único desfecho não inventa emergência', () {
      // Máximo e mínimo coincidem: o nível é o extremo inferior, mas também o
      // superior. A regra de emergência ganha, o que é o lado seguro.
      final model = modelWith({'ONLY': 42});

      expect(severityFor(42, model), GubsSeverity.emergency);
    });
  });
}
