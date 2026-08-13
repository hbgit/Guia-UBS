/**
 * Avaliador de regras em forma normal disjuntiva — IMPLEMENTACAO DE REFERENCIA.
 *
 * O gate deterministico em Dart (`app/lib/triage/gate/red_flag_gate.dart`) deve
 * produzir exatamente o mesmo resultado para qualquer entrada; ambos leem a
 * MESMA tabela do pacote e sao verificados contra a MESMA suite golden.
 *
 * Funcao pura e total: sem I/O, sem excecao para entrada valida, sem estado.
 */

export interface RuleTerm {
  groupNo: number;
  tokenId: string;
  /** Termo negado exige a AUSENCIA do token. */
  negated: boolean;
}

export interface Rule {
  id: string;
  priority: number;
  outcomeId: string;
  terms: RuleTerm[];
}

export interface Outcome {
  id: string;
  severityLevel: number;
}

export interface Verdict {
  outcomeId: string;
  severityLevel: number;
  /** Regra vencedora, ou null quando o desfecho padrao assumiu. */
  matchedRuleId: string | null;
}

/**
 * Uma regra dispara quando existe um grupo cujos termos sao TODOS satisfeitos
 * (E dentro do grupo, OU entre grupos). Regra sem termos nunca dispara —
 * caso contrario um erro de autoria viraria uma regra universal.
 */
export function ruleMatches(rule: Rule, tokens: ReadonlySet<string>): boolean {
  if (rule.terms.length === 0) return false;

  const groups = new Map<number, RuleTerm[]>();
  for (const term of rule.terms) {
    const bucket = groups.get(term.groupNo);
    if (bucket) bucket.push(term);
    else groups.set(term.groupNo, [term]);
  }

  for (const terms of groups.values()) {
    if (terms.every((t) => tokens.has(t.tokenId) !== t.negated)) return true;
  }
  return false;
}

/**
 * Resolve o desfecho de um conjunto de tokens.
 *
 * MAIOR SEVERIDADE VENCE; `priority` so desempata dentro do mesmo nivel.
 *
 * Essa ordem — e nao "primeira regra por prioridade" — e deliberada: torna
 * impossivel que um erro de autoria (uma regra de rotina com prioridade baixa)
 * rebaixe uma red flag. A invariante INV-1 passa a ser estrutural, nao uma
 * convencao que o revisor precisa lembrar de conferir.
 *
 * Sem regra correspondente, assume o desfecho padrao do pacote — nunca silencio.
 */
export function evaluate(
  tokens: ReadonlySet<string>,
  rules: readonly Rule[],
  outcomes: ReadonlyMap<string, Outcome>,
  defaultOutcomeId: string,
): Verdict {
  let best: { verdict: Verdict; priority: number } | null = null;

  for (const rule of rules) {
    if (!ruleMatches(rule, tokens)) continue;
    const outcome = outcomes.get(rule.outcomeId);
    if (!outcome) continue; // orfao ja barrado por validate-referential

    const wins =
      best === null ||
      outcome.severityLevel > best.verdict.severityLevel ||
      (outcome.severityLevel === best.verdict.severityLevel && rule.priority < best.priority);

    if (wins) {
      best = {
        verdict: {
          outcomeId: outcome.id,
          severityLevel: outcome.severityLevel,
          matchedRuleId: rule.id,
        },
        priority: rule.priority,
      };
    }
  }

  if (best) return best.verdict;

  const fallback = outcomes.get(defaultOutcomeId);
  if (!fallback) {
    throw new Error(`Desfecho padrao "${defaultOutcomeId}" nao existe no pacote`);
  }
  return { outcomeId: fallback.id, severityLevel: fallback.severityLevel, matchedRuleId: null };
}
