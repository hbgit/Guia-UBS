/// Combinação de severidades — o ponto onde a INV-1 é imposta em código.
///
/// ===========================================================================
/// CÓDIGO CRÍTICO DE SEGURANÇA DO PACIENTE
/// ===========================================================================
///
/// `severidade_final = max(gate, llm)` (espec.md §5.1 INV-1, RF-05).
///
/// Existe uma única função capaz de produzir o resultado final de uma triagem,
/// e ela é monotônica: a sugestão do modelo só consegue SUBIR a severidade.
/// Nenhum caminho do código permite que uma inferência rebaixe o veredito
/// determinístico — não por convenção, mas porque não há outra função.
library;

import 'package:meta/meta.dart';

import '../engine/triage_engine.dart';
import 'routing_rule.dart';

/// De onde veio o desfecho final apresentado ao usuário.
enum TriageSource {
  /// Gate determinístico decidiu sozinho (red flag ou modelo sem opinião).
  gate,

  /// Modelo local escalou a severidade acima do gate.
  engine,
}

/// Resultado final de uma sessão de triagem.
///
/// Não guarda os tokens: a sequência de sintomas morre em memória junto com a
/// sessão e nunca é persistida (LGPD-RF13, INV-2).
@immutable
class TriageResult {
  const TriageResult({
    required this.outcomeId,
    required this.severityLevel,
    required this.source,
    required this.degraded,
    required this.matchedRuleId,
  });

  final String outcomeId;
  final int severityLevel;
  final TriageSource source;

  /// `true` quando o motor local não pôde ser usado e a triagem completou só
  /// com regras (RF-12). Vira contador agregado de telemetria, nunca evento
  /// individual.
  final bool degraded;

  /// Regra determinística vencedora, quando houve.
  final String? matchedRuleId;

  @override
  String toString() => 'TriageResult($outcomeId, sev=$severityLevel, '
      'origem=${source.name}, degradado=$degraded)';
}

/// Combina o veredito determinístico com a sugestão do motor local.
///
/// A sugestão é DESCARTADA quando não supera o gate. Isso cobre três casos com
/// a mesma regra, sem ramificação especial para nenhum deles:
///
/// * modelo concorda com o gate  → gate prevalece (mesma severidade);
/// * modelo tenta rebaixar       → ignorado;
/// * modelo sem opinião (`null`) → gate prevalece.
///
/// `degraded` descreve a DISPONIBILIDADE do motor, não o desfecho: uma red flag
/// resolvida sem consultar o modelo não é degradação, é o caminho previsto.
TriageResult mergeVerdict(
  TriageVerdict gate,
  EngineSuggestion? suggestion, {
  required bool degraded,
}) {
  if (suggestion == null || suggestion.severityLevel <= gate.severityLevel) {
    return TriageResult(
      outcomeId: gate.outcomeId,
      severityLevel: gate.severityLevel,
      source: TriageSource.gate,
      degraded: degraded,
      matchedRuleId: gate.matchedRuleId,
    );
  }

  return TriageResult(
    outcomeId: suggestion.outcomeId,
    severityLevel: suggestion.severityLevel,
    source: TriageSource.engine,
    degraded: degraded,
    matchedRuleId: gate.matchedRuleId,
  );
}
