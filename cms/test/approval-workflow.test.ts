/**
 * A FSM da release, percorrida como dado.
 *
 * O que este teste protege nao e "o botao funciona": e que **publicar sem
 * revisao clinica seja impossivel de escrever**. Uma transicao ilegal que passe
 * despercebida significa pack chegando a aparelho offline sem ninguem ter
 * aprovado o conteudo.
 */
import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { RELEASE_STATUSES } from '../src/db/schema/publishing.js';
import {
  TRANSICOES,
  reivindicar,
  transicaoPermitida,
  type ReleaseStatus,
} from '../src/services/approval-workflow.js';
import {
  auditRows,
  freshApp,
  pedido,
  seedConteudo,
  sessaoDe,
  type Fixture,
} from './support/app.js';

let f: Fixture;
let editor: string;
let revisor: { cookie: string; id: string };
let admin: string;

before(async () => {
  f = await freshApp();
  editor = (await sessaoDe(f, 'editor')).cookie;
  revisor = await sessaoDe(f, 'clinical_reviewer');
  admin = (await sessaoDe(f, 'admin')).cookie;
  await seedConteudo(f, editor);
});
after(async () => f.close());

// ---------------------------------------------------------------------------
// Propriedades estaticas da FSM
// ---------------------------------------------------------------------------

test('toda transicao aponta para estados que existem no schema', () => {
  const validos = new Set<string>(RELEASE_STATUSES);
  for (const t of TRANSICOES) {
    assert.ok(validos.has(t.de), `estado "${t.de}" nao existe`);
    assert.ok(validos.has(t.para), `estado "${t.para}" nao existe`);
  }
});

test('nao existe atalho que pule a revisao clinica', () => {
  // E a propriedade central do item. Escrita como assercao sobre o CONJUNTO, ela
  // continua valendo quando alguem acrescentar uma transicao nova.
  const proibidas: [ReleaseStatus, ReleaseStatus][] = [
    ['draft', 'approved'],
    ['draft', 'built'],
    ['draft', 'published'],
    ['pending_review', 'built'],
    ['pending_review', 'published'],
    ['approved', 'published'],
  ];
  for (const [de, para] of proibidas) {
    for (const ator of ['editor', 'clinical_reviewer', 'admin', 'job'] as const) {
      assert.equal(
        transicaoPermitida(de, para, ator),
        false,
        `${ator} pode ir de ${de} para ${para} — isso pula a revisao clinica`,
      );
    }
  }
});

test('so o job constroi e publica; so o admin revoga e reenfileira', () => {
  // Separacao de responsabilidades: um operador nao "constroi" um pack pela
  // interface, e o job nao decide revogar.
  assert.equal(transicaoPermitida('approved', 'building', 'job'), true);
  assert.equal(transicaoPermitida('approved', 'building', 'admin'), false);
  assert.equal(transicaoPermitida('built', 'published', 'job'), true);
  assert.equal(transicaoPermitida('built', 'published', 'admin'), false);
  assert.equal(transicaoPermitida('published', 'revoked', 'admin'), true);
  assert.equal(transicaoPermitida('published', 'revoked', 'job'), false);
  assert.equal(transicaoPermitida('building', 'approved', 'admin'), true);
  assert.equal(transicaoPermitida('building', 'approved', 'job'), false);
});

test('editor nao aprova, revisor nao submete', () => {
  assert.equal(transicaoPermitida('pending_review', 'approved', 'editor'), false);
  assert.equal(transicaoPermitida('draft', 'pending_review', 'clinical_reviewer'), false);
});

test('todo estado tem saida, exceto o terminal', () => {
  // Estado sem saida que nao seja terminal e release presa para sempre.
  const comSaida = new Set(TRANSICOES.map((t) => t.de));
  for (const estado of RELEASE_STATUSES) {
    if (estado === 'revoked') continue;
    assert.ok(comSaida.has(estado), `"${estado}" nao tem nenhuma saida`);
  }
});

// ---------------------------------------------------------------------------
// Comportamento pelo HTTP
// ---------------------------------------------------------------------------

async function novaRelease(id: string, versao: number, cookie = editor) {
  return pedido(f, cookie, 'POST', '/api/releases', {
    id,
    municipalityId: 'mun-1',
    packVersion: versao,
    schemaVersion: '1.0',
  });
}

test('release nasce em rascunho', async () => {
  const r = await novaRelease('rel-a', 1);
  assert.equal(r.status, 201, await r.text());
  const lida = await pedido(f, editor, 'GET', '/api/releases/rel-a');
  const corpo = (await lida.json()) as { release: { status: string } };
  assert.equal(corpo.release.status, 'draft');
});

test('a resposta traz as transicoes possiveis a partir do estado atual', async () => {
  // O cliente monta os botoes disto, em vez de manter uma segunda copia das
  // regras — que divergiria da primeira.
  const r = await pedido(f, editor, 'GET', '/api/releases/rel-a');
  const corpo = (await r.json()) as { transicoes: { para: string }[] };
  assert.deepEqual(
    corpo.transicoes.map((t) => t.para),
    ['pending_review'],
  );
});

