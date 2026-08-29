/**
 * O envio do binario de asset.
 *
 * Quase toda asserção aqui existe por um modo de falha concreto, e vale dizer
 * qual antes de cada uma. As tres que mais importam:
 *
 * - **o binario nunca sai em JSON nem entra na trilha.** `audit_entry` e
 *   append-only por gatilho: um blob gravado ali seria permanente;
 * - **o teto e conferido no `Content-Length`, antes de ler o corpo.** Uma
 *   checagem no handler mede depois de ja ter bufferizado tudo, e o teto passa a
 *   proteger o parse em vez da memoria;
 * - **os magic bytes precisam concordar com o `Content-Type` declarado.** O tipo
 *   declarado vira o do objeto no S3, que vira o que a borda diz ao aparelho.
 */
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { after, before, test } from 'node:test';

import { freshApp, pedido, seedConteudo, sessaoDe, type Fixture } from './support/app.js';

const SVG =
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect width="24" height="24"/></svg>';
const SHA_DO_SVG = createHash('sha256').update(Buffer.from(SVG)).digest('hex');

let f: Fixture;
let cookie: string;

before(async () => {
  f = await freshApp();
  const sessao = await sessaoDe(f, 'editor');
  cookie = sessao.cookie;
  await seedConteudo(f, cookie);
});
after(async () => f.close());

/** Envio cru: o `Content-Type` carrega o tipo, a URL carrega a chave. */
async function enviar(
  corpo: string | Buffer,
  { tipo = 'image/svg+xml', ifMatch = '"1"', ref = 'icon.exemplo', comprimento = '' } = {},
): Promise<Response> {
  const bytes = Buffer.isBuffer(corpo) ? corpo : Buffer.from(corpo);
  const cabecalhos: Record<string, string> = {
    cookie,
    origin: 'http://localhost',
    'content-type': tipo,
  };
  if (ifMatch) cabecalhos['if-match'] = ifMatch;
  if (comprimento) cabecalhos['content-length'] = comprimento;

  return f.app.request(`/api/content/assets/${ref}/binario`, {
    method: 'PUT',
    headers: cabecalhos,
    body: new Uint8Array(bytes),
  });
}

test('o envio grava blob, hash e tamanho na MESMA versao', async () => {
  // Em dois `UPDATE` o gatilho `asset_version_monotonic` abortaria — a guarda
  // funcionando, mas e melhor nao escrever. Uma versao so prova que foi um.
  const r = await enviar(SVG);
  const corpo = (await r.json()) as { versao: number; sha256: string; bytes: number };
  assert.equal(r.status, 200, JSON.stringify(corpo));
  assert.equal(corpo.versao, 2, 'a linha nasceu em 1; o envio leva a 2, nao a 3');
  // O hash sai dos BYTES, nao do caminho nem do que alguem digitou.
  assert.equal(corpo.sha256, SHA_DO_SVG);
  assert.equal(corpo.bytes, Buffer.from(SVG).byteLength);
  assert.equal(r.headers.get('etag'), '"2"');
});

test('o binario NUNCA aparece em JSON', async () => {
  /**
   * Sem a projecao derivada do schema, `GET /assets` devolveria 47 arrays de
   * bytes, e o `antes` do PATCH gravaria o blob na trilha append-only.
   */
  for (const caminho of ['/api/content/assets', '/api/content/assets/icon.exemplo']) {
    const texto = await (await pedido(f, cookie, 'GET', caminho)).text();
    assert.ok(!texto.includes('"binario"'), `${caminho} devolveu a coluna do blob`);
    assert.ok(!texto.includes('"type":"Buffer"'), `${caminho} serializou bytes`);
  }
});

test('a trilha guarda os DOIS hashes, e nenhum byte', async () => {
  const linhas = await f.client.execute(
    "SELECT before_json, after_json FROM audit_entry WHERE action = 'content_binario_upload'",
  );
  assert.equal(linhas.rows.length, 1);
  const depois = String(linhas.rows[0]!.after_json);
  assert.ok(depois.includes(SHA_DO_SVG), 'a trilha nao registrou o hash novo');
  // "Quem trocou quais bytes por quais" cabe em duzentos bytes; o blob nao sairia
  // mais de la nunca.
  assert.ok(depois.length < 500, `a trilha guardou ${depois.length} bytes`);
  assert.ok(!depois.includes('Buffer'), 'bytes vazaram para a trilha');
});

test('o `path` e DERIVADO do ref e do tipo, nao do que se digitou', async () => {
  // `path` alimenta a chave no S3, a url do manifest e um `join()` de sistema de
  // arquivos. Deixa-lo editavel foi o que tornou `../..` uma possibilidade.
  const linha = (await (
    await pedido(f, cookie, 'GET', '/api/content/assets/icon.exemplo')
  ).json()) as { path: string };
  assert.equal(linha.path, 'assets/icon.exemplo.svg');
});

