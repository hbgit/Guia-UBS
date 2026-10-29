/**
 * As migracoes e os gatilhos aplicam limpo, e o que esta no disco corresponde ao
 * que o gerador produz agora.
 *
 * O ultimo ponto e o que impede o modo de falha mais desagradavel deste item:
 * alguem acrescenta tabela a `APPEND_ONLY_TABLES`, esquece `npm run cms:triggers`,
 * e o banco de producao fica com uma trilha de auditoria editavel — sem erro, sem
 * log, sem sintoma ate o dia em que importa.
 */
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { after, before, test } from 'node:test';

import { createClient } from '@libsql/client';

import { getTableName, is } from 'drizzle-orm';
import { SQLiteTable } from 'drizzle-orm/sqlite-core';

import {
  migrationStatements,
  splitStatements,
  triggerStatementsFromDisk,
} from '../src/db/client.js';
import * as schema from '../src/db/schema/index.js';
import { buildTriggerSql, triggerStatements } from '../src/db/triggers.js';
import { preCondicao0009 } from '../scripts/migrate.js';
import { freshDatabase, seedIdentity, type TestDatabase } from './support/db.js';

let fixture: TestDatabase;

before(() => {
  fixture = freshDatabase();
  seedIdentity(fixture.db);
});

after(() => fixture.close());

test('toda tabela exportada pelo schema existe no banco migrado', () => {
  const existentes = new Set(
    (
      fixture.db.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").all() as {
        name: string;
      }[]
    ).map((row) => row.name),
  );

  let contadas = 0;
  for (const exported of Object.values(schema)) {
    if (!is(exported, SQLiteTable)) continue;
    contadas += 1;
    const name = getTableName(exported);
    assert.ok(existentes.has(name), `"${name}" e exportada pelo schema e nao existe no banco`);
  }
  assert.ok(contadas >= 28, `so ${contadas} tabelas encontradas no schema`);
});

test('a integridade referencial fecha depois de migrar', () => {
  const orfaos = fixture.db.prepare('PRAGMA foreign_key_check').all();
  assert.deepEqual(orfaos, [], 'PRAGMA foreign_key_check acusou orfaos');
});

test('as FKs estao ligadas NESTE fixture', () => {
  // Afirmacao fraca de proposito, e vale dizer por que: ela le a pragma que o
  // proprio `freshDatabase()` acabou de ligar, entao so garante que o fixture
  // esta coerente com o que diz ser. A garantia sobre o PRODUTO — que o caminho
  // de runtime recusa referencia invalida — esta em `foreign-keys.test.ts`, e e
  // sobre comportamento.
  const [flag] = fixture.db.prepare('PRAGMA foreign_keys').all() as { foreign_keys: number }[];
  assert.equal(flag?.foreign_keys, 1);
});

test('triggers.sql no disco e identico ao que o gerador produz agora', () => {
  // O mesmo contrato que `contract:check` tem para os JSON Schemas, so que
  // verificado tambem aqui: quem rodar `npm test` sem passar pelo CI ja
  // descobre que esqueceu de regenerar.
  assert.deepEqual(
    triggerStatementsFromDisk(),
    triggerStatements(),
    'src/db/triggers.sql esta desatualizado — rode `npm run cms:triggers`',
  );
});

test('o gerador e deterministico', () => {
  assert.equal(buildTriggerSql(), buildTriggerSql());
});

test('cada gatilho tem o DROP correspondente antes do CREATE', () => {
  // E o que torna `triggers.sql` reaplicavel a cada migracao. Um CREATE sem DROP
  // falharia na segunda execucao e derrubaria a migracao inteira.
  const statements = triggerStatementsFromDisk();
  for (let i = 0; i < statements.length; i += 2) {
    const drop = statements[i]!;
    const create = statements[i + 1]!;
    assert.match(drop, /^DROP TRIGGER IF EXISTS `(.+)`$/);
    const nome = drop.match(/`(.+)`/)![1];
    assert.ok(
      create.startsWith(`CREATE TRIGGER \`${nome}\``),
      `o DROP de "${nome}" nao e seguido do CREATE dele`,
    );
  }
});

test('reaplicar os gatilhos e idempotente', () => {
  for (const statement of triggerStatementsFromDisk()) fixture.db.exec(statement);
  for (const statement of triggerStatementsFromDisk()) fixture.db.exec(statement);

  const gatilhos = fixture.db
    .prepare("SELECT name FROM sqlite_master WHERE type = 'trigger'")
    .all() as { name: string }[];
  assert.equal(gatilhos.length, triggerStatementsFromDisk().length / 2);
});

test('os gatilhos continuam valendo depois de reaplicados', () => {
  // Idempotencia sem comportamento seria um DROP que apaga e um CREATE que erra.
  fixture.db.exec(`
    INSERT INTO audit_entry (id, actor_id, action, entity_type, entity_id, occurred_at)
    VALUES ('audit-reaplicado', 'admin-1', 'create', 'card', 'card.x', '2026-08-23T12:00:00Z');
  `);
  assert.throws(
    () => fixture.db.exec("DELETE FROM audit_entry WHERE id = 'audit-reaplicado'"),
    /append-only/,
  );
});

test('as migracoes trazem tabelas antes dos gatilhos', () => {
  // Um gatilho sobre tabela inexistente falha na criacao. A ordem sai de
  // `migrationStatements()`, e nao da ordem alfabetica de um diretorio.
  const statements = migrationStatements();
  const primeiroGatilho = statements.findIndex((s) => s.startsWith('DROP TRIGGER'));
  const ultimaTabela = statements.map((s) => s.startsWith('CREATE TABLE')).lastIndexOf(true);
  assert.ok(primeiroGatilho > ultimaTabela, 'ha gatilho sendo criado antes da ultima tabela');
});

