/**
 * As invariantes que o banco sustenta sozinho — sem rota, sem ORM, sem sessao.
 *
 * Cada uma existe porque a alternativa (confiar no codigo de aplicacao) falha
 * exatamente no caso em que a protecao importa: quando o codigo de aplicacao e
 * o que esta errado.
 */
import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { getTableName } from 'drizzle-orm';

import { PII_COLUMNS, VERSIONED_TABLES } from '../src/db/schema/index.js';
import { freshDatabase, seedClinicalChain, seedIdentity, type TestDatabase } from './support/db.js';

let fixture: TestDatabase;

before(() => {
  fixture = freshDatabase();
  seedIdentity(fixture.db);
  seedClinicalChain(fixture.db);
});

after(() => fixture.close());

// ---------------------------------------------------------------------------
// Travamento otimista
// ---------------------------------------------------------------------------

test('UPDATE sem incrementar version e recusado', () => {
  // Este e o defeito que o gatilho existe para pegar: sem ele o UPDATE passa, o
  // travamento otimista deixa de valer EM SILENCIO, e o unico sintoma e a
  // edicao de alguem sumindo sem explicacao.
  assert.throws(
    () => fixture.db.exec("UPDATE card SET sort_order = 5 WHERE id = 'card.rotina'"),
    /version precisa subir de 1/,
  );
});

test('UPDATE com version + 1 e aceito', () => {
  fixture.db.exec("UPDATE card SET sort_order = 5, version = version + 1 WHERE id = 'card.rotina'");
  const row = fixture.db
    .prepare("SELECT sort_order, version FROM card WHERE id = 'card.rotina'")
    .get() as { sort_order: number; version: number };
  assert.equal(row.sort_order, 5);
  assert.equal(row.version, 2);
});

test('pular versoes tambem e recusado', () => {
  // Salto denuncia escrita que nao passou pelo caminho do travamento otimista.
  assert.throws(
    () => fixture.db.exec("UPDATE card SET version = version + 7 WHERE id = 'card.rotina'"),
    /version precisa subir de 1/,
  );
});

test('regredir a versao e recusado', () => {
  assert.throws(
    () => fixture.db.exec("UPDATE card SET version = 1 WHERE id = 'card.rotina'"),
    /version precisa subir de 1/,
  );
});

test('toda tabela versionada realmente tem a coluna version', () => {
  for (const table of VERSIONED_TABLES) {
    const name = getTableName(table);
    const columns = fixture.db.prepare(`PRAGMA table_info(${name})`).all() as { name: string }[];
    assert.ok(
      columns.some((column) => column.name === 'version'),
      `${name} esta em VERSIONED_TABLES e nao tem coluna version — o gatilho gerado ` +
        'para ela seria invalido',
    );
  }
});

// ---------------------------------------------------------------------------
// Regra clinica aprovada
// ---------------------------------------------------------------------------

test('regra aprovada recusa UPDATE mesmo com a versao correta', () => {
  fixture.db.exec(
    "UPDATE routing_rule SET status = 'approved', version = version + 1 WHERE id = 'rule-1'",
  );
  assert.throws(
    () =>
      fixture.db.exec(
        "UPDATE routing_rule SET priority = 1, version = version + 1 WHERE id = 'rule-1'",
      ),
    /regra aprovada nao e editada in-place/,
    'a versao correta nao pode servir de porta de entrada para editar conteudo ja revisado',
  );
});

test('regra em rascunho continua editavel', () => {
  fixture.db.exec(`
    INSERT INTO routing_rule (id, priority, outcome_id, status, version, updated_by, updated_at)
    VALUES ('rule-2', 200, 'ROUTINE_UBS', 'draft', 1, 'admin-1', '2026-08-23T12:00:00Z');
  `);
  fixture.db.exec(
    "UPDATE routing_rule SET priority = 150, version = version + 1 WHERE id = 'rule-2'",
  );
  const row = fixture.db.prepare("SELECT priority FROM routing_rule WHERE id = 'rule-2'").get() as {
    priority: number;
  };
  assert.equal(row.priority, 150);
});

// ---------------------------------------------------------------------------
// CHECK: o `enum` do drizzle e so tipagem — estes precisam existir no DDL
// ---------------------------------------------------------------------------

test('papel de admin fora dos tres definidos e recusado', () => {
  assert.throws(
    () =>
      fixture.db.exec(`
        INSERT INTO admin_user (id, email, name, password_hash, role, created_at)
        VALUES ('admin-x', 'x@exemplo.invalid', 'X', 'h', 'superadmin', '2026-08-23T12:00:00Z');
      `),
    /CHECK constraint failed/,
  );
});

test('status de release fora da FSM e recusado', () => {
  assert.throws(
    () =>
      fixture.db.exec(`
        INSERT INTO pack_release
          (id, municipality_id, pack_version, schema_version, status, created_by, created_at)
        VALUES ('rel-x', 'mun-1', 9, '1.0', 'quase_pronto', 'admin-1', '2026-08-23T12:00:00Z');
      `),
    /CHECK constraint failed/,
  );
});

test('cor fora da semantica do design e recusada', () => {
  assert.throws(
    () =>
      fixture.db.exec(`
        INSERT INTO card (id, kind, icon_ref, color_token, sort_order, version, updated_by, updated_at)
        VALUES ('card.x', 'info', 'icon.exemplo', 'lilas', 0, 1, 'admin-1', '2026-08-23T12:00:00Z');
      `),
    /CHECK constraint failed/,
    'lilas e procedencia/automacao e nunca cor de conteudo clinico (CLAUDE.md)',
  );
});

