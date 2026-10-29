/**
 * O caminho CMS -> pack: extracao, portoes, guarda de chave e o job.
 *
 * Este arquivo atravessa os dois workspaces de proposito. O que ele protege e a
 * saida declarada da Fase 3 — "pack publicado ponta a ponta pelo CMS, com
 * aprovacao clinica registrada" — e as duas coisas que nao podem falhar em
 * silencio no meio do caminho: rascunho de regra vazando para o pack, e
 * assinatura com chave que a frota nao conhece.
 *
 * Banco em ARQUIVO, nao `:memory:`: cada conexao libSQL em memoria abre um banco
 * proprio e vazio. Foi assim que o item 18 descobriu.
 */
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';

import { migrationStatements } from '@guia-ubs/cms/src/db/client.js';
import { createClient, type Client } from '@libsql/client';

import { ACOES_QUE_REABREM, ACOES_QUE_NAO_REABREM } from '@guia-ubs/contract';

import { readRuleModel } from '../src/build-pack.js';
import { extrairConteudo, lerAtestadosDoBanco, lerGoldenDoBanco } from '../src/extract.js';
import { chavePublicaDe, conferirChaveRegistrada } from '../src/release.js';
import { lerGoldenDoYaml, validateGolden } from '../src/validate.js';
import { processar, proximaAprovada } from '../src/worker.js';
import { ATESTADO_FICTICIO, REG } from './support/revisao.js';

const AGORA = '2026-08-24T12:00:00Z';
const REPO_ROOT = join(import.meta.dirname, '..', '..');
/** Instante no formato que o banco carimba — o mesmo de `blocked_at`. */
const ISO_DO_BANCO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
/** O worker le o registro publico do repositorio; aqui, o ficticio. */
const OPCOES = { publicar: false, registro: REG } as const;

let diretorio: string;
let client: Client;
let keyPath: string;
let publicKeyBase64: string;

