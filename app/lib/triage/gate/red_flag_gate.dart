/// Gate determinístico de encaminhamento.
///
/// ===========================================================================
/// CÓDIGO CRÍTICO DE SEGURANÇA DO PACIENTE
/// ===========================================================================
///
/// Função PURA e TOTAL: sem I/O, sem estado, sem exceção para entrada válida.
/// É avaliada ANTES de qualquer inferência do modelo local, e o LLM jamais
/// rebaixa o resultado — `severidade_final = max(gate, llm)` (espec.md INV-1).
///
/// Espelha o comportamento de `packer/src/rules.ts`, a implementação de
/// referência. Ambas leem a MESMA tabela do pacote e são verificadas contra a
/// MESMA suite golden (`seed/golden/clinical_cases.yaml`), o que impede que
/// divirjam silenciosamente.
///
/// O mesmo avaliador serve ao `RuleOnlyEngine` (kill switch do RF-12): não
/// existe uma segunda cópia da lógica clínica para sair de sincronia.
library;

import '../domain/routing_rule.dart';

/// Uma regra dispara quando existe um grupo cujos termos são TODOS satisfeitos.
///
/// Regra sem termos nunca dispara: caso contrário um erro de curadoria viraria
/// uma regra universal, aplicada a qualquer combinação de sintomas.
bool ruleMatches(RoutingRule rule, Set<String> tokens) {
  if (rule.terms.isEmpty) return false;

  final groups = <int, List<RuleTerm>>{};
  for (final term in rule.terms) {
    groups.putIfAbsent(term.groupNo, () => <RuleTerm>[]).add(term);
  }

  for (final terms in groups.values) {
    if (terms.every((t) => tokens.contains(t.tokenId) != t.negated)) return true;
  }
  return false;
}

/// Resolve o desfecho para um conjunto de tokens.
///
/// MAIOR SEVERIDADE VENCE; `priority` só desempata dentro do mesmo nível.
///
/// Essa ordem — e não "primeira regra por prioridade" — torna a INV-1
/// estrutural: nenhum erro de autoria consegue rebaixar uma red flag, nem uma
/// regra de rotina com a menor prioridade possível.
///
/// Sem regra correspondente, assume o desfecho padrão do pacote. Nunca há
/// silêncio: a orientação segura é sempre procurar atendimento.
TriageVerdict evaluate(Set<String> tokens, RuleModel model) {
  ({RoutingRule rule, RoutingOutcome outcome})? best;

  for (final rule in model.rules) {
    if (!ruleMatches(rule, tokens)) continue;
    final outcome = model.outcomes[rule.outcomeId];
    if (outcome == null) continue; // órfão já barrado pelo packer

    final wins = best == null ||
        outcome.severityLevel > best.outcome.severityLevel ||
        (outcome.severityLevel == best.outcome.severityLevel &&
            rule.priority < best.rule.priority);

    if (wins) best = (rule: rule, outcome: outcome);
  }

  if (best != null) {
    return TriageVerdict(
      outcomeId: best.outcome.id,
      severityLevel: best.outcome.severityLevel,
      matchedRuleId: best.rule.id,
    );
  }

  final fallback = model.outcomes[model.defaultOutcomeId];
  if (fallback == null) {
    // Pacote inválido: o packer nunca assinaria assim. Falha ruidosa em vez
    // de devolver um encaminhamento inventado.
    throw StateError(
      'Desfecho padrão "${model.defaultOutcomeId}" não existe no pacote',
    );
  }
  return TriageVerdict(
    outcomeId: fallback.id,
    severityLevel: fallback.severityLevel,
    matchedRuleId: null,
  );
}

/// `true` quando o veredito atingiu a maior severidade do pacote — o caso em
/// que o orquestrador ignora o LLM e responde emergência de imediato.
bool isRedFlag(TriageVerdict verdict, RuleModel model) =>
    verdict.severityLevel >= model.maxSeverity;
