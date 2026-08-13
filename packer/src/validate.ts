/**
 * Portoes de qualidade que precedem a assinatura.
 *
 * Nada e assinado com um destes vermelho. E aqui que um erro de curadoria para
 * — em vez de virar orientacao clinica errada num dispositivo sem internet
 * (PRD risco R5).
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

import { parse as parseYaml } from 'yaml';

import { evaluate, type Outcome, type Rule } from './rules.js';

export interface ValidationIssue {
  kind: 'referential' | 'translation' | 'golden' | 'golden_false_negative';
  message: string;
}

const LANGS = ['pt', 'es'] as const;

/**
 * Integridade referencial e completude de traducao.
 *
 * As FKs do SQLite ja barram o orfao classico; o que checamos aqui e o que uma
 * FK nao expressa: regra sem termo (nunca dispararia), token descontinuado
 * ainda referenciado por regra viva, e traducao faltando — que na interface
 * vira um cartao mudo para quem depende do audio.
 */
export function validateReferential(dbPath: string): ValidationIssue[] {
  const db = new DatabaseSync(dbPath, { readOnly: true });
  const issues: ValidationIssue[] = [];
  const add = (kind: ValidationIssue['kind'], message: string) => issues.push({ kind, message });

  try {
    for (const row of db.prepare('PRAGMA foreign_key_check').all() as Record<string, unknown>[]) {
      add('referential', `Violacao de chave estrangeira: ${JSON.stringify(row)}`);
    }

    for (const row of db
      .prepare(
        `SELECT r.id FROM routing_rule r
          LEFT JOIN routing_rule_term t ON t.rule_id = r.id
          GROUP BY r.id HAVING COUNT(t.token_id) = 0`,
      )
      .all() as { id: string }[]) {
      add('referential', `Regra "${row.id}" nao tem nenhum termo — nunca dispararia`);
    }

    for (const row of db
      .prepare(
        `SELECT DISTINCT t.rule_id, t.token_id FROM routing_rule_term t
           JOIN symptom_token s ON s.id = t.token_id
          WHERE s.deprecated = 1`,
      )
      .all() as { rule_id: string; token_id: string }[]) {
      add('referential', `Regra "${row.rule_id}" usa o token descontinuado "${row.token_id}"`);
    }

    const meta = db.prepare('SELECT default_outcome_id FROM pack_meta WHERE id = 1').get() as
      | { default_outcome_id: string }
      | undefined;
    if (!meta) {
      add('referential', 'pack_meta vazio');
    } else {
      const exists = db
        .prepare('SELECT 1 FROM routing_outcome WHERE id = ?')
        .get(meta.default_outcome_id);
      if (!exists) {
        add('referential', `Desfecho padrao "${meta.default_outcome_id}" nao existe`);
      }
    }

    // Completude de traducao: entidade -> tabela de traducao -> coluna de FK.
    const translatable: [string, string, string][] = [
      ['symptom_token', 'token_translation', 'token_id'],
      ['card', 'card_translation', 'card_id'],
      ['venue', 'venue_translation', 'venue_id'],
      ['service', 'service_translation', 'service_id'],
      ['document', 'document_translation', 'document_id'],
      ['flow_step', 'flow_step_translation', 'step_id'],
    ];

    for (const [entity, table, fk] of translatable) {
      for (const lang of LANGS) {
        for (const row of db
          .prepare(
            `SELECT e.id FROM ${entity} e
              WHERE NOT EXISTS (SELECT 1 FROM ${table} t WHERE t.${fk} = e.id AND t.lang = ?)`,
          )
          .all(lang) as { id: string }[]) {
          add('translation', `${entity} "${row.id}" sem traducao em "${lang}"`);
        }
      }
    }

    return issues;
  } finally {
    db.close();
  }
}

interface GoldenCase {
  id: string;
  tokens: string[];
  expect: string;
  note?: string;
  reviewed_by?: string | null;
}

export interface GoldenReport {
  total: number;
  passed: number;
  issues: ValidationIssue[];
  /** Casos que esperavam a maior severidade e obtiveram menos — evento de seguranca. */
  falseNegatives: number;
  /** Casos sem revisor clinico nomeado. Nao bloqueia a Fase 1; bloqueia o piloto. */
  unreviewed: number;
}

/**
 * Roda a suite golden contra o modelo de regras do pacote.
 * Criterio de aprovacao: 100%. Falso negativo e contabilizado a parte porque
 * sua gravidade e de outra ordem: e o caso em que o app manda para casa alguem
 * que precisava de emergencia.
 */
export function validateGolden(
  repoRoot: string,
  model: {
    rules: Rule[];
    outcomes: Map<string, Outcome>;
    defaultOutcomeId: string;
    tokenIds: Set<string>;
  },
): GoldenReport {
  const file = join(repoRoot, 'seed', 'golden', 'clinical_cases.yaml');
  const parsed = parseYaml(readFileSync(file, 'utf8')) as { cases?: GoldenCase[] };
  const cases = parsed.cases ?? [];

  const issues: ValidationIssue[] = [];
  let passed = 0;
  let falseNegatives = 0;
  let unreviewed = 0;

  const maxSeverity = Math.max(...[...model.outcomes.values()].map((o) => o.severityLevel));

  for (const testCase of cases) {
    if (!testCase.reviewed_by) unreviewed += 1;

    const unknown = testCase.tokens.filter((t) => !model.tokenIds.has(t));
    if (unknown.length > 0) {
      issues.push({
        kind: 'golden',
        message: `Caso "${testCase.id}" usa token inexistente: ${unknown.join(', ')}`,
      });
      continue;
    }

    const verdict = evaluate(
      new Set(testCase.tokens),
      model.rules,
      model.outcomes,
      model.defaultOutcomeId,
    );

    if (verdict.outcomeId === testCase.expect) {
      passed += 1;
      continue;
    }

    const expectedSeverity = model.outcomes.get(testCase.expect)?.severityLevel ?? -1;
    const isFalseNegative =
      expectedSeverity === maxSeverity && verdict.severityLevel < expectedSeverity;
    if (isFalseNegative) falseNegatives += 1;

    issues.push({
      kind: isFalseNegative ? 'golden_false_negative' : 'golden',
      message:
        `Caso "${testCase.id}" [${testCase.tokens.join(' + ')}]: ` +
        `esperado ${testCase.expect}, obtido ${verdict.outcomeId}` +
        (verdict.matchedRuleId ? ` (regra ${verdict.matchedRuleId})` : ' (desfecho padrao)'),
    });
  }

  return { total: cases.length, passed, issues, falseNegatives, unreviewed };
}