/** Conteudo clinico FICTICIO, o minimo para um pack valido. */
async function semear(c: Client): Promise<void> {
  const exec = (sql: string) => c.execute(sql);
  const A = `1, 'admin-1', '${AGORA}'`;

  await exec(`INSERT INTO admin_user (id, email, name, role, created_at, updated_at)
    VALUES ('admin-1', 'op@exemplo.invalid', 'Operadora', 'editor', 0, 0)`);
  await exec(`INSERT INTO municipality (id, code, name, version, updated_by, updated_at)
    VALUES ('mun-1', '0000000', 'Exemplo', ${A})`);
  await exec(`INSERT INTO municipality (id, code, name, version, updated_by, updated_at)
    VALUES ('mun-2', '1111111', 'Outro', ${A})`);

  await exec(`INSERT INTO asset (ref, kind, path, sha256, bytes, version, updated_by, updated_at)
    VALUES ('icon.head', 'icon', 'assets/icon.head.svg', '${'a'.repeat(64)}', 1, ${A})`);

  for (const [id, kind] of [
    ['chest', 'body_part'],
    ['pain', 'symptom'],
  ]) {
    await exec(`INSERT INTO symptom_token (id, kind, icon_ref, sort_order, deprecated, version, updated_by, updated_at)
      VALUES ('${id}', '${kind}', 'icon.head', 0, 0, ${A})`);
    for (const lang of ['pt', 'es']) {
      await exec(`INSERT INTO token_translation (token_id, lang, label, version, updated_by, updated_at)
        VALUES ('${id}', '${lang}', '${id}-${lang}', ${A})`);
    }
  }
  for (const [id, cor] of [
    ['card.rot', 'green'],
    ['card.emg', 'red'],
  ]) {
    await exec(`INSERT INTO card (id, kind, icon_ref, color_token, sort_order, version, updated_by, updated_at)
      VALUES ('${id}', 'result', 'icon.head', '${cor}', 0, ${A})`);
    for (const lang of ['pt', 'es']) {
      await exec(`INSERT INTO card_translation (card_id, lang, title, version, updated_by, updated_at)
        VALUES ('${id}', '${lang}', '${id}-${lang}', ${A})`);
    }
  }
  await exec(`INSERT INTO venue (id, icon_ref, color_token, sort_order, version, updated_by, updated_at)
    VALUES ('UBS', 'icon.head', 'green', 0, ${A})`);
  for (const lang of ['pt', 'es']) {
    await exec(`INSERT INTO venue_translation (venue_id, lang, label, version, updated_by, updated_at)
      VALUES ('UBS', '${lang}', 'UBS-${lang}', ${A})`);
  }
  await exec(`INSERT INTO routing_outcome (id, severity_level, card_id, venue_id, version, updated_by, updated_at)
    VALUES ('ROUTINE_UBS', 10, 'card.rot', 'UBS', ${A})`);
  await exec(`INSERT INTO routing_outcome (id, severity_level, card_id, venue_id, version, updated_by, updated_at)
    VALUES ('EMERGENCY', 100, 'card.emg', 'UBS', ${A})`);

  // Uma regra APROVADA e uma em RASCUNHO. A segunda nao pode entrar no pack.
  await exec(`INSERT INTO routing_rule (id, priority, outcome_id, status, version, updated_by, updated_at)
    VALUES ('rf-aprovada', 10, 'EMERGENCY', 'approved', ${A})`);
  for (const token of ['chest', 'pain']) {
    await exec(`INSERT INTO routing_rule_term (rule_id, group_no, token_id, negated, version, updated_by, updated_at)
      VALUES ('rf-aprovada', 0, '${token}', 0, ${A})`);
  }
  await exec(`INSERT INTO routing_rule (id, priority, outcome_id, status, version, updated_by, updated_at)
    VALUES ('rascunho', 5, 'ROUTINE_UBS', 'draft', ${A})`);
  await exec(`INSERT INTO routing_rule_term (rule_id, group_no, token_id, negated, version, updated_by, updated_at)
    VALUES ('rascunho', 0, 'chest', 0, ${A})`);

  // Conteudo municipal de DOIS municipios: o pack de um nao pode levar o outro.
  for (const [mun, id] of [
    ['mun-1', 'svc-meu'],
    ['mun-2', 'svc-alheio'],
  ]) {
    await exec(`INSERT INTO service (municipality_id, id, venue_id, icon_ref, sort_order, version, updated_by, updated_at)
      VALUES ('${mun}', '${id}', 'UBS', 'icon.head', 0, ${A})`);
    for (const lang of ['pt', 'es']) {
      await exec(`INSERT INTO service_translation (municipality_id, service_id, lang, label, version, updated_by, updated_at)
        VALUES ('${mun}', '${id}', '${lang}', '${id}-${lang}', ${A})`);
    }
  }

  await exec(`INSERT INTO golden_case (id, tokens_json, expected_outcome_id, clinical_source, added_by, active)
    VALUES ('g-toracico', '["chest","pain"]', 'EMERGENCY', 'ficticio', 'admin-1', 1)`);
  // Atestado e revisao FICTICIOS: sem eles o portao barraria toda release.
  const at = ATESTADO_FICTICIO;
  await exec(`INSERT INTO golden_attestation
      (id, nome, conselho, uf, categoria, registro, termo_sha256, created_by, created_at)
    VALUES ('${at.id}', '${at.nome}', '${at.conselho}', '${at.uf}', 'ENF', '${at.registro}',
            '${at.termo_sha256}', 'admin-1', '${AGORA}')`);
  await exec(`INSERT INTO golden_case_review
      (id, case_id, attestation_id, reviewed_at, recorded_by, recorded_at)
    VALUES ('rv-0', 'g-toracico', '${at.id}', '2026-08-20', 'admin-1', '${AGORA}')`);
  await exec(`INSERT INTO signing_key (key_id, public_key, activated_at)
    VALUES ('k-teste', '${publicKeyBase64}', '${AGORA}')`);
  await exec(`INSERT INTO pack_release (id, municipality_id, pack_version, schema_version, status, created_by, created_at)
    VALUES ('rel-1', 'mun-1', 1, '1.0', 'approved', 'admin-1', '${AGORA}')`);
}

before(async () => {
  diretorio = mkdtempSync(join(tmpdir(), 'gubs-pipeline-'));

  // Par EFEMERO. A chave de producao jamais entra num runner de teste.
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  keyPath = join(diretorio, 'k.pem');
  writeFileSync(keyPath, privateKey.export({ type: 'pkcs8', format: 'pem' }) as string);
  publicKeyBase64 = publicKey.export({ type: 'spki', format: 'der' }).toString('base64');

  client = createClient({ url: `file:${join(diretorio, 'cms.db')}` });
  for (const s of migrationStatements()) await client.execute(s);
  await semear(client);
});

