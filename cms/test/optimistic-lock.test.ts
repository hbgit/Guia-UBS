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

// ---------------------------------------------------------------------------
// Traducao (#16): o mesmo contrato, mais `If-None-Match: *` para criar — sem
// ele a primeira traducao de um idioma nao teria versao nenhuma para mandar.
// ---------------------------------------------------------------------------

const TRAD = '/api/content/symptom-tokens/fever/traducoes/pt';

async function traducaoDe(token: string) {
  const r = await f.client.execute({
    sql: 'SELECT label, version FROM token_translation WHERE token_id = ? AND lang = ?',
    args: [token, 'pt'],
  });
  const linha = r.rows[0];
  return linha && { label: linha.label, version: Number(linha.version) };
}

test('traducao: PUT sem pre-condicao recebe 428', async () => {
  const r = await pedido(f, editor, 'PUT', TRAD, { label: 'Febre' });
  assert.equal(r.status, 428);
  assert.equal(await traducaoDe('fever'), undefined);
});

test('traducao: If-Match malformado e 428, como no PATCH', async () => {
  for (const v of ['abc', '0', '-1']) {
    const r = await pedido(f, editor, 'PUT', TRAD, { label: 'X' }, v);
    assert.equal(r.status, 428, `If-Match ${v}`);
  }
});

test('traducao: If-Match e If-None-Match juntos recebem 400', async () => {
  const r = await pedido(f, editor, 'PUT', TRAD, { label: 'X' }, 1, '*');
  assert.equal(r.status, 400);
  assert.equal(await traducaoDe('fever'), undefined);
});

test('traducao: If-Match em traducao inexistente e 404, nao cria', async () => {
  const r = await pedido(f, editor, 'PUT', TRAD, { label: 'Febre' }, 1);
  assert.equal(r.status, 404);
  assert.equal(await traducaoDe('fever'), undefined);
});

test('traducao: If-None-Match * cria com ETag "1"', async () => {
  const r = await pedido(f, editor, 'PUT', TRAD, { label: 'Febre' }, undefined, '*');
  assert.equal(r.status, 201, await r.text());
  assert.equal(r.headers.get('etag'), '"1"');
});

test('traducao: segunda criacao recebe 409 com versaoAtual e nao sobrescreve', async () => {
  const r = await pedido(f, editor, 'PUT', TRAD, { label: 'Calor' }, undefined, '*');
  assert.equal(r.status, 409);
  assert.equal(((await r.json()) as { versaoAtual?: number }).versaoAtual, 1);
  assert.deepEqual(await traducaoDe('fever'), { label: 'Febre', version: 1 });
});

test('traducao: GET devolve a linha com ETag', async () => {
  const r = await pedido(f, editor, 'GET', TRAD);
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('etag'), '"1"');
  assert.equal(((await r.json()) as { label?: string }).label, 'Febre');
});

test('traducao: duas escritas a partir da mesma leitura — a segunda recebe 409', async () => {
  const a = await pedido(f, editor, 'PUT', TRAD, { label: 'Febre alta' }, 1);
  assert.equal(a.status, 200, await a.text());
  assert.equal(a.headers.get('etag'), '"2"');

  const b = await pedido(f, editor, 'PUT', TRAD, { label: 'Quentura' }, 1);
  assert.equal(b.status, 409);
  assert.equal(((await b.json()) as { versaoAtual?: number }).versaoAtual, 2);
  assert.deepEqual(await traducaoDe('fever'), { label: 'Febre alta', version: 2 });
});

test('traducao: so as escritas aceitas entram na trilha', async () => {
  const t = (await auditRows(f)).filter(
    (l) => l.action === 'content_translate' && l.entity_id === 'pt/fever',
  );
  assert.equal(t.length, 2, 'criacao + uma atualizacao; recusas nao entram');
  const atualizacoes = t.filter((l) => l.before_json);
  assert.equal(atualizacoes.length, 1);
  assert.equal((JSON.parse(atualizacoes[0]!.before_json!) as { label: string }).label, 'Febre');
});

test('traducao: pai inexistente com If-None-Match * e erro de integridade, nao 500', async () => {
  const r = await pedido(
    f, editor, 'PUT', '/api/content/symptom-tokens/nao-existe/traducoes/pt',
    { label: 'X' }, undefined, '*',
  );
  assert.ok(r.status === 409 || r.status === 422, `status ${r.status}`);
  assert.equal(((await r.json()) as { versaoAtual?: number }).versaoAtual, undefined);
});

test('traducao: chave composta (services) cria e detecta conflito', async () => {
  await pedido(f, editor, 'POST', '/api/content/venues', {
    id: 'UBS', iconRef: 'icon.exemplo', colorToken: 'green', sortOrder: 0,
  });
  const servico = await pedido(f, editor, 'POST', '/api/content/services', {
    municipalityId: 'mun-1', id: 'srv-1', venueId: 'UBS', iconRef: 'icon.exemplo', sortOrder: 0,
  });
  assert.equal(servico.status, 201, await servico.text());

  const caminho = '/api/content/services/mun-1/srv-1/traducoes/pt';
  const criada = await pedido(f, editor, 'PUT', caminho, { label: 'Consulta' }, undefined, '*');
  assert.equal(criada.status, 201, await criada.text());
  const editada = await pedido(f, editor, 'PUT', caminho, { label: 'Consulta geral' }, 1);
  assert.equal(editada.status, 200, await editada.text());
  assert.equal(editada.headers.get('etag'), '"2"');
  const perdedora = await pedido(f, editor, 'PUT', caminho, { label: 'Outra' }, 1);
  assert.equal(perdedora.status, 409);
  assert.equal(((await perdedora.json()) as { versaoAtual?: number }).versaoAtual, 2);

  const r = await f.client.execute(
    "SELECT label, version FROM service_translation WHERE municipality_id = 'mun-1' AND service_id = 'srv-1' AND lang = 'pt'",
  );
  assert.equal(r.rows[0]!.label, 'Consulta geral');
  assert.equal(Number(r.rows[0]!.version), 2);
  const trilha = (await auditRows(f)).filter(
    (l) => l.action === 'content_translate' && l.entity_id === 'pt/mun-1/srv-1',
  );
  assert.equal(trilha.length, 2);
});
