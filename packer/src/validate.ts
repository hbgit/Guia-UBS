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

import {
  avaliarRevisao,
  conferirContraRegistro,
  evaluate,
  MIN_REVISORES,
  type EntradaRegistro,
  type Outcome,
  type Rule,
} from '@guia-ubs/contract';

export interface ValidationIssue {
  kind:
    | 'referential'
    | 'translation'
    | 'golden'
    | 'golden_false_negative'
    | 'golden_sem_revisor'
    | 'golden_revisao_invalida'
    | 'golden_vazia'
    | 'golden_registro_invalido';
  message: string;
}

/**
 * `assinatura`: o pack sai assinado, e caso sem revisao clinica BLOQUEIA.
 * `verificacao`: nada e assinado (`--dry-run`), e caso sem revisao so avisa.
 *
 * Nao ha terceiro modo nem flag que pule o portao: o modo de aviso so e
 * alcancavel por um comando que nao vai assinar (`cli.ts#modoDoComando`).
 */
export type ModoRevisao = 'assinatura' | 'verificacao';

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

export interface GoldenCase {
  id: string;
  tokens: string[];
  expect: string;
  note?: string;
  /**
   * `unknown` de proposito: vem do YAML sem validacao de tipo, e quem decide se
   * e uma lista de `RevisorYaml` valida e `avaliarRevisao` do contrato.
   */
  reviewed_by?: unknown;
  reviewed_at?: unknown;
}

/**
 * Casos golden do YAML — a fonte do caminho `seed/`, que o CI roda em toda PR.
 *
 * O outro leitor e `extract.ts#lerGoldenDoBanco`, a fonte do caminho do CMS,
 * onde o revisor clinico acrescenta casos pela interface. Sao duas FONTES para
 * dois CAMINHOS distintos, e nao duas copias da mesma coisa: cada caminho tem
 * uma so, e nao ha sincronizacao para envelhecer.
 *
 * Os dois desaguam na MESMA `validateGolden`, que e o que impede os criterios de
 * aprovacao divergirem.
 */
export function lerGoldenDoYaml(repoRoot: string): GoldenCase[] {
  const file = join(repoRoot, 'seed', 'golden', 'clinical_cases.yaml');
  const parsed = parseYaml(readFileSync(file, 'utf8')) as { cases?: GoldenCase[] };
  return parsed.cases ?? [];
}

/**
 * Entradas cruas do registro publico `seed/golden/atestados.yaml` — a lista sob
 * `atestados`. `unknown` de proposito: quem decide se o formato vale e
 * `avaliarRegistro` do contrato, e um nome ou numero de registro que alguem
 * deixe ali precisa chegar ate ela para ser recusado.
 */
export function lerAtestadosDoYaml(repoRoot: string): unknown[] {
  const file = join(repoRoot, 'seed', 'golden', 'atestados.yaml');
  const parsed: unknown = parseYaml(readFileSync(file, 'utf8'));
  const chaves = parsed && typeof parsed === 'object' ? Object.keys(parsed) : [];
  const atestados = (parsed as { atestados?: unknown } | null)?.atestados;
  if (chaves.length !== 1 || !Array.isArray(atestados)) {
    throw new Error(`${file}: esperado so a chave "atestados" com uma lista (vazia: "atestados: []")`);
  }
  return atestados;
}

export interface GoldenReport {
  total: number;
  passed: number;
  issues: ValidationIssue[];
  /** Casos que esperavam a maior severidade e obtiveram menos — evento de seguranca. */
  falseNegatives: number;
  /** Casos sem revisao clinica. Bloqueia em `assinatura`; em `verificacao`, avisa. */
  unreviewed: number;
}

/**
 * Roda a suite golden contra o modelo de regras do pacote.
 * Criterio de aprovacao: 100%. Falso negativo e contabilizado a parte porque
 * sua gravidade e de outra ordem: e o caso em que o app manda para casa alguem
 * que precisava de emergencia.
 *
 * Revisao clinica (issue #2): AUSENTE bloqueia so em `assinatura`; INVALIDA
 * (formato errado, ou atestado fora do registro / divergente dele) e suite vazia
 * bloqueiam nos dois modos (D9) — sao erro de quem escreveu o YAML, e o CI de PR
 * deve apontar ja. `opcoes` e obrigatorio de proposito: um padrao seria um modo
 * escolhido por omissao.
 */
export function validateGolden(
  cases: readonly GoldenCase[],
  model: {
    rules: Rule[];
    outcomes: Map<string, Outcome>;
    defaultOutcomeId: string;
    tokenIds: Set<string>;
  },
  opcoes: { modo: ModoRevisao; agora: Date; registro: readonly EntradaRegistro[] },
): GoldenReport {
  const issues: ValidationIssue[] = [];
  let passed = 0;
  let falseNegatives = 0;
  let unreviewed = 0;

  if (cases.length === 0) {
    // Suite vazia passaria "100%" sem garantir nada (D7).
    issues.push({
      kind: 'golden_vazia',
      message: 'Suite golden vazia: sem casos, nao ha o que garantir',
    });
  }

  const maxSeverity = Math.max(...[...model.outcomes.values()].map((o) => o.severityLevel));

  for (const testCase of cases) {
    const revisao = avaliarRevisao(testCase, opcoes.agora);
    if (revisao.estado === 'ausente') {
      unreviewed += 1;
      if (opcoes.modo === 'assinatura') {
        issues.push({
          kind: 'golden_sem_revisor',
          message: `Caso "${testCase.id}" sem revisao clinica`,
        });
      }
    } else {
      const problemas =
        revisao.estado === 'invalida'
          ? revisao.problemas
          : revisao.revisores.length < MIN_REVISORES
            ? [`reviewed_by: menos de ${MIN_REVISORES} revisor(es)`]
            : conferirContraRegistro(revisao.revisores, opcoes.registro);
      if (problemas.length > 0) {
        issues.push({
          kind: 'golden_revisao_invalida',
          message: `Caso "${testCase.id}": revisao invalida — ${problemas.join('; ')}`,
        });
      }
    }

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