after(() => {
  client.close();
  rmSync(diretorio, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// Extracao
// ---------------------------------------------------------------------------

test('regra em RASCUNHO nao entra no pack', async () => {
  // A propriedade mais importante do extrator: rascunho no pack e conteudo nao
  // revisado chegando a um aparelho sem internet (INV-4, risco R5 do PRD).
  const sql = (await extrairConteudo({ client, municipalityId: 'mun-1' }))
    .map((p) => p.sql)
    .join('\n');
  assert.ok(sql.includes('rf-aprovada'), 'a regra aprovada precisa entrar');
  assert.ok(!sql.includes('rascunho'), 'uma regra em rascunho vazou para o pack');
});

test('conteudo de outro municipio nao vaza', async () => {
  const sql = (await extrairConteudo({ client, municipalityId: 'mun-1' }))
    .map((p) => p.sql)
    .join('\n');
  assert.ok(sql.includes('svc-meu'));
  assert.ok(!sql.includes('svc-alheio'), 'servico de outro municipio entrou no pack');
});

test('nenhuma coluna de autoria atravessa para o pack', async () => {
  // O pack nao tem onde guarda-las: o DDL recusaria, mas recusar no fim do build
  // e pior que nao gerar.
  const sql = (await extrairConteudo({ client, municipalityId: 'mun-1' }))
    .map((p) => p.sql)
    .join('\n');
  for (const coluna of ['updated_by', 'updated_at', 'binary', 'status', 'municipality_id']) {
    assert.ok(!sql.includes(coluna), `"${coluna}" atravessou para o pack`);
  }
});

// ---------------------------------------------------------------------------
// Suite golden: duas fontes, um criterio
// ---------------------------------------------------------------------------

test('os dois leitores produzem a mesma forma para validateGolden', async () => {
  const doBanco = await lerGoldenDoBanco(client);
  const doYaml = lerGoldenDoYaml(REPO_ROOT);
  assert.equal(doBanco.length, 1);
  assert.ok(doYaml.length >= 20, 'o YAML semente perdeu casos');
  for (const caso of [...doBanco, ...doYaml]) {
    assert.ok(Array.isArray(caso.tokens));
    assert.equal(typeof caso.expect, 'string');
  }
});

// ---------------------------------------------------------------------------
// Guarda de chave
// ---------------------------------------------------------------------------

test('chave registrada e aceita', () => {
  conferirChaveRegistrada('k-teste', keyPath, [
    { keyId: 'k-teste', publicKey: publicKeyBase64, retiredAt: null },
  ]);
});

test('chave que a frota nao conhece e recusada ANTES de assinar', () => {
  // Sem esta guarda, o pack sairia assinado e TODO aparelho o rejeitaria em
  // silencio: o sync tenta, a assinatura nao confere, nada no servidor acusa.
  assert.throws(() => conferirChaveRegistrada('k-fantasma', keyPath, []), /nao esta em signing_key/);
});

test('chave aposentada e recusada', () => {
  assert.throws(
    () =>
      conferirChaveRegistrada('k-teste', keyPath, [
        { keyId: 'k-teste', publicKey: publicKeyBase64, retiredAt: AGORA },
      ]),
    /aposentada/,
  );
});

test('privada que nao corresponde a publica registrada e recusada', () => {
  const outra = generateKeyPairSync('ed25519')
    .publicKey.export({ type: 'spki', format: 'der' })
    .toString('base64');
  assert.throws(
    () =>
      conferirChaveRegistrada('k-teste', keyPath, [
        { keyId: 'k-teste', publicKey: outra, retiredAt: null },
      ]),
    /nao corresponde a publica registrada/,
  );
  assert.notEqual(chavePublicaDe(keyPath), outra);
});

// ---------------------------------------------------------------------------
// O job
// ---------------------------------------------------------------------------

test('o job constroi, assina e registra a corrida golden', async () => {
  process.env.PACK_SIGNING_KEY_PATH = keyPath;
  process.env.PACK_SIGNING_KEY_ID = 'k-teste';
  process.env.SOURCE_DATE_EPOCH = '1787097600';

  const release = await proximaAprovada(client);
  assert.ok(release, 'a release aprovada deveria estar na fila');
  assert.equal(release.municipalityCode, '0000000');

  // `publicar: false` — o teste nao fala com MinIO. Tudo ate a assinatura roda.
  const resultado = await processar(client, release, OPCOES);
  assert.equal(resultado.estado, 'publicado', JSON.stringify(resultado.problemas));

  const linhas = await client.execute(
    "SELECT status, pack_sha256, signed_at FROM pack_release WHERE id = 'rel-1'",
  );
  assert.equal(linhas.rows[0]!.status, 'built');
  assert.match(String(linhas.rows[0]!.pack_sha256), /^[0-9a-f]{64}$/);
  assert.ok(linhas.rows[0]!.signed_at);

  const corrida = await client.execute(
    "SELECT passed, total FROM golden_run WHERE pack_release_id = 'rel-1'",
  );
  assert.equal(Number(corrida.rows[0]!.total), 1);
  assert.equal(Number(corrida.rows[0]!.passed), 1);
});

test('a trilha do job registra ator NULO', async () => {
  // O job nao tem operador. Inventar um `system` criaria uma linha em
  // `admin_user` que parece porta dos fundos numa auditoria.
  const linhas = await client.execute(
    "SELECT actor_id, action FROM audit_entry WHERE entity_id = 'rel-1'",
  );
  assert.ok(linhas.rows.length >= 2, 'building e built deveriam estar na trilha');
  for (const l of linhas.rows) assert.equal(l.actor_id, null);
  assert.ok(linhas.rows.some((l) => l.action === 'release_built'));
});

test('o pack construido tem so a regra aprovada', () => {
  const modelo = readRuleModel(join(REPO_ROOT, 'packer', 'out', 'content.db'));
  assert.deepEqual(
    modelo.rules.map((r) => r.id),
    ['rf-aprovada'],
  );
});

test('a fila fica vazia depois de processada', async () => {
  assert.equal(await proximaAprovada(client), null);
});

/** Escrita auditada com ator, carimbada pelo banco — como `recordAudit` grava. */
async function auditar(action: string, actor: string | null = 'admin-1'): Promise<void> {
  await client.execute({
    sql: `INSERT INTO audit_entry (id, actor_id, action, entity_type, entity_id, occurred_at)
          VALUES (lower(hex(randomblob(16))), ?, ?, 'teste', 'teste',
                  strftime('%Y-%m-%dT%H:%M:%fZ','now'))`,
    args: [actor, action],
  });
}

/** O relogio do banco tem milissegundos; duas escritas no mesmo ms empatariam. */
const proximoMs = () => new Promise((ok) => setTimeout(ok, 5));

test('o worker BLOQUEIA caso golden sem revisor e devolve a release', async () => {
  // O defeito do issue #2: ate aqui o worker assinava com caso sem revisor.
  await client.execute(
    `INSERT INTO golden_case (id, tokens_json, expected_outcome_id, clinical_source, added_by, active)
     VALUES ('g-sem-revisao', '["chest","pain"]', 'EMERGENCY', 'ficticio', 'admin-1', 1)`,
  );
  await client.execute(
    `INSERT INTO pack_release (id, municipality_id, pack_version, schema_version, status, created_by, created_at)
     VALUES ('rel-x', 'mun-1', 2, '1.0', 'approved', 'admin-1', '2026-08-25T00:00:00Z')`,
  );

  const release = await proximaAprovada(client);
  assert.equal(release?.id, 'rel-x');
  const resultado = await processar(client, release!, OPCOES);
  assert.equal(resultado.estado, 'bloqueado');
  assert.ok(resultado.problemas!.some((p) => p.includes('g-sem-revisao')));

  const linha = (
    await client.execute(
      "SELECT status, claimed_at, blocked_at, pack_sha256 FROM pack_release WHERE id = 'rel-x'",
    )
  ).rows[0]!;
  assert.equal(linha.status, 'approved', 'a release deveria voltar para a fila');
  assert.equal(linha.claimed_at, null);
  assert.match(String(linha.blocked_at), ISO_DO_BANCO);
  assert.equal(linha.pack_sha256, null, 'nada pode ter sido assinado');
});

test('blocked_at e o instante do claim, carimbado pelo banco', async () => {
  // A extracao le o conteudo logo depois do claim. Escrita que caia entre o
  // claim e o bloqueio nao entrou no build — se `blocked_at` fosse o instante do
  // bloqueio, ela ficaria antes dele e nunca reabriria a release.
  const trilha = await client.execute(
    `SELECT action, after_json, occurred_at FROM audit_entry
      WHERE entity_type = 'pack_release' AND entity_id = 'rel-x' ORDER BY occurred_at`,
  );
  const claim = trilha.rows.find((l) => l.action === 'release_building')!;
  const bloqueio = trilha.rows.find((l) => l.action === 'release_approved')!;
  const claimedAt = String(JSON.parse(String(claim.after_json)).claimed_at);
  assert.match(claimedAt, ISO_DO_BANCO);
  // Do relogio do banco, como o `occurred_at` da trilha que registra o claim.
  assert.ok(claimedAt <= String(claim.occurred_at), `${claimedAt} > ${claim.occurred_at}`);

  const linha = (
    await client.execute("SELECT blocked_at FROM pack_release WHERE id = 'rel-x'")
  ).rows[0]!;
  assert.equal(String(linha.blocked_at), claimedAt);
  assert.equal(JSON.parse(String(bloqueio.after_json)).blocked_at, claimedAt);
});

test('escrita de conteudo entre o claim e o bloqueio reabre a release', async () => {
  const claimedAt = String(
    JSON.parse(
      String(
        (
          await client.execute(
            `SELECT after_json FROM audit_entry
              WHERE entity_id = 'rel-x' AND action = 'release_building'`,
          )
        ).rows[0]!.after_json,
      ),
    ).claimed_at,
  );
  const bloqueouEm = String(
    (
      await client.execute(
        `SELECT occurred_at FROM audit_entry
          WHERE entity_id = 'rel-x' AND action = 'release_approved'`,
      )
    ).rows[0]!.occurred_at,
  );
  // Um milissegundo depois do claim: durante o build, antes do bloqueio.
  const durante = new Date(Date.parse(claimedAt) + 1).toISOString();
  assert.ok(durante < bloqueouEm, `${durante} deveria cair antes do bloqueio (${bloqueouEm})`);

  const id = 'aud-durante-build';
  await client.execute({
    sql: `INSERT INTO audit_entry (id, actor_id, action, entity_type, entity_id, occurred_at)
          VALUES (?, 'admin-1', 'content_update', 'teste', 'teste', ?)`,
    args: [id, durante],
  });
  try {
    assert.equal((await proximaAprovada(client))?.id, 'rel-x');
  } finally {
    // A trilha e append-only; recua o bloqueio para alem da escrita, para os
    // testes seguintes partirem de uma release bloqueada sem mudanca.
    await client.execute({
      sql: "UPDATE pack_release SET blocked_at = ? WHERE id = 'rel-x'",
      args: [new Date(Date.parse(bloqueouEm) + 1).toISOString()],
    });
  }
});

test('release bloqueada nao e repescada sem mudanca', async () => {
  // Sem isto, `rodarUmaVez` em laco reconstruiria a mesma release a cada varredura.
  assert.equal(await proximaAprovada(client), null);
  const corridas = await client.execute(
    "SELECT COUNT(*) AS n FROM golden_run WHERE pack_release_id = 'rel-x'",
  );
  assert.equal(Number(corridas.rows[0]!.n), 1);
});

test('login nao reabre release bloqueada', async () => {
  await proximoMs();
  await auditar('sign_in');
  await auditar('two_factor_verify');
  await auditar('release_submit');
  // Escrita de conteudo SEM ator (SQL de manutencao, job) tambem nao reabre.
  await auditar('content_update', null);
  assert.equal(await proximaAprovada(client), null);
});

test('release bloqueada nao trava a mais nova', async () => {
  await client.execute(
    `INSERT INTO pack_release (id, municipality_id, pack_version, schema_version, status, created_by, created_at)
     VALUES ('rel-y', 'mun-1', 3, '1.0', 'approved', 'admin-1', '2026-08-26T00:00:00Z')`,
  );
  assert.equal((await proximaAprovada(client))?.id, 'rel-y');
  // Fora da fila de novo, para os testes seguintes verem so `rel-x`.
  await client.execute("UPDATE pack_release SET status = 'revoked' WHERE id = 'rel-y'");
});

test('release bloqueada volta depois de escrita de conteudo', async () => {
  await proximoMs();
  await auditar('content_update');
  assert.equal((await proximaAprovada(client))?.id, 'rel-x');

  // As tres familias que reabrem, montadas do contrato — e nenhuma das outras.
  assert.deepEqual([...ACOES_QUE_REABREM], ['content_', 'rule_', 'golden_']);
  assert.ok(!ACOES_QUE_NAO_REABREM.some((a) => ACOES_QUE_REABREM.some((p) => a.startsWith(p))));

  // Desfaz: sem revisor, o caso nao pode ficar ativo para os testes seguintes.
  await client.execute("UPDATE golden_case SET active = 0 WHERE id = 'g-sem-revisao'");
  await client.execute("UPDATE pack_release SET status = 'revoked' WHERE id = 'rel-x'");
});

test('suite do banco vazia BLOQUEIA o worker', async () => {
  await client.execute("UPDATE golden_case SET active = 0 WHERE id = 'g-toracico'");
  await client.execute(
    `INSERT INTO pack_release (id, municipality_id, pack_version, schema_version, status, created_by, created_at)
     VALUES ('rel-vazia', 'mun-1', 4, '1.0', 'approved', 'admin-1', '2026-08-27T00:00:00Z')`,
  );
  try {
    const resultado = await processar(client, (await proximaAprovada(client))!, OPCOES);
    assert.equal(resultado.estado, 'bloqueado');
    assert.ok(resultado.problemas!.some((p) => /suite golden vazia/i.test(p)));
  } finally {
    await client.execute("UPDATE golden_case SET active = 1 WHERE id = 'g-toracico'");
    await client.execute("UPDATE pack_release SET status = 'revoked' WHERE id = 'rel-vazia'");
  }
});

test('atestado do banco fora do registro BLOQUEIA o worker', async () => {
  // O mesmo caso, revisado pelo mesmo atestado: so o registro publico mudou.
  // Atestado no CMS que o repositorio nao conhece e revisor sem termo publicado.
  await client.execute(
    `INSERT INTO pack_release (id, municipality_id, pack_version, schema_version, status, created_by, created_at)
     VALUES ('rel-fora', 'mun-1', 5, '1.0', 'approved', 'admin-1', '2026-08-28T00:00:00Z')`,
  );
  const outroHash = [{ ...REG[1]!, termo_sha256: 'c'.repeat(64) }];
  try {
    const resultado = await processar(client, (await proximaAprovada(client))!, {
      publicar: false,
      registro: outroHash,
    });
    assert.equal(resultado.estado, 'bloqueado');
    assert.ok(
      resultado.problemas!.some((p) => p.includes('AT-9002') && p.includes('termo_sha256')),
      JSON.stringify(resultado.problemas),
    );

    const semEle = await processar(client, (await reaberta('rel-fora'))!, {
      publicar: false,
      registro: [REG[0]!],
    });
    assert.equal(semEle.estado, 'bloqueado');
    assert.ok(
      semEle.problemas!.some((p) => p.includes('AT-9002') && p.includes('nao consta')),
      JSON.stringify(semEle.problemas),
    );
  } finally {
    await client.execute("UPDATE pack_release SET status = 'revoked' WHERE id = 'rel-fora'");
  }
});

/** Reabre por escrita de conteudo auditada e devolve a proxima da fila. */
async function reaberta(id: string) {
  await proximoMs();
  await auditar('content_update');
  const release = await proximaAprovada(client);
  assert.equal(release?.id, id);
  return release;
}

test('caso golden vermelho BLOQUEIA e devolve a release para a fila', async () => {
  // Nada e assinado com um portao vermelho — e a release volta para `approved` em
  // vez de um estado de erro, porque depois de corrigido o conteudo a MESMA
  // release deve poder ser construida de novo.
  //
  // `g-impossivel` e revisado: bloqueia pelo motivo que nomeia (veredito
  // divergente), nao por falta de revisor.
  await client.execute(
    `INSERT INTO golden_case (id, tokens_json, expected_outcome_id, clinical_source, added_by, active)
     VALUES ('g-impossivel', '["chest"]', 'EMERGENCY', 'ficticio', 'admin-1', 1)`,
  );
  await client.execute(`INSERT INTO golden_case_review
      (id, case_id, attestation_id, reviewed_at, recorded_by, recorded_at)
    VALUES ('rv-imp', 'g-impossivel', '${ATESTADO_FICTICIO.id}', '2026-08-21', 'admin-1', '${AGORA}')`);
  await client.execute(
    `INSERT INTO pack_release (id, municipality_id, pack_version, schema_version, status, created_by, created_at)
     VALUES ('rel-2', 'mun-1', 6, '1.0', 'approved', 'admin-1', '2026-08-29T00:00:00Z')`,
  );

  const release = await proximaAprovada(client);
  assert.equal(release?.id, 'rel-2');
  const resultado = await processar(client, release!, OPCOES);
  assert.equal(resultado.estado, 'bloqueado');
  assert.ok(resultado.problemas!.some((p) => p.includes('g-impossivel') && p.includes('esperado')));
  assert.ok(!resultado.problemas!.some((p) => /sem revisao/.test(p)));

  const linhas = await client.execute(
    "SELECT status, claimed_at FROM pack_release WHERE id = 'rel-2'",
  );
  assert.equal(linhas.rows[0]!.status, 'approved', 'a release deveria voltar para a fila');
  assert.equal(linhas.rows[0]!.claimed_at, null);

  const corrida = await client.execute(
    "SELECT passed, total FROM golden_run WHERE pack_release_id = 'rel-2'",
  );
  assert.equal(Number(corrida.rows[0]!.total), 2);
  assert.equal(Number(corrida.rows[0]!.passed), 1, 'a corrida vermelha precisa ficar registrada');

  // Escrita de conteudo auditada: a release volta a ser elegivel, como depois de
  // corrigido o conteudo.
  await reaberta('rel-2');
});

test('a suite golden do banco passa contra o pack construido', async () => {
  const modelo = readRuleModel(join(REPO_ROOT, 'packer', 'out', 'content.db'));
  const relatorio = validateGolden(
    (await lerGoldenDoBanco(client)).filter((c) => c.id === 'g-toracico'),
    modelo,
    { modo: 'assinatura', agora: new Date(AGORA), registro: REG },
  );
  assert.deepEqual(relatorio.issues, []);
  assert.equal(relatorio.passed, 1);
  assert.equal(relatorio.falseNegatives, 0);
});

// Por ultimo de proposito: revisao e append-only, e as linhas abaixo nao saem
// mais do banco compartilhado por este arquivo.
test('lerGoldenDoBanco monta reviewed_by a partir das revisoes', async () => {
  await client.execute(
    `INSERT INTO golden_case (id, tokens_json, expected_outcome_id, clinical_source, added_by, active)
     VALUES ('g-leitura', '["chest","pain"]', 'EMERGENCY', 'ficticio', 'admin-1', 1)`,
  );
  const antes = (await lerGoldenDoBanco(client)).find((c) => c.id === 'g-leitura');
  assert.equal(antes?.reviewed_by, null, 'caso sem revisao sai com reviewed_by nulo');

  // Segundo atestado FICTICIO (o primeiro, AT-9002, vem de `semear`); revisoes
  // inseridas fora de ordem e com datas diferentes.
  await client.execute(`INSERT INTO golden_attestation
      (id, nome, conselho, uf, categoria, registro, termo_sha256, created_by, created_at)
    VALUES ('AT-9001', 'Revisor Ficticio Teste', 'CRM', 'RR', NULL, '000001',
            '${'a'.repeat(64)}', 'admin-1', '${AGORA}')`);
  await client.execute(`INSERT INTO golden_case_review
      (id, case_id, attestation_id, reviewed_at, recorded_by, recorded_at)
    VALUES ('rv-l2', 'g-leitura', 'AT-9002', '2026-08-22', 'admin-1', '${AGORA}'),
           ('rv-l1', 'g-leitura', 'AT-9001', '2026-08-20', 'admin-1', '${AGORA}')`);

  const caso = (await lerGoldenDoBanco(client)).find((c) => c.id === 'g-leitura');
  assert.deepEqual(caso?.reviewed_by, [
    { atestado: 'AT-9001', conselho: 'CRM', uf: 'RR', reviewed_at: '2026-08-20' },
    { atestado: 'AT-9002', conselho: 'COREN', uf: 'RR', categoria: 'ENF', reviewed_at: '2026-08-22' },
  ]);

  // Nome e registro ficam no CMS: o leitor de atestados os devolve, o de casos nao.
  const atestados = await lerAtestadosDoBanco(client);
  assert.deepEqual(
    atestados.map((a) => a.id),
    ['AT-9001', 'AT-9002'],
  );
  assert.deepEqual(atestados[1], ATESTADO_FICTICIO);
  assert.ok(!('categoria' in atestados[0]!), 'CRM nao tem categoria');
  assert.ok(!JSON.stringify(caso).includes('Ficticia'), 'nome do revisor vazou para o caso');
});
