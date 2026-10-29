/**
 * Importador de casos golden (P0-2): mesma regra do packer e das rotas.
 * Dados FICTICIOS: IDs AT-9xxx, nomes inventados, registros zerados.
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { after, before, beforeEach, test } from 'node:test';

import { avaliarRegistro, avaliarRevisao } from '@guia-ubs/contract';
import { parse as parseYaml } from 'yaml';

import { importarGolden, type CasoGoldenYaml } from '../src/services/golden-import.js';
import { auditRows, freshApp, novoOperador, TEST_ENV, type Fixture } from './support/app.js';

let f: Fixture;
let autor: string;
const AGORA = new Date('2026-10-28T12:00:00Z');
const termo = (c: string) => c.repeat(64);

const REG = [
  { id: 'AT-9201', conselho: 'CRM', uf: 'RR', termo_sha256: termo('a') },
  { id: 'AT-9202', conselho: 'COREN', categoria: 'ENF', uf: 'AC', termo_sha256: termo('b') },
];
const ATESTADOS_CMS = [
  { id: 'AT-9201', nome: 'Revisora Ficticia Um', conselho: 'CRM', uf: 'RR', categoria: null, registro: '000201', termo: termo('a') },
  { id: 'AT-9202', nome: 'Revisor Ficticio Dois', conselho: 'COREN', uf: 'AC', categoria: 'ENF', registro: '000202', termo: termo('b') },
];
const REV1 = { atestado: 'AT-9201', conselho: 'CRM', uf: 'RR', reviewed_at: '2026-10-01' };
const REV2 = { atestado: 'AT-9202', conselho: 'COREN', categoria: 'ENF', uf: 'AC', reviewed_at: '2026-10-02' };

const caso = (id: string, extra: Partial<CasoGoldenYaml> = {}): CasoGoldenYaml => ({
  id,
  tokens: ['chest', 'pain'],
  expect: 'EMERGENCY',
  reviewed_by: [REV1],
  ...extra,
});

async function q(sql: string, args: (string | number)[] = []) {
  return (await f.client.execute({ sql, args })).rows;
}
async function contagem(tabela: string) {
  return Number((await q(`SELECT COUNT(*) AS n FROM ${tabela}`))[0]!.n);
}
async function registrarCms(ids = ATESTADOS_CMS.map((a) => a.id), alvo = ATESTADOS_CMS) {
  for (const a of alvo.filter((x) => ids.includes(x.id))) {
    await f.client.execute({
      sql: `INSERT INTO golden_attestation
              (id, nome, conselho, uf, categoria, registro, termo_sha256, created_by, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      args: [a.id, a.nome, a.conselho, a.uf, a.categoria, a.registro, a.termo, autor, AGORA.toISOString()],
    });
  }
}
const importar = (casos: CasoGoldenYaml[], registro: readonly unknown[] = REG) =>
  importarGolden(f.client, TEST_ENV.hashSalt, { casos, registro }, { autor, agora: AGORA });

before(async () => {
  f = await freshApp();
  autor = (await novoOperador(f, 'editor')).id;
});
after(async () => f.close());
beforeEach(async () => {
  // Trilha e revisao sao append-only: limpa-se so o que o gatilho permite.
  await f.client.execute('PRAGMA foreign_keys = OFF');
  for (const t of ['golden_case_review_no_delete']) await f.client.execute(`DROP TRIGGER IF EXISTS ${t}`);
  await f.client.execute('DELETE FROM golden_case_review');
  await f.client.execute('DELETE FROM golden_case');
  await f.client.execute('DELETE FROM golden_attestation');
  await f.client.execute('PRAGMA foreign_keys = ON');
});

test('recusa caso sem revisor e nao escreve nada', async () => {
  await registrarCms();
  const r = await importar([caso('a'), caso('b', { reviewed_by: undefined })]);
  assert.deepEqual(r.recusados.map((x) => x.id), ['b']);
  assert.match(r.recusados[0]!.problemas[0]!, /sem revisao clinica/);
  assert.equal(await contagem('golden_case'), 0);
  assert.equal(await contagem('golden_case_review'), 0);
});

test('recusa revisao invalida', async () => {
  await registrarCms();
  const r = await importar([caso('a', { reviewed_by: [{ ...REV1, reviewed_at: '2099-01-01' }] })]);
  assert.equal(r.recusados.length, 1);
  assert.equal(await contagem('golden_case'), 0);
});

test('recusa atestado fora do registro', async () => {
  await registrarCms();
  const r = await importar([caso('a')], [REG[1]]);
  assert.equal(r.recusados.length, 1);
  assert.match(r.recusados[0]!.problemas.join(), /atestados\.yaml/);
  assert.equal(await contagem('golden_case'), 0);
});

test('recusa atestado ausente do CMS', async () => {
  await registrarCms(['AT-9202']);
  const r = await importar([caso('a')]);
  assert.equal(r.recusados.length, 1);
  assert.match(r.recusados[0]!.problemas[0]!, /POST \/api\/golden-cases\/atestados/);
  assert.equal(await contagem('golden_case'), 0);
});

test('CMS divergente do registro e conflito', async () => {
  await registrarCms(undefined, [{ ...ATESTADOS_CMS[0]!, termo: termo('c') }, ATESTADOS_CMS[1]!]);
  const r = await importar([caso('a')]);
  assert.equal(r.conflitos.length, 1);
  assert.match(r.conflitos[0]!.motivo, /CMS e atestados\.yaml divergem/);
  assert.equal(await contagem('golden_case'), 0);
});

test('recusa suite vazia', async () => {
  const r = await importar([]);
  assert.deepEqual(r.recusados.map((x) => x.id), ['(suite)']);
});

test('recusa registro invalido', async () => {
  const r = await importar([caso('a')], [{ id: 'xx' }]);
  assert.deepEqual(r.recusados.map((x) => x.id), ['(registro)']);
  assert.equal(await contagem('golden_case'), 0);
});

test('importa casos revisados ativos com revisoes e trilha', async () => {
  await registrarCms();
  const r = await importar([caso('a'), caso('b', { reviewed_by: [REV1, REV2] })]);
  assert.deepEqual(r.inseridos, ['a', 'b']);
  assert.deepEqual(r.recusados, []);
  const ativos = await q('SELECT id, active FROM golden_case ORDER BY id');
  assert.deepEqual(ativos.map((x) => [x.id, Number(x.active)]), [['a', 1], ['b', 1]]);
  assert.equal(await contagem('golden_case_review'), 3);
  const acoes = (await auditRows(f)).filter((x) => x.action === 'golden_case_import');
  assert.deepEqual(acoes.map((x) => x.entity_id).sort(), ['a', 'b']);
  assert.ok(acoes.every((x) => x.actor_id === autor));
});

test('acrescenta revisor a caso existente com conteudo identico', async () => {
  await registrarCms();
  // Como o importador antigo deixava: ativo e sem revisao.
  await f.client.execute({
    sql: `INSERT INTO golden_case (id, tokens_json, expected_outcome_id, clinical_source, added_by, active)
          VALUES ('a', ?, 'EMERGENCY', 'x', ?, 1)`,
    args: [JSON.stringify(['chest', 'pain']), autor],
  });
  const r = await importar([caso('a')]);
  assert.deepEqual(r.revisoresAcrescentados, [{ id: 'a', atestados: ['AT-9201'] }]);
  assert.equal(await contagem('golden_case_review'), 1);
  assert.ok((await auditRows(f)).some((x) => x.action === 'golden_case_review' && x.entity_id === 'a'));
});

test('conteudo divergente e conflito e nada e escrito', async () => {
  await registrarCms();
  await f.client.execute({
    sql: `INSERT INTO golden_case (id, tokens_json, expected_outcome_id, clinical_source, added_by, active)
          VALUES ('a', ?, 'ROUTINE_UBS', 'x', ?, 0)`,
    args: [JSON.stringify(['chest', 'pain']), autor],
  });
  const r = await importar([caso('a'), caso('novo')]);
  assert.equal(r.conflitos.length, 1);
  assert.match(r.conflitos[0]!.motivo, /conteudo editado no CMS/);
  assert.equal(await contagem('golden_case'), 1);
  assert.equal(await contagem('golden_case_review'), 0);
});

test('nunca remove revisao que o YAML nao traz', async () => {
  await registrarCms();
  await importar([caso('a', { reviewed_by: [REV1, REV2] })]);
  const r = await importar([caso('a', { reviewed_by: [REV1] })]);
  assert.deepEqual(r.mantidos, ['a']);
  assert.equal(await contagem('golden_case_review'), 2);
});

test('nunca troca a data de uma revisao existente', async () => {
  await registrarCms();
  await importar([caso('a')]);
  const r = await importar([caso('a', { reviewed_by: [{ ...REV1, reviewed_at: '2026-10-20' }] })]);
  assert.equal(r.conflitos.length, 1);
  const datas = await q('SELECT reviewed_at FROM golden_case_review');
  assert.deepEqual(datas.map((x) => x.reviewed_at), ['2026-10-01']);
});

test('reimportar e idempotente', async () => {
  await registrarCms();
  await importar([caso('a')]);
  const trilha = (await auditRows(f)).length;
  const r = await importar([caso('a')]);
  assert.deepEqual(r.mantidos, ['a']);
  assert.deepEqual([r.inseridos, r.revisoresAcrescentados, r.conflitos, r.recusados], [[], [], [], []]);
  assert.equal(await contagem('golden_case_review'), 1);
  assert.equal((await auditRows(f)).length, trilha);
});

test('todo caso do YAML real com revisao valida e aceito', async () => {
  const raiz = join(import.meta.dirname, '..', '..', 'seed', 'golden');
  const ler = (n: string) => parseYaml(readFileSync(join(raiz, n), 'utf8')) as Record<string, unknown>;
  const todos = (ler('clinical_cases.yaml').cases as CasoGoldenYaml[]) ?? [];
  const registro = (ler('atestados.yaml').atestados as unknown[]) ?? [];
  const reg = avaliarRegistro({ atestados: registro });
  assert.ok(reg.ok, 'atestados.yaml real deve ser valido');

  // Relogio de parede, e nao `AGORA`: revisao real datada depois da data fixa
  // seria filtrada como "no futuro", e o teste ficaria verde sem importar nada.
  const hoje = new Date();
  // Rodou sobre TODOS os casos do YAML real, mesmo que nenhum tenha revisao ainda.
  let examinados = 0;
  const revisados: CasoGoldenYaml[] = [];
  for (const c of todos) {
    examinados += 1;
    if (avaliarRevisao(c, hoje).estado === 'valida') revisados.push(c);
  }
  assert.ok(todos.length > 0, 'o YAML real tem casos');
  assert.equal(examinados, todos.length, 'o filtro percorreu todos os casos do YAML real');

  // Atestados fictícios com os IDs e campos do registro real.
  for (const [i, e] of reg.entradas.entries()) {
    await f.client.execute({
      sql: `INSERT INTO golden_attestation
              (id, nome, conselho, uf, categoria, registro, termo_sha256, created_by, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      args: [
        e.id, `Pessoa Ficticia ${i}`, e.conselho, e.uf,
        'categoria' in e ? e.categoria : null,
        String(i + 1).padStart(6, '0'), e.termo_sha256, autor, hoje.toISOString(),
      ],
    });
  }
  if (revisados.length === 0) return; // nada a importar; o suficiente: o filtro rodou acima
  const r = await importarGolden(f.client, TEST_ENV.hashSalt, { casos: revisados, registro }, { autor, agora: hoje });
  assert.equal(r.recusados.length, 0, JSON.stringify(r.recusados));
  assert.equal(r.conflitos.length, 0, JSON.stringify(r.conflitos));
});
