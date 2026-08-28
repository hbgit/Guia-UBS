/**
 * O contrato de servir a interface pelo mesmo processo que atende a API.
 *
 * Quase tudo aqui existe por causa de um modo de falha concreto:
 *
 * - `/api/<typo>` virando HTML faz TODO `fetch` da SPA falhar com "Unexpected
 *   token '<'" em vez de um 404 legivel. E o defeito que mais desperdicaria
 *   tempo neste desenho, e nao aparece em nenhuma tela — aparece no console.
 * - Um arquivo `health` dentro de `dist/` sombreando o healthcheck faria o
 *   compose declarar o servico saudavel lendo um artefato do Vite.
 * - `index.html` cacheado faz tela branca a cada implantacao: o navegador guarda
 *   a casca de ontem e pede um asset com hash que o build novo apagou.
 * - Sem `dist`, um 404 mandaria procurar erro de digitacao no caminho; o que
 *   houve foi ninguem ter rodado `npm run web:build`.
 */
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';

import { SEM_BUILD } from '../src/web.js';
import { freshApp, pedido, sessaoDe, type Fixture } from './support/app.js';

const CASCA = '<!doctype html><title>casca</title><div id="raiz"></div>';
const ASSET = 'console.log("bundle");';

/** Nome com hash, como o Vite emite — e o que justifica o `immutable`. */
const NOME_DO_ASSET = 'app-a1b2c3d4.js';

let raiz: string;
let comInterface: Fixture;
let semInterface: Fixture;

before(async () => {
  raiz = mkdtempSync(join(tmpdir(), 'gubs-web-'));
  mkdirSync(join(raiz, 'assets'));
  writeFileSync(join(raiz, 'index.html'), CASCA, 'utf8');
  writeFileSync(join(raiz, 'assets', NOME_DO_ASSET), ASSET, 'utf8');
  /**
   * Um arquivo chamado `health`, de proposito. E a unica forma de afirmar que a
   * ordem de montagem protege o healthcheck: sem o `/health` registrado antes,
   * este arquivo responderia no lugar dele.
   */
  writeFileSync(join(raiz, 'health'), 'nao sou o healthcheck', 'utf8');

  comInterface = await freshApp(raiz);
  semInterface = await freshApp(join(raiz, 'nao-existe'));
});

after(async () => {
  await comInterface.close();
  await semInterface.close();
  rmSync(raiz, { recursive: true, force: true });
});

test('a raiz devolve a casca', async () => {
  const r = await comInterface.app.request('/');
  assert.equal(r.status, 200);
  assert.match(r.headers.get('content-type') ?? '', /text\/html/);
  assert.match(await r.text(), /id="raiz"/);
});

test('rota da SPA cai no recuo de historico, e nao em 404', async () => {
  // `/releases/rel-2026-01` nao e arquivo nenhum; quem resolve e o react-router,
  // no navegador. O servidor devolve a casca e deixa o roteamento acontecer la.
  const r = await comInterface.app.request('/releases/rel-2026-01');
  assert.equal(r.status, 200);
  assert.match(await r.text(), /id="raiz"/);
});

test('a casca NUNCA e cacheada; o asset com hash e imutavel', async () => {
  const casca = await comInterface.app.request('/');
  assert.equal(casca.headers.get('cache-control'), 'no-store');

  const asset = await comInterface.app.request(`/assets/${NOME_DO_ASSET}`);
  assert.equal(asset.status, 200);
  assert.match(asset.headers.get('cache-control') ?? '', /immutable/);
  assert.equal(await asset.text(), ASSET);
});

test('asset com hash inexistente e 404, nao a casca', async () => {
  // Devolver HTML sob uma URL de asset o guardaria por um ano, com `immutable`,
  // no cache de quem pediu.
  const r = await comInterface.app.request('/assets/app-00000000.js');
  assert.equal(r.status, 404);
});

test('/health responde o healthcheck mesmo havendo um arquivo `health` no dist', async () => {
  const r = await comInterface.app.request('/health');
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { status: 'ok' });
});

test('rota inexistente sob /api e 404 para quem TEM sessao, e nunca HTML', async () => {
  /**
   * A guarda que sustenta o desenho inteiro. Sem ela, um erro de digitacao numa
   * chamada da SPA vira "Unexpected token '<'" no console do navegador.
   *
   * Precisa de sessao: `protegido` roda `requireSession` como middleware `*`, que
   * responde 401 ANTES de qualquer casamento de rota. Sem sessao, portanto, o 404
   * nem chega a ser alcancavel — e o cenario que interessa e o da SPA autenticada
   * errando o caminho, que e quando alguem passa a tarde procurando o defeito.
   */
  const sessao = await sessaoDe(comInterface, 'editor');
  const r = await pedido(comInterface, sessao.cookie, 'GET', '/api/rota-que-nao-existe');
  assert.equal(r.status, 404);
  assert.doesNotMatch(r.headers.get('content-type') ?? '', /text\/html/);
});

test('rota protegida sem sessao continua 401, nao HTML', async () => {
  const r = await comInterface.app.request('/api/me');
  assert.equal(r.status, 401);
  assert.deepEqual(await r.json(), { error: 'nao autenticado' });
});

test('/api/telemetry continua alcancavel — a guarda casa por caminho, nao por protecao', async () => {
  // A telemetria e publica e montada ANTES do grupo protegido. Uma guarda escrita
  // como "e rota protegida?" a quebraria, e o sintoma seria a unica rota sem
  // sessao do sistema passando a devolver a casca.
  const r = await comInterface.app.request('/api/telemetry', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: '{}',
  });
  assert.notEqual(r.status, 404);
  assert.doesNotMatch(r.headers.get('content-type') ?? '', /text\/html/);
});

test('POST para caminho qualquer e 404, nao pagina', async () => {
  const r = await comInterface.app.request('/releases', { method: 'POST' });
  assert.equal(r.status, 404);
});

test('travessia de caminho nao serve arquivo de fora da raiz', async () => {
  for (const alvo of ['/../../etc/passwd', '/%2e%2e/%2e%2e/etc/passwd']) {
    const r = await comInterface.app.request(alvo);
    // Pode virar recuo de historico (200 com a casca) ou 404 — o que nao pode e
    // sair conteudo de fora da raiz.
    assert.doesNotMatch(await r.text(), /root:/);
  }
});

test('sem build, a interface responde 503 e a API nao muda', async () => {
  const tela = await semInterface.app.request('/');
  // 503 e nao 404: a API esta no ar e a interface nao. Um 404 aqui mandaria
  // procurar erro de digitacao no caminho.
  assert.equal(tela.status, 503);
  assert.deepEqual(await tela.json(), { error: SEM_BUILD });

  const saude = await semInterface.app.request('/health');
  assert.equal(saude.status, 200);

  const api = await semInterface.app.request('/api/me');
  assert.equal(api.status, 401);
});
