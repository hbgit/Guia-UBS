/// FSM-A — sessão de triagem, como máquina **explícita**.
///
/// ===========================================================================
/// CÓDIGO CRÍTICO DE SEGURANÇA DO PACIENTE
/// ===========================================================================
///
/// Transcrição da matriz de [espec.md §4.1] em enum de estados, eventos e
/// ações. Sem I/O, sem relógio, sem modelo: o [TriageSession] é quem chama o
/// mundo e traduz o que aconteceu em [TriageEvent].
///
/// A separação existe pelo mesmo motivo da FSM-B, e aqui ela vale mais: as
/// propriedades que precisam ser verdadeiras nesta máquina são clínicas.
/// "Nenhum caminho leva de red flag a resultado não-emergência" é uma
/// afirmação sobre o GRAFO, e um grafo declarado como dado pode ser
/// percorrido por um teste. Espalhado por `if`s dentro de um controller, não.
///
/// ## As três propriedades que o teste percorre
///
/// 1. Red flag **nunca** passa pelo modelo (S2 → S5 direto, sem S3).
/// 2. Exceção no gate **sempre** termina em `E1_FAIL_CLOSED`, e o resultado
///    associado é emergência — fail-closed, não fail-open.
/// 3. Toda saída de S3 que não seja `inference_ok` cai em S4, que é total.
library;

import 'package:meta/meta.dart';

/// Σ da FSM-A.
enum TriageState {
  /// Repouso. Nenhuma sessão viva, nenhum token em memória.
  s0Idle,

  /// Compondo sintomas (RF-02/RF-03).
  s1Composing,

  /// Gate determinístico rodando (RF-04).
  s2GateEval,

  /// Modelo local rodando, com teto de 5 s (RF-05).
  s3Inferring,

  /// Só regras (RF-12).
  s4Fallback,

  /// Resultado na tela (RF-06). Final.
  s5Result,

  /// Falha no gate. Final, e o resultado exibido é emergência.
  e1FailClosed,
}

/// Efeitos que o driver executa. A máquina os nomeia, não os executa.
enum TriageAction {
  /// Carrega ontologia e regras do pack ativo; sorteia o id de sessão.
  startSession,

  /// Acrescenta o token à composição.
  appendToken,

  /// Recusa o token e dá retorno visual — teto de 5 atingido, ou token que
  /// não existe na ontologia do pack.
  rejectToken,

  /// Congela o conjunto de tokens. Depois disto a composição não muda mais.
  snapshotTokens,

  /// Descarta a sessão: tokens fora da memória, id de sessão descartado.
  discardSession,

  /// Responde emergência sem consultar o modelo (INV-1).
  bypassEngine,

  /// Monta o prompt determinístico e chama o motor.
  runEngine,

  /// Aborta a inferência e libera o contexto nativo.
  abortInference,

  /// Resolve pelas regras puras e marca `degraded`.
  runRulesOnly,

  /// `severidade_final = max(gate, motor)`.
  mergeVerdict,

  /// Fail-closed: resultado é emergência, aconteça o que acontecer.
  failClosedToEmergency,

  /// Registra a falha no ring buffer local (sem PII, LGPD-RT03).
  logFatalLocal,

  /// Dispara o áudio do cartão, em paralelo e sem bloquear (RF-06).
  speakResult,
}

@immutable
sealed class TriageEvent {
  const TriageEvent();
}

/// Usuário tocou em "estou com sintomas".
@immutable
final class TapTriage extends TriageEvent {
  const TapTriage({required this.packAvailable});

  /// Guarda da linha A1: sem pack verificado não há ontologia nem regras, e
  /// uma triagem sem regras não é uma triagem degradada — é nenhuma triagem.
  final bool packAvailable;
}

/// Usuário tocou um ícone de sintoma.
@immutable
final class AddToken extends TriageEvent {
  const AddToken({required this.inOntology, required this.atCapacity});

  /// O token existe na ontologia do pack ativo.
  final bool inOntology;

  /// Já há 5 tokens — o teto do CAP-03.
  final bool atCapacity;
}

/// Usuário confirmou a composição.
@immutable
final class Confirm extends TriageEvent {
  const Confirm({required this.hasTokens});

  final bool hasTokens;
}

/// 120 s sem toque, ou toque em "casa".
@immutable
final class AbandonSession extends TriageEvent {
  const AbandonSession();
}

/// Gate terminou.
@immutable
final class GateDone extends TriageEvent {
  const GateDone({required this.redFlag, required this.engineAvailable});

  /// O veredito determinístico atingiu a severidade máxima do pack.
  final bool redFlag;

  final bool engineAvailable;
}

/// Gate lançou. Não deveria acontecer — o avaliador é total — mas "não
/// deveria" não é uma garantia que se possa dar a um paciente.
@immutable
final class GateFailed extends TriageEvent {
  const GateFailed();
}

/// Modelo respondeu com um desfecho que o decodificador reconheceu.
@immutable
final class InferenceOk extends TriageEvent {
  const InferenceOk();
}

/// Timeout de 5 s, erro de FFI ou falta de memória.
@immutable
final class InferenceFailed extends TriageEvent {
  const InferenceFailed();
}

/// Regras puras responderam. Sempre respondem: o avaliador é total.
@immutable
final class RulesDone extends TriageEvent {
  const RulesDone();
}

/// Usuário saiu da tela de resultado.
@immutable
final class LeaveResult extends TriageEvent {
  const LeaveResult();
}

@immutable
class TriageTransition {
  const TriageTransition(
    this.next, {
    this.actions = const [],
    required this.rule,
  });