test('sem If-Match, 428 — a mesma pre-condicao do PATCH', async () => {
  // Dispensar a pre-condicao numa rota so e o que ensina que o cabecalho e
  // decorativo. O envio muda a linha e incrementa `version` como qualquer escrita.
  const r = await enviar(SVG, { ifMatch: '' });
  assert.equal(r.status, 428);
});

test('If-Match velho responde 409 com a versao atual', async () => {
  const r = await enviar(SVG, { ifMatch: '"1"' });
  const corpo = (await r.json()) as { versaoAtual: number };
  assert.equal(r.status, 409);
  assert.equal(corpo.versaoAtual, 2, 'o 409 precisa dizer contra o que se perdeu');
});

test('Content-Type que nao bate com os magic bytes e recusado', async () => {
  // O tipo declarado vira o `Content-Type` do objeto no S3, que vira o que a
  // borda diz ao aparelho. Os magic bytes sao o que torna aquilo verdade.
  const r = await enviar(Buffer.from('nao sou um png'), { tipo: 'image/png', ifMatch: '"2"' });
  assert.equal(r.status, 422);
  assert.match(String(((await r.json()) as { error: string }).error), /image\/png/);
});

test('tipo fora da lista do kind e recusado', async () => {
  const r = await enviar(Buffer.from('OggS'), { tipo: 'audio/opus', ifMatch: '"2"' });
  assert.equal(r.status, 422);
});

test('SVG perigoso e recusado, e a resposta NOMEIA a regra', async () => {
  /**
   * Recusar, e nao sanitizar: um sanitizador e um parser que se passa a manter, e
   * o modo de falha dele e aceitar em silencio o que nao entendeu.
   *
   * A referencia externa e a que protege a promessa do produto — um
   * `<image href="https://…">` num icone assinado e uma chamada de rede num
   * aparelho cuja premissa e nao fazer nenhuma.
   */
  const casos: [string, string][] = [
    ['<svg xmlns="x"><script>alert(1)</script></svg>', 'script'],
    ['<!DOCTYPE svg [<!ENTITY a "b">]><svg xmlns="x"/>', 'dtd'],
    ['<svg xmlns="x" onload="alert(1)"/>', 'evento'],
    ['<svg xmlns="x"><image href="https://exemplo.invalid/x.png"/></svg>', 'referencia-externa'],
    ['<svg xmlns="x"><rect fill="url(https://exemplo.invalid/g)"/></svg>', 'referencia-externa'],
  ];
  for (const [conteudo, regra] of casos) {
    const r = await enviar(conteudo, { ifMatch: '"2"' });
    const corpo = (await r.json()) as { regra?: string; error: string };
    assert.equal(r.status, 422, `${regra}: ${JSON.stringify(corpo)}`);
    assert.equal(corpo.regra, regra, 'a recusa precisa dizer QUAL regra falhou');
  }
});

test('acima do teto do kind, 413', async () => {
  // Icone do pacote semente tem ~450 bytes; o teto de 64 KiB ja recusa um bitmap
  // contrabandeado dentro de um SVG.
  const gigante = `<svg xmlns="x">${'<rect/>'.repeat(12000)}</svg>`;
  const r = await enviar(gigante, { ifMatch: '"2"' });
  assert.equal(r.status, 413);
});

test('Content-Length grande com corpo curto e recusado ANTES de ler', async () => {
  /**
   * O discriminador limpo entre os dois desenhos.
   *
   * `bodyLimit` confere o cabecalho e recusa sem ler um byte. Uma checagem no
   * handler leria o corpo curto, mediria 10 bytes e deixaria passar — protegendo
   * o parse, e nao a memoria, que e o que importa numa rota de megabytes.
   */
  const r = await enviar(SVG, { ifMatch: '"2"', comprimento: String(50 * 1024 * 1024) });
  assert.equal(r.status, 413);
});

test('a leitura devolve os bytes, e com as duas defesas de SVG', async () => {
  const r = await pedido(f, cookie, 'GET', '/api/content/assets/icon.exemplo/binario');
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('content-type'), 'image/svg+xml');
  // Endereçado por conteudo: refetch da previa vira 304.
  assert.equal(r.headers.get('etag'), `"${SHA_DO_SVG}"`);
  // Uma navegacao BAIXA em vez de renderizar — o caminho pelo qual um SVG com
  // script viraria XSS no proprio CMS. `<img src>` e subrecurso e ignora isto.
  assert.equal(r.headers.get('content-disposition'), 'attachment');
  assert.match(r.headers.get('content-security-policy') ?? '', /default-src 'none'/);
  assert.equal(await r.text(), SVG);
});

test('item sem binario responde 404 na leitura, e nao um corpo vazio', async () => {
  await pedido(f, cookie, 'POST', '/api/content/assets', {
    ref: 'icon.sem.bytes',
    kind: 'icon',
    path: 'assets/icon.sem.bytes.svg',
  });
  const r = await pedido(f, cookie, 'GET', '/api/content/assets/icon.sem.bytes/binario');
  assert.equal(r.status, 404);
});
