/// A saída do SLM é entrada não confiável. Estes testes fixam o quão pouco ela
/// pode fazer.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/triage/domain/routing_rule.dart';
import 'package:guia_ubs/triage/engine/engine_decoder.dart';

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
  group('decodeSuggestion', () {
    test('reconhece um identificador do pacote', () {
      final suggestion = decodeSuggestion('EMERGENCY', _seedLike);

      expect(suggestion, isNotNull);
      expect(suggestion!.outcomeId, 'EMERGENCY');
      expect(suggestion.severityLevel, 100);
    });

    test('a severidade vem do pacote, nunca do texto gerado', () {
      // O modelo tenta anexar um nível baixo à emergência. O número é ignorado:
      // ele não faz parte do que a decodificação lê.
      final suggestion = decodeSuggestion('EMERGENCY severity 1 nivel 0', _seedLike);

      expect(suggestion!.severityLevel, 100);
    });

    test('tolera caixa e pontuação em volta', () {
      for (final raw in <String>[
        ' emergency ',
        'Resposta: EMERGENCY.',
        '**EMERGENCY**',
        '\nEMERGENCY\n',
      ]) {
        expect(decodeSuggestion(raw, _seedLike)?.outcomeId, 'EMERGENCY',
            reason: 'não reconheceu em "$raw"');
      }
    });

    test('alucinação vira "sem opinião"', () {
      for (final raw in <String>[
        '',
        'nao sei',
        'PROCURE_UM_MEDICO',
        'EMERGENCIA', // parecido, mas não é identificador do pacote
        '42',
        '<|im_end|>',
      ]) {
        expect(decodeSuggestion(raw, _seedLike), isNull, reason: 'aceitou "$raw"');
      }
    });

    test('dois identificadores na mesma resposta = sem opinião', () {
      // O modelo não escolheu. Escolher por ele seria inventar uma decisão
      // clínica a partir de ordem de aparição.
      expect(decodeSuggestion('ROUTINE_UBS ou EMERGENCY', _seedLike), isNull);
    });

    test('repetir o mesmo identificador continua valendo', () {
      expect(
        decodeSuggestion('EMERGENCY EMERGENCY EMERGENCY', _seedLike)?.outcomeId,
        'EMERGENCY',
      );
    });

    test('identificador que é prefixo de outro não contamina o resultado', () {
      // Armadilha real: busca por subsequência acharia EMERGENCY dentro de
      // EMERGENCY_PEDIATRICA e a decodificação viraria sorteio.
      final model = _model({
        'ROUTINE_UBS': 10,
        'EMERGENCY': 100,
        'EMERGENCY_PEDIATRICA': 100,
      });

      expect(decodeSuggestion('EMERGENCY_PEDIATRICA', model)?.outcomeId,
          'EMERGENCY_PEDIATRICA');
      expect(decodeSuggestion('EMERGENCY', model)?.outcomeId, 'EMERGENCY');
    });

    test('pacote com identificadores ambíguos desqualifica a decodificação', () {
      // Dois desfechos que só diferem em caixa: não há resposta do modelo que
      // possa ser resolvida com segurança, então nenhuma é aceita.
      final ambiguous = _model({'Emergency': 100, 'EMERGENCY': 10});

      expect(decodeSuggestion('EMERGENCY', ambiguous), isNull);
    });

    test('texto longo além da janela não é varrido', () {
      final farAway = '${'x' * (maxDecodedChars + 10)} EMERGENCY';

      expect(decodeSuggestion(farAway, _seedLike), isNull);
    });
  });
}