  final TriageState next;
  final List<TriageAction> actions;

  /// Linha da matriz que autorizou a transição, para a falha de teste apontar
  /// direto para a spec.
  final String rule;
}

/// Aplica a matriz de [espec.md §4.1].
///
/// `null` para pares que a matriz não prevê: o driver descarta o evento e
/// permanece onde está. Uma máquina que improvisa transição para evento
/// inesperado é uma máquina que pode entregar resultado sem passar pelo gate.
TriageTransition? transition(TriageState state, TriageEvent event) {
  switch ((state, event)) {
    // --- S0_IDLE -----------------------------------------------------------
    case (TriageState.s0Idle, final TapTriage e):
      if (!e.packAvailable) return null;
      return const TriageTransition(
        TriageState.s1Composing,
        actions: [TriageAction.startSession],
        rule: 'A1 S0→S1 tap_triagem [pack ativo verificado]',
      );

    // --- S1_COMPOSING ------------------------------------------------------
    case (TriageState.s1Composing, final AddToken e):
      if (e.inOntology && !e.atCapacity) {
        return const TriageTransition(
          TriageState.s1Composing,
          actions: [TriageAction.appendToken],
          rule: 'A2 S1→S1 add_token [t ∈ ontologia ∧ |tokens| < 5]',
        );
      }
      return const TriageTransition(
        TriageState.s1Composing,
        actions: [TriageAction.rejectToken],
        rule: 'A3 S1→S1 add_token [fora da ontologia ∨ teto de 5]',
      );

    case (TriageState.s1Composing, final Confirm e):
      if (!e.hasTokens) return null; // confirmar vazio não é evento válido
      return const TriageTransition(
        TriageState.s2GateEval,
        actions: [TriageAction.snapshotTokens],
        rule: 'A4 S1→S2 confirm [|tokens| ≥ 1]',
      );

    case (TriageState.s1Composing, AbandonSession()):
      return const TriageTransition(
        TriageState.s0Idle,
        actions: [TriageAction.discardSession],
        rule: 'A5 S1→S0 timeout 120s ∨ tap_home',
      );

    // --- S2_GATE_EVAL ------------------------------------------------------
    case (TriageState.s2GateEval, final GateDone e):
      if (e.redFlag) {
        // O modelo NÃO é consultado. Não é otimização: é a INV-1 escrita no
        // grafo. Se o caminho passasse por S3, existiria um estado em que uma
        // emergência espera 5 s por um modelo que não pode mudar nada.
        return const TriageTransition(
          TriageState.s5Result,
          actions: [TriageAction.bypassEngine, TriageAction.speakResult],
          rule: 'A6 S2→S5 red flag [bypass LLM, INV-1]',
        );
      }
      if (e.engineAvailable) {
        return const TriageTransition(
          TriageState.s3Inferring,
          actions: [TriageAction.runEngine],
          rule: 'A7 S2→S3 sem red flag [motor disponível]',
        );
      }
      return const TriageTransition(
        TriageState.s4Fallback,
        actions: [TriageAction.runRulesOnly],
        rule: 'A8 S2→S4 sem red flag [motor indisponível]',
      );

    case (TriageState.s2GateEval, GateFailed()):
      return const TriageTransition(
        TriageState.e1FailClosed,
        actions: [
          TriageAction.failClosedToEmergency,
          TriageAction.logFatalLocal,
          TriageAction.speakResult,
        ],
        rule: 'A9 S2→E1 exceção [fail-closed para EMERGENCY]',
      );

    // --- S3_INFERRING ------------------------------------------------------
    case (TriageState.s3Inferring, InferenceOk()):
      return const TriageTransition(
        TriageState.s5Result,
        actions: [TriageAction.mergeVerdict, TriageAction.speakResult],
        rule: 'A10 S3→S5 inference_ok [max(gate, llm)]',
      );

    case (TriageState.s3Inferring, InferenceFailed()):
      return const TriageTransition(
        TriageState.s4Fallback,
        actions: [TriageAction.abortInference, TriageAction.runRulesOnly],
        rule: 'A11 S3→S4 timeout 5s ∨ erro FFI ∨ OOM',
      );

    // --- S4_FALLBACK -------------------------------------------------------
    case (TriageState.s4Fallback, RulesDone()):
      return const TriageTransition(
        TriageState.s5Result,
        actions: [TriageAction.mergeVerdict, TriageAction.speakResult],
        rule: 'A12 S4→S5 rules_done [degraded ← true]',
      );

    // --- Finais ------------------------------------------------------------
    case (TriageState.s5Result, LeaveResult()):
      return const TriageTransition(
        TriageState.s0Idle,
        actions: [TriageAction.discardSession],
        rule: 'A13 S5→S0 tap_next ∨ tap_home [limpa sessão]',
      );

    case (TriageState.e1FailClosed, LeaveResult()):
      return const TriageTransition(
        TriageState.s0Idle,
        actions: [TriageAction.discardSession],
        rule: 'A14 E1→S0 tap_home [limpa sessão]',
      );

    // Abandonar vale de qualquer estado vivo: o botão "casa" está sempre
    // visível (CAP-02), e uma tela de onde o botão não funciona é um
    // dead-end com aparência de saída.
    case (_, AbandonSession()) when state != TriageState.s0Idle:
      return const TriageTransition(
        TriageState.s0Idle,
        actions: [TriageAction.discardSession],
        rule: 'A15 * →S0 tap_home [casa sempre disponível]',
      );

    default:
      return null;
  }
}
