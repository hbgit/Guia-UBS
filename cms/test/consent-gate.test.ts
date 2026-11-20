/**
 * Aceite do termo de uso bloqueia toda rota protegida ate a versao vigente
 * (issue #10). A unica excecao e `/api/consentimento`; `/api/me` NAO e excecao.
 */
import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { hashDoTexto, publicarDocumento, type DocumentoVigente } from '../src/services/legal.js';
import {
  ativar2fa,
  freshApp,
  login,
  loginCom2fa,
  novoOperador,
  pedido,
  TERMO_DE_TESTE,
  TEST_ENV,
  type Fixture,
} from './support/app.js';

let f: Fixture;
let sessao: { cookie: string; id: string };

before(async () => {
  f = await freshApp();
  const op = await novoOperador(f, 'editor', 'consent@exemplo.invalid');
  const segredo = await ativar2fa(f, op.email);
  sessao = { cookie: await loginCom2fa(f, op.email, segredo), id: op.id };
});
after(async () => f.close());

const ler = async (cookie = sessao.cookie) => pedido(f, cookie, 'GET', '/api/consentimento');
const aceitar = async (corpo: unknown, cookie = sessao.cookie) =>
  pedido(f, cookie, 'POST', '/api/consentimento', corpo);

async function contar(sql: string, args: string[] = []): Promise<number> {
  return Number((await f.client.execute({ sql, args })).rows[0]![0]);
}

async function bloqueado(caminho: string, fixture = f, cookie = sessao.cookie) {
  const r = await pedido(fixture, cookie, 'GET', caminho);
  assert.equal(r.status, 403, `${caminho} deveria estar bloqueada`);
  assert.equal(((await r.json()) as { next: string }).next, '/api/consentimento');
}

test('fluxo: bloqueio, aceite, concorrencia, nova versao, 409 e 400', async () => {
  await bloqueado('/api/me');
  await bloqueado('/api/releases');

  const lido = await ler();
  assert.equal(lido.status, 200);
  const termo = (await lido.json()) as DocumentoVigente & { aceito: boolean };
  assert.equal(termo.hash, hashDoTexto(TERMO_DE_TESTE));
  assert.equal(termo.aceito, false);

  // Concorrencia: dois POST identicos, uma linha e uma entrada na trilha.
  const visto = { version: termo.version, hash: termo.hash };
  const [a, b] = await Promise.all([aceitar(visto), aceitar(visto)]);
  assert.equal(a.status, 200);
  assert.equal(b.status, 200);
  assert.deepEqual(await a.json(), { aceito: true, ...visto });
  const porOperador = 'SELECT COUNT(*) FROM consent_record WHERE subject_ref = ?';
  assert.equal(await contar(porOperador, [sessao.id]), 1);
  assert.equal(
    await contar("SELECT COUNT(*) FROM audit_entry WHERE action = 'consent_accept' AND actor_id = ?", [sessao.id]),
    1,
  );
  const linha = await f.client.execute({
    sql: 'SELECT doc_hash FROM consent_record WHERE subject_ref = ?',
    args: [sessao.id],
  });
  assert.equal(linha.rows[0]!.doc_hash, termo.hash);

  assert.equal((await pedido(f, sessao.cookie, 'GET', '/api/me')).status, 200);
  assert.equal((await pedido(f, sessao.cookie, 'GET', '/api/releases')).status, 200);
  assert.equal(((await (await ler()).json()) as { aceito: boolean }).aceito, true);

  await assert.rejects(f.client.execute("UPDATE consent_record SET method = 'x'"));
  await assert.rejects(f.client.execute("UPDATE legal_document SET content_md = 'x'"));

  // Nova versao: o bloqueio volta.
  await publicarDocumento(f.client, TEST_ENV.hashSalt, { version: 'teste-2', contentMd: TERMO_DE_TESTE + ' v2' }, null);
  await bloqueado('/api/me');

  // Aceite da versao anterior: 409 com a vigente, nada gravado.
  const velho = await aceitar(visto);
  assert.equal(velho.status, 409);
  assert.equal(((await velho.json()) as { vigente: DocumentoVigente }).vigente.version, 'teste-2');
  assert.equal(await contar(porOperador, [sessao.id]), 1);

  assert.equal((await aceitar({ version: 'x', hash: 'nao-hex' })).status, 400);

  const v2 = (await (await ler()).json()) as DocumentoVigente;
  assert.equal((await aceitar({ version: v2.version, hash: v2.hash })).status, 200);
  assert.equal((await pedido(f, sessao.cookie, 'GET', '/api/me')).status, 200);
});

test('sem termo publicado o bloqueio fica fechado', async () => {
  const g = await freshApp(undefined, { termo: false });
  try {
    const op = await novoOperador(g, 'editor', 'semtermo@exemplo.invalid');
    const cookie = await loginCom2fa(g, op.email, await ativar2fa(g, op.email));
    await bloqueado('/api/me', g, cookie);
    assert.equal((await pedido(g, cookie, 'GET', '/api/consentimento')).status, 404);
    const post = await pedido(g, cookie, 'POST', '/api/consentimento', {
      version: 'teste-1',
      hash: hashDoTexto(TERMO_DE_TESTE),
    });
    assert.equal(post.status, 404);
  } finally {
    await g.close();
  }
});

test('o bloqueio de 2FA responde antes do de aceite', async () => {
  const op = await novoOperador(f, 'editor', 'sem2fa@exemplo.invalid');
  const { cookie } = await login(f, op.email);
  assert.ok(cookie);
  const r = await pedido(f, cookie, 'GET', '/api/me');
  assert.equal(r.status, 403);
  assert.equal(((await r.json()) as { next: string }).next, '/api/auth/two-factor/enable');
});

test('sem sessao: 401', async () => {
  assert.equal((await f.app.request('/api/consentimento')).status, 401);
});
