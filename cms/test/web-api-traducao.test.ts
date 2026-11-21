/**
 * A traducao pela SPA (#16): `substituir` contra o servidor real.
 *
 * Fica fora de `web-conformance.test.ts`, que e puramente estatico. Aqui o
 * `fetch` global e trocado por um que entrega ao `app.request` do Hono — o mesmo
 * caminho de `pedido`, com `cookie` e `origin` acrescentados.
 */
import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { ErroApi, ler, substituir } from '../web/src/api/api.js';
import { formularioTravado, paraEnvio, paraFormulario } from '../web/src/conteudo/traducao.js';
import { TEST_ENV, freshApp, pedido, seedConteudo, sessaoDe, type Fixture } from './support/app.js';

let f: Fixture;
const fetchOriginal = globalThis.fetch;

before(async () => {
  f = await freshApp();
  const editor = (await sessaoDe(f, 'editor')).cookie;
  await seedConteudo(f, editor);
  const r = await pedido(f, editor, 'POST', '/api/content/symptom-tokens', {
    id: 'tosse', kind: 'symptom', iconRef: 'icon.exemplo', sortOrder: 0, deprecated: 0,
  });
  assert.equal(r.status, 201, await r.text());
  globalThis.fetch = (async (entrada: string, init: RequestInit = {}) =>
    f.app.request(entrada, {
      ...init,
      headers: {
        ...(init.headers as Record<string, string>),
        cookie: editor,
        origin: TEST_ENV.authBaseUrl,
      },
    })) as typeof fetch;
});
after(async () => {
  globalThis.fetch = fetchOriginal;
  await f.close();
});

const CAMPOS = ['label', 'audioRef'] as const;

test('paraFormulario pega so os campos e deixa o nulo ausente', () => {
  assert.deepEqual(
    paraFormulario({ label: 'Febre', audioRef: null, version: 3, tokenId: 'x' }, CAMPOS),
    { label: 'Febre' },
  );
});

test('paraEnvio manda vazio e ausente como null', () => {
  // `audioRef` e FK para `asset`: `''` seria recusado pela FK.
  assert.deepEqual(paraEnvio({ label: 'Febre', audioRef: '' }, CAMPOS), {
    label: 'Febre',
    audioRef: null,
  });
  assert.deepEqual(paraEnvio({ label: 'Febre' }, CAMPOS), { label: 'Febre', audioRef: null });
});

const conflito = (versao: number) => (e: unknown) =>
  e instanceof ErroApi && e.falha.tipo === 'conflito_versao' && e.falha.versaoAtual === versao;

test('SPA: traducao gravada a partir da mesma leitura recebe conflito_versao', async () => {
  const caminho = '/api/content/symptom-tokens/tosse/traducoes/pt';
  assert.equal(await substituir(null, caminho, { label: 'A', audioRef: null }), 1);
  await assert.rejects(substituir(null, caminho, { label: 'B' }), conflito(1));

  const lido = await ler<Record<string, unknown>>(caminho);
  assert.equal(lido.versao, 1);
  // O ciclo real da tela: linha lida -> formulario -> envio, com audioRef nulo.
  const corpo = paraEnvio(paraFormulario(lido.dados, CAMPOS), CAMPOS);
  assert.equal(await substituir(lido, caminho, corpo), 2, 'regravar traducao sem audio precisa passar');
  await assert.rejects(substituir(lido, caminho, { label: 'D' }), conflito(2));
});

test('formularioTravado: trava lendo e salvando; nao trava em traducao inexistente', () => {
  assert.equal(formularioTravado(undefined, false), true, 'lendo');
  assert.equal(formularioTravado({ dados: {}, versao: 1 }, true), true, 'salvando');
  assert.equal(formularioTravado({ dados: {}, versao: 1 }, false), false, 'lida');
  assert.equal(formularioTravado(null, false), false, 'inexistente: a gravacao cria');
});