test('versao repetida no mesmo municipio e recusada com 409', async () => {
  // `UNIQUE(municipality_id, pack_version)` e o anti-downgrade da INV-7: reemitir
  // um numero faria metade da frota parar de atualizar sem erro nenhum.
  const r = await novaRelease('rel-duplicada', 1);
  assert.equal(r.status, 409);
});

test('submeter move para revisao e registra na trilha', async () => {
  const r = await pedido(f, editor, 'POST', '/api/releases/rel-a/submeter');
  assert.equal(r.status, 200, await r.text());

  const linhas = await auditRows(f);
  assert.ok(linhas.some((l) => l.action === 'release_submit' && l.entity_id === 'rel-a'));
});

test('submeter de novo e recusado, e a resposta diz o que e possivel agora', async () => {
  const r = await pedido(f, editor, 'POST', '/api/releases/rel-a/submeter');
  assert.equal(r.status, 409);
  const corpo = (await r.json()) as { atual: string; permitidas: { para: string }[] };
  assert.equal(corpo.atual, 'pending_review');
  assert.deepEqual(corpo.permitidas.map((p) => p.para).sort(), ['approved', 'draft']);
});

test('rejeicao devolve a release para rascunho', async () => {
  const r = await pedido(f, revisor.cookie, 'POST', '/api/approvals', {
    releaseId: 'rel-a',
    decision: 'reject',
    comment: 'faltou revisar a regra de dor toracica',
  });
  assert.equal(r.status, 200, await r.text());

  const lida = await pedido(f, editor, 'GET', '/api/releases/rel-a');
  const corpo = (await lida.json()) as { release: { status: string } };
  assert.equal(corpo.release.status, 'draft');
});

test('a rejeicao fica registrada — retratar-se e inserir, nao apagar', async () => {
  const linhas = await f.client.execute(
    "SELECT decision FROM approval WHERE pack_release_id = 'rel-a'",
  );
  assert.equal(linhas.rows.length, 1);
  assert.equal(linhas.rows[0]!.decision, 'reject');
});

test('release em rascunho nao pode ser revogada nem reenfileirada', async () => {
  assert.equal((await pedido(f, admin, 'POST', '/api/releases/rel-a/revogar')).status, 409);
  assert.equal((await pedido(f, admin, 'POST', '/api/releases/rel-a/reenfileirar')).status, 409);
});

test('release inexistente responde 404', async () => {
  const r = await pedido(f, editor, 'POST', '/api/releases/nao-existe/submeter');
  assert.equal(r.status, 404);
});

test('editor nao revoga — e permissao de admin', async () => {
  assert.equal((await pedido(f, editor, 'POST', '/api/releases/rel-a/revogar')).status, 403);
});

// ---------------------------------------------------------------------------
// Posse: o compare-and-set
// ---------------------------------------------------------------------------

test('so um claim vence a corrida', async () => {
  // Sem isto, dois jobs construiriam o mesmo pack e publicariam um por cima do
  // outro. "Uma instancia hoje" nao e garantia.
  await novaRelease('rel-corrida', 2);
  await pedido(f, editor, 'POST', '/api/releases/rel-corrida/submeter');
  await pedido(f, revisor.cookie, 'POST', '/api/approvals', {
    releaseId: 'rel-corrida',
    decision: 'approve',
  });

  const resultados = await Promise.all([
    reivindicar(f.client, 'rel-corrida'),
    reivindicar(f.client, 'rel-corrida'),
    reivindicar(f.client, 'rel-corrida'),
  ]);
  assert.equal(resultados.filter(Boolean).length, 1, 'mais de um job tomou posse');
});

test('o claim carimba quando a posse foi tomada', async () => {
  // Sem o carimbo, "o job travou" e indistinguivel de "o job esta trabalhando".
  const linhas = await f.client.execute(
    "SELECT status, claimed_at FROM pack_release WHERE id = 'rel-corrida'",
  );
  assert.equal(linhas.rows[0]!.status, 'building');
  assert.ok(linhas.rows[0]!.claimed_at, 'claimed_at ficou nulo');
});

test('reenfileirar destrava e limpa o carimbo', async () => {
  const r = await pedido(f, admin, 'POST', '/api/releases/rel-corrida/reenfileirar');
  assert.equal(r.status, 200, await r.text());

  const linhas = await f.client.execute(
    "SELECT status, claimed_at FROM pack_release WHERE id = 'rel-corrida'",
  );
  assert.equal(linhas.rows[0]!.status, 'approved');
  assert.equal(linhas.rows[0]!.claimed_at, null);

  const trilha = await auditRows(f);
  assert.ok(
    trilha.some((l) => l.action === 'release_requeue'),
    'destravar sem registro e a saida que a auditoria nao ve',
  );
});