// ---------------------------------------------------------------------------
// 0009: golden_case perde `reviewed_by`, revisao vira tabela append-only
// ---------------------------------------------------------------------------

const MIGRATIONS_DIR = join(import.meta.dirname, '..', 'src', 'db', 'migrations');

/**
 * Sentencas de UMA migracao, pelo indice do journal — a ordem que o migrador do
 * drizzle usa em producao, e nao a do diretorio.
 */
function migracao(idx: number): string[] {
  const journal = JSON.parse(
    readFileSync(join(MIGRATIONS_DIR, 'meta', '_journal.json'), 'utf8'),
  ) as { entries: { idx: number; tag: string }[] };
  const entrada = journal.entries.find((e) => e.idx === idx);
  assert.ok(entrada, `migracao ${idx} fora do journal`);
  return splitStatements(readFileSync(join(MIGRATIONS_DIR, `${entrada.tag}.sql`), 'utf8'));
}

/** Banco como estava em producao antes da 0009: 0000..0008 MAIS os gatilhos. */
function bancoAte0008(): DatabaseSync {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON');
  for (let i = 0; i <= 8; i += 1) for (const s of migracao(i)) db.exec(s);
  // Os gatilhos de entao: os de hoje menos os da tabela que a 0009 cria.
  for (const s of triggerStatementsFromDisk()) {
    if (!s.includes('golden_case_review')) db.exec(s);
  }
  db.exec(`INSERT INTO admin_user (id, email, name, role, created_at, updated_at)
           VALUES ('admin-1', 'op@exemplo.invalid', 'Operador', 'editor', 0, 0)`);
  return db;
}

test('golden_case ativo e sem revisor sobrevive a 0009', () => {
  const db = bancoAte0008();
  try {
    db.exec(`INSERT INTO golden_case
               (id, tokens_json, expected_outcome_id, clinical_source, added_by, reviewed_by, active)
             VALUES ('g-1', '["chest","pain"]', 'EMERGENCY', 'ficticio', 'admin-1', NULL, 1)`);

    for (const s of migracao(9)) db.exec(s);

    const linha = db.prepare("SELECT * FROM golden_case WHERE id = 'g-1'").get();
    assert.deepEqual(
      { ...linha },
      {
        id: 'g-1',
        tokens_json: '["chest","pain"]',
        expected_outcome_id: 'EMERGENCY',
        clinical_source: 'ficticio',
        added_by: 'admin-1',
        active: 1,
      },
    );
    const revisoes = db.prepare('SELECT COUNT(*) AS n FROM golden_case_review').get() as {
      n: number;
    };
    assert.equal(revisoes.n, 0, 'a migracao nao inventa revisao');
  } finally {
    db.close();
  }
});

test('todo gatilho do triggers.sql existe no banco depois de migrar', () => {
  // O caminho de `runMigrations()` num banco que JA existia: migracao pendente
  // (que reconstroi `golden_case`) e entao os gatilhos. Um banco novo nao
  // exercita a reconstrucao, e e nela que um gatilho some.
  const db = bancoAte0008();
  try {
    for (const s of migracao(9)) db.exec(s);
    for (const s of triggerStatementsFromDisk()) db.exec(s);

    const existentes = new Set(
      (
        db.prepare("SELECT name FROM sqlite_master WHERE type = 'trigger'").all() as {
          name: string;
        }[]
      ).map((r) => r.name),
    );
    const esperados = triggerStatementsFromDisk()
      .filter((s) => s.startsWith('DROP TRIGGER'))
      .map((s) => s.match(/`(.+)`/)![1]!);
    assert.ok(esperados.includes('golden_case_review_no_update'));
    assert.ok(esperados.includes('golden_case_review_no_delete'));
    for (const nome of esperados) assert.ok(existentes.has(nome), `gatilho "${nome}" ausente`);
  } finally {
    db.close();
  }
});

test('pre-condicao da 0009 acusa reviewed_by preenchido', async () => {
  // A 0009 descarta a coluna. Um revisor gravado nela sumiria em silencio — e
  // `reviewed_by` era FK para operador, nao atestado: nao ha para onde copiar.
  const diretorio = mkdtempSync(join(tmpdir(), 'gubs-0009-'));
  const client = createClient({ url: `file:${join(diretorio, 'cms.db')}` });
  try {
    for (let i = 0; i <= 8; i += 1) for (const s of migracao(i)) await client.execute(s);
    await client.execute(`INSERT INTO admin_user (id, email, name, role, created_at, updated_at)
                          VALUES ('admin-1', 'op@exemplo.invalid', 'Operador', 'editor', 0, 0)`);
    await client.execute(`INSERT INTO golden_case
               (id, tokens_json, expected_outcome_id, added_by, reviewed_by, active)
             VALUES ('g-revisado', '["chest"]', 'EMERGENCY', 'admin-1', 'admin-1', 1),
                    ('g-pendente', '["chest"]', 'EMERGENCY', 'admin-1', NULL, 1)`);

    assert.deepEqual(await preCondicao0009(client), ['g-revisado']);

    // Depois da 0009 a coluna nao existe, e a pre-condicao nao pode quebrar.
    await client.execute("UPDATE golden_case SET reviewed_by = NULL WHERE id = 'g-revisado'");
    for (const s of migracao(9)) await client.execute(s);
    assert.deepEqual(await preCondicao0009(client), []);
  } finally {
    client.close();
    rmSync(diretorio, { recursive: true, force: true });
  }
});
