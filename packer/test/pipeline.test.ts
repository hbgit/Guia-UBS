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

import { readRuleModel } from '../src/build-pack.js';
import { extrairConteudo, lerGoldenDoBanco } from '../src/extract.js';
import { chavePublicaDe, conferirChaveRegistrada } from '../src/release.js';
import { lerGoldenDoYaml, validateGolden } from '../src/validate.js';
import { processar, proximaAprovada } from '../src/worker.js';

const AGORA = '2026-08-24T12:00:00Z';
const REPO_ROOT = join(import.meta.dirname, '..', '..');

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

  await exec(`INSERT INTO asset (ref, kind, path, sha256, bytes, storage_key, version, updated_by, updated_at)
    VALUES ('icon.head', 'icon', 'assets/icon.head.svg', '${'a'.repeat(64)}', 1, 'k', ${A})`);

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
  for (const coluna of ['updated_by', 'updated_at', 'storage_key', 'status', 'municipality_id']) {
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
  const resultado = await processar(client, release, { publicar: false });
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

test('caso golden vermelho BLOQUEIA e devolve a release para a fila', async () => {
  // Nada e assinado com um portao vermelho — e a release volta para `approved` em
  // vez de um estado de erro, porque depois de corrigido o conteudo a MESMA
  // release deve poder ser construida de novo.
  await client.execute(
    `INSERT INTO golden_case (id, tokens_json, expected_outcome_id, clinical_source, added_by, active)
     VALUES ('g-impossivel', '["chest"]', 'EMERGENCY', 'ficticio', 'admin-1', 1)`,
  );
  await client.execute(
    `INSERT INTO pack_release (id, municipality_id, pack_version, schema_version, status, created_by, created_at)
     VALUES ('rel-2', 'mun-1', 2, '1.0', 'approved', 'admin-1', '${AGORA}')`,
  );

  const release = await proximaAprovada(client);
  const resultado = await processar(client, release!, { publicar: false });
  assert.equal(resultado.estado, 'bloqueado');
  assert.ok(resultado.problemas!.some((p) => p.includes('g-impossivel')));

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
});

test('a suite golden do banco passa contra o pack construido', async () => {
  const modelo = readRuleModel(join(REPO_ROOT, 'packer', 'out', 'content.db'));
  const relatorio = validateGolden(
    (await lerGoldenDoBanco(client)).filter((c) => c.id === 'g-toracico'),
    modelo,
  );
  assert.equal(relatorio.passed, 1);
  assert.equal(relatorio.falseNegatives, 0);
});
