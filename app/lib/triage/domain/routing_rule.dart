/// Modelo de encaminhamento lido do `content.db`.
///
/// Espelha as tabelas `routing_rule`, `routing_rule_term` e `routing_outcome`
/// do contrato. Nenhum destes tipos guarda estado de usuário: a sessão de
/// triagem vive apenas em memória e morre ao voltar ao repouso (LGPD-RF13).
library;

import 'package:meta/meta.dart';

/// Termo de uma regra. `negated` exige a AUSÊNCIA do token.
@immutable
class RuleTerm {
  const RuleTerm({
    required this.groupNo,
    required this.tokenId,
    required this.negated,
  });

  final int groupNo;
  final String tokenId;
  final bool negated;
}

/// Regra em forma normal disjuntiva: E dentro do grupo, OU entre grupos.
@immutable
class RoutingRule {
  const RoutingRule({
    required this.id,
    required this.priority,
    required this.outcomeId,
    required this.terms,
  });

  final String id;

  /// Desempata apenas entre regras de mesma severidade — nunca entre níveis.
  final int priority;

  final String outcomeId;
  final List<RuleTerm> terms;
}

/// Desfecho possível. `severityLevel` inteiro torna `max(gate, llm)` trivial.
@immutable
class RoutingOutcome {
  const RoutingOutcome({required this.id, required this.severityLevel});

  final String id;
  final int severityLevel;
}

/// Resultado da avaliação determinística.
@immutable
class TriageVerdict {
  const TriageVerdict({
    required this.outcomeId,
    required this.severityLevel,
    required this.matchedRuleId,
  });

  final String outcomeId;
  final int severityLevel;

  /// Regra vencedora, ou `null` quando o desfecho padrão do pacote assumiu.
  final String? matchedRuleId;

  @override
  String toString() =>
      'TriageVerdict($outcomeId, sev=$severityLevel, regra=${matchedRuleId ?? "padrão"})';
}

/// Conjunto de regras e desfechos de um pacote — a entrada do gate.
@immutable
class RuleModel {
  const RuleModel({
    required this.rules,
    required this.outcomes,
    required this.defaultOutcomeId,
  });

  final List<RoutingRule> rules;
  final Map<String, RoutingOutcome> outcomes;
  final String defaultOutcomeId;

  /// Maior severidade presente no pacote. É o nível das red flags.
  int get maxSeverity =>
      outcomes.values.map((o) => o.severityLevel).reduce((a, b) => a > b ? a : b);
}
