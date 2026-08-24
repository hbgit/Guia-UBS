/**
 * Banco de teste: as MESMAS migracoes e os MESMOS gatilhos que vao para o `sqld`,
 * aplicados num SQLite em memoria.
 *
 * `node:sqlite` e nao um container: libSQL e um fork do SQLite e nada do que
 * estes testes verificam — gatilho, RAISE(ABORT), CHECK, FK — difere entre os
 * dois. Exigir docker para rodar `npm test` custaria mais do que compra. A
 * verificacao contra o `sqld` de verdade esta no roteiro do item, e roda uma vez.
 *
 * Todos os dados abaixo sao FICTICIOS: dominio `.invalid`, codigo de municipio
 * `0000000`, hashes constantes. Nenhuma pessoa, operador ou municipio real.
 */
import { DatabaseSync } from 'node:sqlite';

import { migrationStatements } from '../../src/db/client.js';

export interface TestDatabase {
  db: DatabaseSync;
  close(): void;
}

/** Banco vazio com schema e gatilhos aplicados e FKs ligadas. */
export function freshDatabase(): TestDatabase {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON');
  for (const statement of migrationStatements()) db.exec(statement);
  return { db, close: () => db.close() };
}

const NOW = '2026-08-23T12:00:00Z';
/** O mesmo instante em milissegundos, para as colunas que o Better Auth possui. */
const NOW_MS = Date.parse(NOW);

/** Colunas de autoria, ja preenchidas — toda linha de conteudo precisa das tres. */
const AUTHORING = `1, 'admin-1', '${NOW}'`;

/**
 * Operador, municipio e um release — o minimo para as FKs das tabelas
 * append-only fecharem.
 */
export function seedIdentity(db: DatabaseSync): void {
  // `created_at`/`updated_at` sao INTEGER de milissegundos nesta tabela, e nao
  // TEXT como no resto do banco: o Better Auth passa objetos `Date` ao adapter.
  // A senha NAO mora aqui — vai para `account.password` (ver `authenticatedUser`).
  db.exec(`
    INSERT INTO admin_user (id, email, name, role, created_at, updated_at)
    VALUES ('admin-1', 'editor@exemplo.invalid', 'Operador Um', 'editor', ${NOW_MS}, ${NOW_MS});
  `);
  db.exec(`
    INSERT INTO municipality (id, code, name) VALUES ('mun-1', '0000000', 'Municipio Exemplo');
  `);
  db.exec(`
    INSERT INTO pack_release
      (id, municipality_id, pack_version, schema_version, status, created_by, created_at)
    VALUES ('rel-1', 'mun-1', 1, '1.0', 'draft', 'admin-1', '${NOW}');
  `);
}

/**
 * Cadeia clinica completa: asset -> card/venue -> routing_outcome -> routing_rule.
 *
 * Existe porque `routing_rule` e a unica tabela com gatilho de imutabilidade
 * apos aprovacao, e chegar ate ela exige quatro FKs satisfeitas.
 */
export function seedClinicalChain(db: DatabaseSync): void {
  db.exec(`
    INSERT INTO asset (ref, kind, path, sha256, bytes, storage_key, version, updated_by, updated_at)
    VALUES ('icon.exemplo', 'icon', 'assets/exemplo.svg', '${'a'.repeat(64)}', 128,
            'assets/exemplo.svg', ${AUTHORING});
  `);
  db.exec(`
    INSERT INTO card (id, kind, icon_ref, color_token, sort_order, version, updated_by, updated_at)
    VALUES ('card.rotina', 'result', 'icon.exemplo', 'green', 0, ${AUTHORING});
  `);
  db.exec(`
    INSERT INTO venue (id, icon_ref, color_token, sort_order, version, updated_by, updated_at)
    VALUES ('UBS', 'icon.exemplo', 'green', 0, ${AUTHORING});
  `);
  db.exec(`
    INSERT INTO routing_outcome
      (id, severity_level, card_id, venue_id, version, updated_by, updated_at)
    VALUES ('ROUTINE_UBS', 10, 'card.rotina', 'UBS', ${AUTHORING});
  `);
  db.exec(`
    INSERT INTO routing_rule
      (id, priority, outcome_id, status, version, updated_by, updated_at)
    VALUES ('rule-1', 100, 'ROUTINE_UBS', 'draft', ${AUTHORING});
  `);
}

/**
 * Uma linha valida por tabela append-only, indexada pelo NOME da tabela.
 *
 * O teste exige que toda tabela de `APPEND_ONLY_TABLES` tenha entrada aqui —
 * acrescentar tabela a constante sem escrever a linha reprova, em vez de o teste
 * silenciosamente pular a tabela nova.
 */
export const APPEND_ONLY_ROWS: Readonly<Record<string, { insert: string; id: string }>> = {
  audit_entry: {
    id: 'audit-1',
    insert: `INSERT INTO audit_entry
       (id, actor_id, action, entity_type, entity_id, occurred_at)
     VALUES ('audit-1', 'admin-1', 'update', 'card', 'card.rotina', '${NOW}')`,
  },
  consent_record: {
    id: 'consent-1',
    insert: `INSERT INTO consent_record
       (id, subject_ref, doc_type, doc_version, doc_hash, method, accepted_at)
     VALUES ('consent-1', 'sujeito-ficticio-1', 'tos', '1.0.0', '${'b'.repeat(64)}',
             'web', '${NOW}')`,
  },
  approval: {
    id: 'approval-1',
    insert: `INSERT INTO approval
       (id, pack_release_id, approver_id, role, decision, decided_at)
     VALUES ('approval-1', 'rel-1', 'admin-1', 'clinical_reviewer', 'approve', '${NOW}')`,
  },
};
