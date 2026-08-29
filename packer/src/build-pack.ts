/**
 * Constroi o `content.db` a partir do DDL gerado pelo contrato e do SQL semente.
 *
 * O DDL NAO e escrito a mao: vem de `contract/ddl/`, gerado por drizzle-kit a
 * partir de `contract/src/content-schema.ts` — a mesma fonte que alimenta o
 * codegen. Nao existe segunda definicao do schema para sair de sincronia.
 */
import { createHash } from 'node:crypto';
import { mkdirSync, readdirSync, readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

import type { Outcome, Rule, RuleTerm } from '@guia-ubs/contract';

export interface BuildOptions {
  repoRoot: string;
  outDir: string;
  packVersion: number;
  schemaVersion: string;
  municipality: string;
  defaultOutcomeId: string;
  sourceCommit: string;
  /**
   * Sentencas de DADOS a carregar sobre o DDL.
   *
   * Ausente, o pack e construido de `seed/*.sql` — o caminho do CI, que roda em
   * toda PR sem docker. Presente, vem do extrator do banco de autoria
   * (`extract.ts`), que e o caminho do CMS.
   *
   * Os dois entram pelo MESMO construtor e passam pelos MESMOS portoes, de
   * proposito: um segundo construtor para o caminho do banco seria um caminho
   * cujos portoes ninguem exercita em toda PR.
   */
  dataSource?: { name: string; sql: string }[];
  /**
   * Onde os binarios de asset estao no disco. Padrao: `seed/`.
   *
   * E o caminho do CLI e do CI, que rodam sem docker e sem banco de autoria.
   */
  assetRoot?: string;
  /**
   * Binarios ja em memoria, vindos do banco de autoria. Caminho do CMS.
   *
   * Mesma decisao de `dataSource`: ausente, o build vem de `seed/`; presente,
   * vem do banco. **Duas fontes, uma para cada caminho, nunca sincronizadas** —
   * o mesmo precedente da suite golden (YAML para o CI, `golden_case` para o
   * CMS).
   *
   * Ate o item 25 este parametro nao existia, e o docblock do `assetRoot`
   * prometia que "quando o upload chegar, este parametro passa a apontar para o
   * storage". Nao passou: o CMS nao tem credencial com que escrever no storage,
   * entao os bytes moram no banco e chegam aqui pela memoria, lidos por quem ja
   * tem as duas credenciais.
   */
  assetBytes?: ReadonlyMap<string, Buffer>;
}

export interface BuildResult {
  dbPath: string;
  /**
   * `content` viaja junto para o `publish()` nao precisar voltar ao disco — e e
   * o que permitiu `seed/` sumir dos dois chamadores.
   */
  assets: { ref: string; path: string; sha256: string; bytes: number; content: Buffer }[];
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

/**
 * Carimbo de tempo do pack, honrando `SOURCE_DATE_EPOCH`.
 *
 * O pack e distribuido por URL enderecada pelo proprio hash
 * (`pack-<sha256>.db`), e o app so re-baixa quando o hash muda. Com o relogio
 * de parede aqui dentro, DUAS builds do mesmo conteudo produzem hashes
 * diferentes — e cada republicacao sem mudanca de conteudo obriga a frota
 * inteira a re-baixar o pack por uma linha de metadado. Num posto rural isso e
 * a diferenca entre atualizar e nao atualizar.
 *
 * `SOURCE_DATE_EPOCH` e a convencao do reproducible-builds.org, a mesma que o
 * F-Droid usa (stack.md 9). Definida, o build vira deterministico; ausente,
 * cai no relogio como antes.
 */
function buildTimestamp(): string {
  const epoch = process.env.SOURCE_DATE_EPOCH;
  if (epoch && /^\d+$/.test(epoch)) {
    return new Date(Number(epoch) * 1000).toISOString();
  }
  return new Date().toISOString();
}

export function buildPack(options: BuildOptions): BuildResult {
  const { repoRoot, outDir } = options;
  const assetRoot = options.assetRoot ?? join(repoRoot, 'seed');
  mkdirSync(outDir, { recursive: true });

  const dbPath = join(outDir, 'content.db');
  rmSync(dbPath, { force: true });

  const db = new DatabaseSync(dbPath);
  try {
    // FKs ligadas durante a carga: um orfao falha aqui, antes de qualquer
    // validacao semantica — defesa em profundidade junto de validate.ts.
    db.exec('PRAGMA foreign_keys = ON');

    for (const statement of readDdl(repoRoot)) db.exec(statement);
    for (const { name, sql } of options.dataSource ?? readSeedFiles(repoRoot)) {
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
      let content: Buffer;

      if (options.assetBytes) {
        // Caminho do CMS. A mensagem de falta e OUTRA de proposito: mandar um
        // operador do CMS rodar `generate-placeholders.mjs` o faria procurar o
        // problema num diretorio que ele nem usa.
        const doBanco = options.assetBytes.get(ref);
        if (!doBanco) {
          throw new Error(
            `O asset "${ref}" nao tem binario. Envie o arquivo em /conteudo/assets ` +
              'antes de submeter a release — o pack nao pode citar um arquivo que nao existe.',
          );
        }
        content = doBanco;
      } else {
        // Caminho `seed/`: CLI e CI, sem docker e sem banco de autoria.
        try {
          content = readFileSync(join(assetRoot, path));
        } catch {
          throw new Error(
            `Asset "${ref}" aponta para ${path}, que nao existe em ${assetRoot}. ` +
              'Se o build veio de seed/, rode `node seed/assets/generate-placeholders.mjs`.',
          );
        }
      }

      // `byteLength` nos DOIS caminhos: com `statSync` num e `byteLength` no
      // outro, os dois poderiam divergir por um motivo que ninguem procuraria.
      const bytes = content.byteLength;
      const sha256 = createHash('sha256').update(content).digest('hex');

      /**
       * No caminho do CMS, CONFERIR em vez de corrigir.
       *
       * No caminho `seed/` o SQL guarda `sha256 = ''` de proposito, e sobrescrever
       * e o comportamento certo. No caminho do CMS o hash foi calculado pela rota
       * de envio a partir dos MESMOS bytes: divergir significa que o blob e o
       * metadado dessincronizaram, isto e, que houve escrita fora da rota.
       * "Consertar" em silencio esconderia exatamente o evento que vale conhecer.
       */
      if (options.assetBytes) {
        const gravado = db.prepare('SELECT sha256 FROM asset WHERE ref = ?').get(ref) as
          | { sha256?: string }
          | undefined;
        if (gravado?.sha256 && gravado.sha256 !== sha256) {
          throw new Error(
            `O asset "${ref}" tem sha256 ${gravado.sha256} gravado, mas os bytes somam ` +
              `${sha256}. Blob e metadado dessincronizaram — houve escrita fora da rota de envio.`,
          );
        }
      }

      update.run(sha256, bytes, ref);
      resolved.push({ ref, path, sha256, bytes, content });
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
      buildTimestamp(),
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
