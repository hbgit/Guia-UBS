/// Espelha a matriz da [espec.md §4.1], linha a linha.
///
/// O último grupo é o que justifica a máquina existir separada do controller:
/// ele percorre o GRAFO INTEIRO para provar propriedades clínicas. "Nenhum
/// caminho leva de red flag a inferência" é uma afirmação sobre a estrutura, e
/// só é verificável porque a estrutura é dado.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/triage/orchestrator/triage_fsm.dart';

TriageTransition _take(TriageState state, TriageEvent event) {
  final result = transition(state, event);
  expect(result, isNotNull, reason: 'a matriz prevê esta transição');
  return result!;
}

const List<TriageEvent> _allEvents = [
  TapTriage(packAvailable: true),
  TapTriage(packAvailable: false),
  AddToken(inOntology: true, atCapacity: false),
  AddToken(inOntology: false, atCapacity: false),
  AddToken(inOntology: true, atCapacity: true),
  Confirm(hasTokens: true),
  Confirm(hasTokens: false),
  AbandonSession(),
  GateDone(redFlag: true, engineAvailable: true),
  GateDone(redFlag: true, engineAvailable: false),
  GateDone(redFlag: false, engineAvailable: true),
  GateDone(redFlag: false, engineAvailable: false),
  GateFailed(),
  InferenceOk(),
  InferenceFailed(),
  RulesDone(),
  LeaveResult(),
];