test('lote de telemetria abaixo do k-anonimato e recusado pelo DDL', () => {
  // O validador de aplicacao protege a porta de entrada; este CHECK protege
  // qualquer outra escrita — importacao manual, script, correcao no shell.
  assert.throws(
    () =>
      fixture.db.exec(`
        INSERT INTO telemetry_batch (id, cohort_key, bucket_day, metrics_json, k_count, received_at)
        VALUES ('lote-1', '0000000|1.0.0|1', '2026-08-23', '{}', 19, '2026-08-23T12:00:00Z');
      `),
    /CHECK constraint failed/,
  );
});

// ---------------------------------------------------------------------------
// Anti-downgrade ancorado no banco (INV-7)
// ---------------------------------------------------------------------------

test('duas releases com a mesma versao no mesmo municipio sao recusadas', () => {
  // Reemitir um numero faria metade da frota parar de atualizar sem erro nenhum:
  // cada aparelho ja teria "aquela versao".
  assert.throws(
    () =>
      fixture.db.exec(`
        INSERT INTO pack_release
          (id, municipality_id, pack_version, schema_version, status, created_by, created_at)
        VALUES ('rel-2', 'mun-1', 1, '1.0', 'draft', 'admin-1', '2026-08-23T12:00:00Z');
      `),
    /UNIQUE constraint failed/,
  );
});

test('a mesma versao em municipio diferente e permitida', () => {
  fixture.db.exec(`
    INSERT INTO municipality (id, code, name) VALUES ('mun-2', '1111111', 'Outro Exemplo');
  `);
  fixture.db.exec(`
    INSERT INTO pack_release
      (id, municipality_id, pack_version, schema_version, status, created_by, created_at)
    VALUES ('rel-3', 'mun-2', 1, '1.0', 'draft', 'admin-1', '2026-08-23T12:00:00Z');
  `);
  const row = fixture.db
    .prepare("SELECT pack_version FROM pack_release WHERE id = 'rel-3'")
    .get() as { pack_version: number };
  assert.equal(row.pack_version, 1, 'a versao e monotonica POR municipio, nao global');
});

test('versao zero e recusada', () => {
  assert.throws(
    () =>
      fixture.db.exec(`
        INSERT INTO pack_release
          (id, municipality_id, pack_version, schema_version, status, created_by, created_at)
        VALUES ('rel-4', 'mun-2', 0, '1.0', 'draft', 'admin-1', '2026-08-23T12:00:00Z');
      `),
    /CHECK constraint failed/,
  );
});

// ---------------------------------------------------------------------------
// Superficie de dado pessoal (lgpd.md LGPD-RT02) e INV-2
// ---------------------------------------------------------------------------

test('toda coluna de PII declarada existe no banco', () => {
  // SQLite nao tem `COMMENT ... 'PII'`. Esta lista e o equivalente executavel:
  // renomear uma coluna de dado pessoal sem revisar a LGPD vira build vermelho.
  for (const qualified of PII_COLUMNS) {
    const [table, column] = qualified.split('.');
    const columns = fixture.db.prepare(`PRAGMA table_info(${table})`).all() as { name: string }[];
    assert.ok(
      columns.some((c) => c.name === column),
      `${qualified} esta em PII_COLUMNS e nao existe no schema`,
    );
  }
});

test('nenhuma tabela guarda sequencia de sintomas de usuario final (INV-2)', () => {
  // A unica coluna do banco que menciona tokens e `golden_case.tokens_json`, que
  // e caso clinico FICTICIO escrito pelo revisor — nao sintoma de pessoa. Se
  // aparecer outra, alguem esta prestes a persistir dado sensivel de saude.
  const suspeitas = fixture.db
    .prepare(
      `SELECT m.name AS tabela, p.name AS coluna
         FROM sqlite_master m, pragma_table_info(m.name) p
        WHERE m.type = 'table'
          AND (p.name LIKE '%token%' OR p.name LIKE '%symptom%' OR p.name LIKE '%sintoma%')`,
    )
    .all() as { tabela: string; coluna: string }[];

  // Lista EXAUSTIVA das colunas com "token" ou "symptom" no nome, cada uma
  // revisada. E deliberado que uma coluna nova assim reprove ate ser
  // acrescentada aqui: o custo e uma linha, e o que esta do outro lado e dado
  // sensivel de saude.
  const permitidas = new Set([
    // Vocabulario de icones — identificador de conteudo publico, nao sintoma
    // de pessoa.
    'symptom_token.id',
    'token_translation.token_id',
    'routing_rule_term.token_id',
    // Caso clinico ficticio escrito pelo revisor, versionado junto das regras.
    'golden_case.tokens_json',
    // "token" aqui e token de DESIGN (verde/vermelho/azul), nao de sintoma.
    'card.color_token',
    'venue.color_token',
  ]);

  for (const { tabela, coluna } of suspeitas) {
    assert.ok(
      permitidas.has(`${tabela}.${coluna}`),
      `${tabela}.${coluna} parece guardar sintoma. A sequencia do usuario morre em ` +
        'memoria (INV-2 / LGPD-RF13) e nunca chega a este banco.',
    );
  }
});
