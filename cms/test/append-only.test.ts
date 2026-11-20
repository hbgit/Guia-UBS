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
import {
  APPEND_ONLY_ROWS,
  freshDatabase,
  seedClinicalChain,
  seedIdentity,
  type TestDatabase,
} from './support/db.js';

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

test('o piso das tabelas append-only nao encolhe (remover da constante tambem tiraria o gatilho)', () => {
  // A constante alimenta o gerador de gatilhos E o `describe` abaixo: tirar uma
  // tabela dela remove o gatilho e o teste do gatilho juntos, e tudo fica verde.
  // Este piso e literal de proposito — encolher a lista exige editar aqui.
  const piso = [
    'audit_entry',
    'consent_record',
    'approval',
    'golden_case_review',
    'golden_case_review_revocation',
  ];
  const nomes = APPEND_ONLY_TABLES.map(({ table }) => getTableName(table));
  for (const nome of piso) {
    assert.ok(nomes.includes(nome), `"${nome}" saiu de APPEND_ONLY_TABLES`);
    const gatilhos = fixture.db
      .prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'trigger' AND tbl_name = ?")
      .get(nome) as { n: number };
    assert.ok(gatilhos.n >= 2, `"${nome}" sem gatilho de UPDATE e DELETE no banco`);
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

// ---------------------------------------------------------------------------
// #43: revogacao, uma revisao viva por atestado e desativacao definitiva
// ---------------------------------------------------------------------------

describe('golden: gatilhos da #43', () => {
  let g: TestDatabase;
  const NOW = '2026-11-20T12:00:00Z';
  const revisao = (id: string, caso = 'g-exemplo') =>
    g.db.exec(`INSERT INTO golden_case_review
      (id, case_id, attestation_id, reviewed_at, reviewed_hash, recorded_by, recorded_at)
      VALUES ('${id}', '${caso}', 'AT-9001', '2026-11-19', '${'d'.repeat(64)}', 'admin-1', '${NOW}')`);
  const revogar = (id: string, review: string, motivo = 'motivo ficticio de teste') =>
    g.db.exec(`INSERT INTO golden_case_review_revocation (id, review_id, reason, revoked_by, revoked_at)
      VALUES ('${id}', '${review}', '${motivo}', 'admin-2', '${NOW}')`);
  const desativar = (id: string) =>
    g.db.exec(`UPDATE golden_case SET active = 0, deactivated_at = '${NOW}' WHERE id = '${id}'`);
  const caso = (id: string, desfecho: string) =>
    g.db.exec(`INSERT INTO golden_case (id, tokens_json, expected_outcome_id, added_by, active)
      VALUES ('${id}', '["chest"]', '${desfecho}', 'admin-1', 1)`);

  before(() => {
    g = freshDatabase();
    seedIdentity(g.db);
  });
  after(() => g.close());

  test('desativar com routing_outcome vazia aborta (fail-closed)', () => {
    assert.throws(() => desativar('g-exemplo'), /CHECK constraint failed: golden_case red flag/);
  });

  test('segunda revisao nao revogada do mesmo atestado aborta como duplicidade; revogada a primeira, entra', () => {
    revisao('rv-a');
    assert.throws(() => revisao('rv-b'), /UNIQUE constraint failed/);
    revogar('vg-a', 'rv-a');
    revisao('rv-b');
  });

  test('revogacao com motivo so de espacos e tabs viola CHECK', () => {
    // 12 caracteres em branco: o trim() do SQLite sem 2o argumento so tira espaco.
    assert.throws(
      () => revogar('vg-branco', 'rv-b', ' \t'.repeat(6)),
      /CHECK constraint failed/,
    );
    assert.throws(() => revogar('vg-curto', 'rv-b', 'curto'), /CHECK constraint failed/);
  });

  test('segunda revogacao da mesma revisao viola UNIQUE', () => {
    assert.throws(() => revogar('vg-a2', 'rv-a'), /UNIQUE constraint failed/);
  });

  test('desativar caso de severidade maxima aborta; desfecho inexistente aborta; rotina passa', () => {
    seedClinicalChain(g.db);
    g.db.exec(`INSERT INTO routing_outcome
      (id, severity_level, card_id, venue_id, version, updated_by, updated_at)
      VALUES ('EMERGENCY', 100, 'card.rotina', 'UBS', 1, 'admin-1', '${NOW}')`);
    caso('g-emerg', 'EMERGENCY');
    caso('g-fantasma', 'NAO_EXISTE');
    assert.throws(() => desativar('g-emerg'), /CHECK constraint failed: golden_case red flag/);
    assert.throws(() => desativar('g-fantasma'), /CHECK constraint failed: golden_case red flag/);
    desativar('g-exemplo');
    const linha = g.db
      .prepare("SELECT active, deactivated_at FROM golden_case WHERE id = 'g-exemplo'")
      .get() as { active: number; deactivated_at: string | null };
    assert.deepEqual({ ...linha }, { active: 0, deactivated_at: NOW });
  });

  test('caso desativado nao volta: UPDATE active=1 aborta, UPDATE deactivated_at=NULL aborta', () => {
    assert.throws(
      () => g.db.exec("UPDATE golden_case SET active = 1 WHERE id = 'g-exemplo'"),
      /CHECK constraint failed: golden_case desativado e definitivo/,
    );
    assert.throws(
      () => g.db.exec("UPDATE golden_case SET deactivated_at = NULL WHERE id = 'g-exemplo'"),
      /CHECK constraint failed: golden_case desativado e definitivo/,
    );
  });
});