void main() {
  group('S0_IDLE', () {
    test('A1 — tocar triagem com pack verificado começa a sessão', () {
      final t = _take(TriageState.s0Idle, const TapTriage(packAvailable: true));

      expect(t.next, TriageState.s1Composing);
      expect(t.actions, [TriageAction.startSession]);
    });

    test('sem pack não há triagem — nem degradada', () {
      // Uma triagem sem regras não é uma triagem pior: é nenhuma triagem.
      expect(
        transition(TriageState.s0Idle, const TapTriage(packAvailable: false)),
        isNull,
      );
    });
  });

  group('S1_COMPOSING', () {
    test('A2 — token da ontologia, abaixo do teto, entra', () {
      final t = _take(
        TriageState.s1Composing,
        const AddToken(inOntology: true, atCapacity: false),
      );

      expect(t.next, TriageState.s1Composing);
      expect(t.actions, [TriageAction.appendToken]);
    });

    test('A3 — token no teto de 5 é recusado com retorno visual', () {
      final t = _take(
        TriageState.s1Composing,
        const AddToken(inOntology: true, atCapacity: true),
      );

      expect(t.actions, [TriageAction.rejectToken]);
    });

    test('A3 — token fora da ontologia é recusado', () {
      final t = _take(
        TriageState.s1Composing,
        const AddToken(inOntology: false, atCapacity: false),
      );

      expect(t.actions, [TriageAction.rejectToken]);
    });

    test('A4 — confirmar com ao menos um token congela a composição', () {
      final t = _take(TriageState.s1Composing, const Confirm(hasTokens: true));

      expect(t.next, TriageState.s2GateEval);
      expect(t.actions, [TriageAction.snapshotTokens]);
    });

    test('confirmar sem token não é evento válido', () {
      expect(
        transition(TriageState.s1Composing, const Confirm(hasTokens: false)),
        isNull,
      );
    });

    test('A5 — abandono descarta a sessão da memória', () {
      final t = _take(TriageState.s1Composing, const AbandonSession());

      expect(t.next, TriageState.s0Idle);
      expect(t.actions, [TriageAction.discardSession]);
    });
  });

  group('S2_GATE_EVAL — onde a INV-1 vive', () {
    test('A6 — red flag responde emergência SEM consultar o modelo', () {
      for (final engineAvailable in [true, false]) {
        final t = _take(
          TriageState.s2GateEval,
          GateDone(redFlag: true, engineAvailable: engineAvailable),
        );

        expect(t.next, TriageState.s5Result);
        expect(t.actions, contains(TriageAction.bypassEngine));
        expect(
          t.actions,
          isNot(contains(TriageAction.runEngine)),
          reason: 'red flag esperando 5 s por um modelo que não pode mudar '
              'nada é tempo tirado de quem está tendo um infarto',
        );
      }
    });

    test('A7 — sem red flag e com motor, consulta o modelo', () {
      final t = _take(
        TriageState.s2GateEval,
        const GateDone(redFlag: false, engineAvailable: true),
      );

      expect(t.next, TriageState.s3Inferring);
      expect(t.actions, [TriageAction.runEngine]);
    });

    test('A8 — sem red flag e sem motor, cai direto nas regras', () {
      final t = _take(
        TriageState.s2GateEval,
        const GateDone(redFlag: false, engineAvailable: false),
      );

      expect(t.next, TriageState.s4Fallback);
      expect(t.actions, [TriageAction.runRulesOnly]);
    });

    test('A9 — exceção no gate é FAIL-CLOSED, não fail-open', () {
      final t = _take(TriageState.s2GateEval, const GateFailed());

      expect(t.next, TriageState.e1FailClosed);
      expect(t.actions, contains(TriageAction.failClosedToEmergency));
      expect(t.actions, contains(TriageAction.logFatalLocal));
    });
  });

  group('S3 e S4', () {
    test('A10 — inferência boa passa por max(gate, llm)', () {
      final t = _take(TriageState.s3Inferring, const InferenceOk());

      expect(t.next, TriageState.s5Result);
      expect(t.actions, contains(TriageAction.mergeVerdict));
    });

    test('A11 — falha na inferência aborta e cai nas regras', () {
      final t = _take(TriageState.s3Inferring, const InferenceFailed());

      expect(t.next, TriageState.s4Fallback);
      expect(t.actions, [
        TriageAction.abortInference,
        TriageAction.runRulesOnly,
      ]);
    });

    test('A12 — regras puras sempre chegam ao resultado', () {
      final t = _take(TriageState.s4Fallback, const RulesDone());

      expect(t.next, TriageState.s5Result);
    });
  });

  group('saídas', () {
    test('A13/A14 — sair de qualquer final limpa a sessão', () {
      for (final state in [TriageState.s5Result, TriageState.e1FailClosed]) {
        final t = _take(state, const LeaveResult());

        expect(t.next, TriageState.s0Idle);
        expect(t.actions, [TriageAction.discardSession]);
      }
    });

    test('A15 — "casa" funciona de qualquer estado vivo', () {
      // O botão está sempre visível (CAP-02). Uma tela em que ele não funciona
      // é um dead-end com aparência de saída.
      for (final state in TriageState.values) {
        if (state == TriageState.s0Idle) continue;
        final t = _take(state, const AbandonSession());

        expect(t.next, TriageState.s0Idle);
        expect(t.actions, contains(TriageAction.discardSession));
      }
    });
  });

  group('propriedades clínicas do grafo', () {
    test('NENHUM caminho leva red flag à inferência', () {
      // A propriedade central da INV-1, verificada na estrutura e não em
      // um caso de teste específico.
      for (final state in TriageState.values) {
        for (final engineAvailable in [true, false]) {
          final t = transition(
            state,
            GateDone(redFlag: true, engineAvailable: engineAvailable),
          );
          if (t == null) continue;
          expect(t.next, isNot(TriageState.s3Inferring));
          expect(t.actions, isNot(contains(TriageAction.runEngine)));
        }
      }
    });

    test('só S2 consulta o modelo — não há atalho para a inferência', () {
      for (final state in TriageState.values) {
        if (state == TriageState.s2GateEval) continue;
        for (final event in _allEvents) {
          expect(
            transition(state, event)?.next,
            isNot(TriageState.s3Inferring),
            reason: '$state + ${event.runtimeType} pulou o gate',
          );
        }
      }
    });

    test('todo caminho para o resultado passa pelo gate', () {
      // S5 só é alcançável a partir de S2 (red flag), S3 ou S4 — e S3 e S4 só
      // são alcançáveis a partir de S2. Não existe rota do repouso ou da
      // composição direto ao cartão.
      for (final state in [
        TriageState.s0Idle,
        TriageState.s1Composing,
      ]) {
        for (final event in _allEvents) {
          expect(
            transition(state, event)?.next,
            isNot(TriageState.s5Result),
            reason: '$state + ${event.runtimeType} entregou resultado sem gate',
          );
        }
      }
    });

    test('a falha do gate nunca termina em resultado comum', () {
      // Se `GateFailed` pudesse levar a S5, o fail-closed viraria opcional.
      for (final state in TriageState.values) {
        final t = transition(state, const GateFailed());
        if (t == null) continue;
        expect(t.next, TriageState.e1FailClosed);
        expect(t.actions, contains(TriageAction.failClosedToEmergency));
      }
    });

    test('todo estado vivo tem saída — nenhum poço', () {
      // Sessão presa é sessão que o usuário abandona sem orientação nenhuma.
      for (final state in TriageState.values) {
        if (state == TriageState.s0Idle) continue;
        final exits = _allEvents
            .map((e) => transition(state, e))
            .whereType<TriageTransition>()
            .where((t) => t.next != state);
        expect(exits, isNotEmpty, reason: '$state é um poço');
      }
    });

    test('todo resultado é falado — o áudio não é opcional na saída', () {
      // Quem não lê depende dele. A tela renderiza sem esperar o áudio
      // (INV-8), mas nenhum caminho para o cartão pode esquecer de dispará-lo.
      for (final state in TriageState.values) {
        for (final event in _allEvents) {
          final t = transition(state, event);
          if (t == null) continue;
          if (t.next != TriageState.s5Result &&
              t.next != TriageState.e1FailClosed) {
            continue;
          }
          expect(
            t.actions,
            contains(TriageAction.speakResult),
            reason: '$state + ${event.runtimeType} chega ao cartão em silêncio',
          );
        }
      }
    });
  });
}
