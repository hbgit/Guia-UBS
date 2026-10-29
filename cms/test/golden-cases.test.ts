/**
 * Atestado de revisor e revisao de caso golden — as restricoes que moram no
 * BANCO (spec P0-2, decisao D6).
 *
 * A rota do CMS tambem valida o formato pelo contrato; estas restricoes existem
 * para o caminho que nao passa pela rota: um script de manutencao, um bug de ORM,
 * uma sessao com acesso ao shell do banco. Os `CHECK`s sao montados das
 * constantes de `@guia-ubs/contract`, entao conselho ou UF novos no contrato
 * chegam aqui por regeneracao, nao por edicao a mao.
 *
 * Todos os dados sao FICTICIOS: nome inventado, IDs AT-9xxx, registros zerados.
 */
import assert from 'node:assert/strict';
import { after, beforeEach, test } from 'node:test';

import { freshDatabase, seedIdentity, type TestDatabase } from './support/db.js';

let fixture: TestDatabase;

beforeEach(() => {
  fixture?.close();
  fixture = freshDatabase();
  seedIdentity(fixture.db);
});

after(() => fixture.close());

const TERMO = (c: string) => c.repeat(64);

/** Insere um atestado; os campos omitidos recebem um valor valido de CRM. */
function atestado(campos: {
  id?: string;
  conselho?: string;
  uf?: string;
  categoria?: string | null;
  registro?: string;
  termo?: string;
}): void {
  const c = {
    id: 'AT-9002',
    conselho: 'CRM',
    uf: 'RR',
    categoria: null,
    registro: '111111',
    termo: TERMO('d'),
    ...campos,
  };
  fixture.db
    .prepare(
      `INSERT INTO golden_attestation
         (id, nome, conselho, uf, categoria, registro, termo_sha256, created_by, created_at)
       VALUES (?, 'Revisora Ficticia Teste', ?, ?, ?, ?, ?, 'admin-1', '2026-08-23T12:00:00Z')`,
    )
    .run(c.id, c.conselho, c.uf, c.categoria, c.registro, c.termo);
}

test('um atestado de CRM valido entra', () => {
  atestado({});
  const n = fixture.db.prepare('SELECT COUNT(*) AS n FROM golden_attestation').get() as {
    n: number;
  };
  // O do fixture (COREN/ENF) mais este.
  assert.equal(n.n, 2);
});

test('o banco recusa conselho fora da lista', () => {
  assert.throws(() => atestado({ conselho: 'CRF' }), /CHECK constraint failed/);
});

test('o banco recusa UF fora das 27', () => {
  assert.throws(() => atestado({ uf: 'XX' }), /CHECK constraint failed/);
  assert.throws(() => atestado({ uf: 'rr' }), /CHECK constraint failed/);
});

test('o banco recusa COREN sem ENF e CRM com categoria', () => {
  // COREN de tecnico (TE) e o caso real que a regra barra: a inscricao existe,
  // e valida, e nao habilita a revisar triagem.
  assert.throws(() => atestado({ conselho: 'COREN', categoria: 'TE' }), /CHECK constraint failed/);
  assert.throws(() => atestado({ conselho: 'COREN', categoria: null }), /CHECK constraint failed/);
  assert.throws(() => atestado({ conselho: 'CRM', categoria: 'ENF' }), /CHECK constraint failed/);
});

test('o banco recusa o mesmo profissional sob dois IDs', () => {
  // Dois IDs para a mesma pessoa fariam um revisor contar como dois quando
  // `MIN_REVISORES` subir.
  atestado({ id: 'AT-9002', registro: '222222', termo: TERMO('d') });
  assert.throws(
    () => atestado({ id: 'AT-9003', registro: '222222', termo: TERMO('e') }),
    /UNIQUE constraint failed/,
  );
});

test('o banco recusa o mesmo termo em dois atestados', () => {
  // Um termo assinado e de uma pessoa: reaproveita-lo seria atestar por outra.
  atestado({ id: 'AT-9002', registro: '333333', termo: TERMO('f') });
  assert.throws(
    () => atestado({ id: 'AT-9003', registro: '444444', termo: TERMO('f') }),
    /UNIQUE constraint failed/,
  );
});

test('a mesma pessoa nao revisa o mesmo caso duas vezes', () => {
  const revisar = (id: string) =>
    fixture.db.exec(`INSERT INTO golden_case_review
        (id, case_id, attestation_id, reviewed_at, recorded_by, recorded_at)
      VALUES ('${id}', 'g-exemplo', 'AT-9001', '2026-08-20', 'admin-1', '2026-08-23T12:00:00Z')`);
  revisar('review-a');
  assert.throws(() => revisar('review-b'), /UNIQUE constraint failed/);
});

test('revisao exige caso e atestado existentes', () => {
  assert.throws(
    () =>
      fixture.db.exec(`INSERT INTO golden_case_review
          (id, case_id, attestation_id, reviewed_at, recorded_by, recorded_at)
        VALUES ('review-x', 'g-exemplo', 'AT-9999', '2026-08-20', 'admin-1', '2026-08-23T12:00:00Z')`),
    /FOREIGN KEY constraint failed/,
  );
});
