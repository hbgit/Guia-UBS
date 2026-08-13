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
}
