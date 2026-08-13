/**
 * Constroi o `content.db` a partir do DDL gerado pelo contrato e do SQL semente.
 *
 * O DDL NAO e escrito a mao: vem de `contract/ddl/`, gerado por drizzle-kit a
 * partir de `contract/src/content-schema.ts` — a mesma fonte que alimenta o
 * codegen. Nao existe segunda definicao do schema para sair de sincronia.
 */
import { createHash } from 'node:crypto';
import { mkdirSync, readdirSync, readFileSync, rmSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

import type { Outcome, Rule, RuleTerm } from './rules.js';

export interface BuildOptions {
  repoRoot: string;
  outDir: string;
  packVersion: number;
  schemaVersion: string;
  municipality: string;
  defaultOutcomeId: string;
  sourceCommit: string;
}

export interface BuildResult {
  dbPath: string;
  assets: { ref: string; path: string; sha256: string; bytes: number }[];
}

/** O DDL do drizzle-kit separa comandos com este marcador. */
const STATEMENT_BREAK = '--> statement-breakpoint';

function readDdl(repoRoot: string): string[] {
  const ddlDir = join(repoRoot, 'contract', 'ddl');
  const files = readdirSync(ddlDir)
    .filter((f) => f.endsWith('.sql'))
    .sort();
  if (files.length === 0) {
    throw new Error('contract/ddl vazio — rode `npx drizzle-kit generate` no workspace contract');
  }
  return files.flatMap((file) =>
    readFileSync(join(ddlDir, file), 'utf8')
      .split(STATEMENT_BREAK)
      .map((s) => s.trim())
      .filter(Boolean),
  );
}

function readSeedFiles(repoRoot: string): { name: string; sql: string }[] {
  const seedDir = join(repoRoot, 'seed');
  return readdirSync(seedDir)
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .map((name) => ({ name, sql: readFileSync(join(seedDir, name), 'utf8') }));
}

export function buildPack(options: BuildOptions): BuildResult {
  const { repoRoot, outDir } = options;
  mkdirSync(outDir, { recursive: true });

  const dbPath = join(outDir, 'content.db');
  rmSync(dbPath, { force: true });

  const db = new DatabaseSync(dbPath);
  try {
    // FKs ligadas durante a carga: um orfao falha aqui, antes de qualquer
    // validacao semantica — defesa em profundidade junto de validate.ts.
    db.exec('PRAGMA foreign_keys = ON');

    for (const statement of readDdl(repoRoot)) db.exec(statement);
    for (const { name, sql } of readSeedFiles(repoRoot)) {
      try {
        db.exec(sql);
      } catch (cause) {
        throw new Error(`Falha ao carregar seed/${name}: ${(cause as Error).message}`);
      }
    }

    // Hash e tamanho reais dos arquivos substituem os placeholders do SQL.
    const assets = db.prepare('SELECT ref, path FROM asset ORDER BY ref').all() as {
      ref: string;
      path: string;
    }[];
    const update = db.prepare('UPDATE asset SET sha256 = ?, bytes = ? WHERE ref = ?');
    const resolved: BuildResult['assets'] = [];

    for (const { ref, path } of assets) {
      const filePath = join(repoRoot, 'seed', path);
      let bytes: number;
      let content: Buffer;
      try {
        content = readFileSync(filePath);
        bytes = statSync(filePath).size;
      } catch {
        throw new Error(
          `Asset "${ref}" aponta para seed/${path}, que nao existe. ` +
            'Rode `node seed/assets/generate-placeholders.mjs`.',
        );
      }
      const sha256 = createHash('sha256').update(content).digest('hex');
      update.run(sha256, bytes, ref);
      resolved.push({ ref, path, sha256, bytes });
    }

    db.prepare(
      `INSERT INTO pack_meta
         (id, pack_version, schema_version, municipality_code, built_at,
          default_outcome_id, source_commit)
       VALUES (1, ?, ?, ?, ?, ?, ?)`,
    ).run(
      options.packVersion,
      options.schemaVersion,
      options.municipality,
      new Date().toISOString(),
      options.defaultOutcomeId,
      options.sourceCommit,
    );

    // Compacta: o pack e distribuido para dispositivos com pouco espaco.
    db.exec('VACUUM');
    return { dbPath, assets: resolved };
  } finally {
    db.close();
  }
}

/** Le regras e desfechos de um pack ja construido — usado pela suite golden. */
export function readRuleModel(dbPath: string): {
  rules: Rule[];
  outcomes: Map<string, Outcome>;
  defaultOutcomeId: string;
  tokenIds: Set<string>;
} {
  const db = new DatabaseSync(dbPath, { readOnly: true });
  try {
    const outcomes = new Map<string, Outcome>();
    for (const row of db.prepare('SELECT id, severity_level FROM routing_outcome').all() as {
      id: string;
      severity_level: number;
    }[]) {
      outcomes.set(row.id, { id: row.id, severityLevel: row.severity_level });
    }

    const termsByRule = new Map<string, RuleTerm[]>();
    for (const row of db
      .prepare('SELECT rule_id, group_no, token_id, negated FROM routing_rule_term')
      .all() as { rule_id: string; group_no: number; token_id: string; negated: number }[]) {
      const term: RuleTerm = {
        groupNo: row.group_no,
        tokenId: row.token_id,
        negated: row.negated === 1,
      };
      const bucket = termsByRule.get(row.rule_id);
      if (bucket) bucket.push(term);
      else termsByRule.set(row.rule_id, [term]);
    }

    const rules = (
      db.prepare('SELECT id, priority, outcome_id FROM routing_rule ORDER BY priority').all() as {
        id: string;
        priority: number;
        outcome_id: string;
      }[]
    ).map((row) => ({
      id: row.id,
      priority: row.priority,
      outcomeId: row.outcome_id,
      terms: termsByRule.get(row.id) ?? [],
    }));

    const meta = db.prepare('SELECT default_outcome_id FROM pack_meta WHERE id = 1').get() as {
      default_outcome_id: string;
    };

    const tokenIds = new Set(
      (db.prepare('SELECT id FROM symptom_token').all() as { id: string }[]).map((r) => r.id),
    );

    return { rules, outcomes, defaultOutcomeId: meta.default_outcome_id, tokenIds };
  } finally {
    db.close();
  }
}
