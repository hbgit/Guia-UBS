/**
 * As tabelas append-only recusam UPDATE e DELETE — no BANCO, nao na aplicacao.
 *
 * A diferenca e a ameaca que se esta cobrindo. Uma checagem na rota protege
 * contra a rota; o gatilho protege contra a rota, contra um bug de ORM, contra
 * um script de manutencao e contra uma sessao comprometida com acesso ao shell
 * do banco. O que se pretende provar sobre estas tres tabelas — que a trilha e
 * irrefutavel — so vale sob a segunda protecao.
 *
 * O teste percorre `APPEND_ONLY_TABLES`, nao uma lista propria: acrescentar
 * tabela a constante sem regenerar `triggers.sql` reprova aqui, porque a linha
 * nova sera atualizavel.
 */
import assert from 'node:assert/strict';
import { after, before, describe, test } from 'node:test';

import { getTableName } from 'drizzle-orm';

import { APPEND_ONLY_TABLES } from '../src/db/schema/index.js';
import { APPEND_ONLY_ROWS, freshDatabase, seedIdentity, type TestDatabase } from './support/db.js';

let fixture: TestDatabase;

before(() => {
  fixture = freshDatabase();
  seedIdentity(fixture.db);
});

after(() => fixture.close());

test('toda tabela append-only tem linha de exemplo no suporte de teste', () => {
  // Sem isto, acrescentar uma tabela a constante e esquecer a linha faria o
  // `describe` abaixo rodar zero asserts para ela — verde por vacuidade.
  for (const { table } of APPEND_ONLY_TABLES) {
    const name = getTableName(table);
    assert.ok(
      name in APPEND_ONLY_ROWS,
      `"${name}" esta em APPEND_ONLY_TABLES e nao tem linha em APPEND_ONLY_ROWS`,
    );
  }
});

for (const { table, requirement } of APPEND_ONLY_TABLES) {
  const name = getTableName(table);

  describe(`${name} (${requirement})`, () => {
    before(() => {
      const row = APPEND_ONLY_ROWS[name];
      assert.ok(row, `sem linha de exemplo para ${name}`);
      fixture.db.exec(row.insert);
    });

    test('INSERT continua permitido — append-only nao e read-only', () => {
      const count = fixture.db.prepare(`SELECT COUNT(*) AS n FROM ${name}`).get() as { n: number };
      assert.equal(count.n, 1);
    });

    test('UPDATE e recusado', () => {
      const row = APPEND_ONLY_ROWS[name]!;
      assert.throws(
        () => fixture.db.exec(`UPDATE ${name} SET id = 'reescrito' WHERE id = '${row.id}'`),
        /append-only/,
      );
    });

    test('DELETE e recusado', () => {
      const row = APPEND_ONLY_ROWS[name]!;
      assert.throws(
        () => fixture.db.exec(`DELETE FROM ${name} WHERE id = '${row.id}'`),
        /append-only/,
      );
    });

    test('a linha continua la depois das duas tentativas', () => {
      const row = APPEND_ONLY_ROWS[name]!;
      const found = fixture.db.prepare(`SELECT id FROM ${name} WHERE id = ?`).get(row.id) as
        | { id: string }
        | undefined;
      assert.equal(found?.id, row.id, 'a tentativa recusada nao pode ter efeito parcial');
    });

    test('a mensagem de erro nomeia o requisito', () => {
      // Quem topar com isso em producao precisa entender por que a operacao foi
      // recusada sem ter que ler o gerador de gatilhos.
      const row = APPEND_ONLY_ROWS[name]!;
      assert.throws(
        () => fixture.db.exec(`DELETE FROM ${name} WHERE id = '${row.id}'`),
        new RegExp(requirement.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
      );
    });
  });
}

test('DELETE em massa tambem e recusado (nao so a linha nomeada)', () => {
  // Um gatilho BEFORE DELETE dispara por LINHA: sobre tabela vazia nao dispara
  // nada, e um `DELETE FROM t` sem WHERE passaria despercebido. Com linha
  // presente, o comando inteiro aborta.
  assert.throws(() => fixture.db.exec('DELETE FROM audit_entry'), /append-only/);
});
