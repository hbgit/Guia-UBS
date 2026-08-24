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
import { after, before, test } from 'node:test';

import { getTableName, is } from 'drizzle-orm';
import { SQLiteTable } from 'drizzle-orm/sqlite-core';

import { migrationStatements, triggerStatementsFromDisk } from '../src/db/client.js';
import * as schema from '../src/db/schema/index.js';
import { buildTriggerSql, triggerStatements } from '../src/db/triggers.js';
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

test('as FKs estao ligadas — sem isso, metade das guardas nao existe', () => {
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
