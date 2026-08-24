/**
 * Duas pessoas editando a mesma linha.
 *
 * E o cenario que o `version` do item 16 e o gatilho de monotonicidade existem
 * para cobrir, e que so aparece de verdade quando duas escritas partem da MESMA
 * leitura. Sem o travamento, a segunda vence em silencio e a edicao da primeira
 * some sem erro, sem log e sem ninguem saber que existiu.
 */
import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { auditRows, freshApp, pedido, seedConteudo, sessaoDe, type Fixture } from './support/app.js';

let f: Fixture;
let editor: string;

before(async () => {
  f = await freshApp();
  editor = (await sessaoDe(f, 'editor')).cookie;
  await seedConteudo(f, editor);
  await pedido(f, editor, 'POST', '/api/content/symptom-tokens', {
    id: 'fever',
    kind: 'symptom',
    iconRef: 'icon.exemplo',
    sortOrder: 0,
    deprecated: 0,
  });
});
after(async () => f.close());

const ALVO = '/api/content/symptom-tokens/fever';

test('a segunda escrita a partir da mesma leitura recebe 409', async () => {
  const primeira = await pedido(f, editor, 'PATCH', ALVO, { sortOrder: 10 }, 1);
  assert.equal(primeira.status, 200);

  const segunda = await pedido(f, editor, 'PATCH', ALVO, { sortOrder: 20 }, 1);
  assert.equal(segunda.status, 409);
});

test('o 409 carrega a versao atual, para o editor oferecer o merge', async () => {
  const r = await pedido(f, editor, 'PATCH', ALVO, { sortOrder: 30 }, 1);
  const corpo = (await r.json()) as { versaoAtual?: number };
  // Um conflito que nao diz contra o que se perdeu obriga a pessoa a recarregar
  // a tela para descobrir.
  assert.equal(corpo.versaoAtual, 2);
});

test('a escrita recusada NAO teve efeito parcial', async () => {
  const linhas = await f.client.execute("SELECT sort_order FROM symptom_token WHERE id = 'fever'");
  assert.equal(Number(linhas.rows[0]!.sort_order), 10, 'o valor da escrita perdedora venceu');
});

test('com a versao corrente, a escrita passa', async () => {
  const r = await pedido(f, editor, 'PATCH', ALVO, { sortOrder: 40 }, 2);
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('etag'), '"3"');
});

test('conflito NAO entra na trilha como se tivesse mudado algo', async () => {
  // Trilha com escrita que nao aconteceu e trilha que mente. As recusadas foram
  // duas (versao 1 depois da 2 e depois da 3).
  const linhas = await auditRows(f);
  const atualizacoes = linhas.filter(
    (l) => l.action === 'content_update' && l.entity_id === 'fever',
  );
  assert.equal(atualizacoes.length, 2, 'entraram mais atualizacoes do que as que ocorreram');
});

test('a versao anda de exatamente 1 — o gatilho nao foi contornado', async () => {
  const linhas = await f.client.execute("SELECT version FROM symptom_token WHERE id = 'fever'");
  // Duas escritas bem-sucedidas a partir da versao 1.
  assert.equal(Number(linhas.rows[0]!.version), 3);
});

test('If-Match malformado e recusado como pre-condicao ausente', async () => {
  for (const valor of ['abc', '0', '-1', '"1.5"']) {
    const r = await f.app.request(ALVO, {
      method: 'PATCH',
      headers: {
        cookie: editor,
        origin: 'http://localhost',
        'content-type': 'application/json',
        'if-match': valor,
      },
      body: JSON.stringify({ sortOrder: 99 }),
    });
    assert.equal(r.status, 428, `If-Match "${valor}" deveria ser recusado`);
  }
});

test('linha inexistente responde 404, nao 409', async () => {
  // Distinguir "sumiu" de "mudou" importa: o editor oferece merge num caso e
  // avisa que o item foi removido no outro.
  const r = await pedido(f, editor, 'PATCH', '/api/content/symptom-tokens/nao-existe', {
    sortOrder: 1,
  }, 1);
  assert.equal(r.status, 404);
});

test('a versao do ETag de leitura serve para o PATCH seguinte', async () => {
  // E o contrato do fluxo: ler, editar, mandar de volta o que foi lido. Se o
  // ETag nao servisse, o cliente teria que adivinhar de onde tirar a versao.
  const lido = await pedido(f, editor, 'GET', ALVO);
  const etag = lido.headers.get('etag')!;
  const r = await f.app.request(ALVO, {
    method: 'PATCH',
    headers: {
      cookie: editor,
      origin: 'http://localhost',
      'content-type': 'application/json',
      'if-match': etag,
    },
    body: JSON.stringify({ sortOrder: 50 }),
  });
  assert.equal(r.status, 200, await r.text());
});
