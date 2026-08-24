/**
 * O fluxo de ponta a ponta contra o app REAL (`createApp`), em processo.
 *
 * Sem porta aberta e sem app de teste montado a parte: um grafo de rotas
 * paralelo seria um grafo em que a rota esquecida no meio fica protegida no
 * teste e aberta em producao.
 */
import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { createAuth, SESSION_MAX_AGE_SECONDS } from '../src/auth/config.js';
import {
  ativar2fa,
  freshApp,
  login,
  loginCom2fa,
  novoOperador,
  SENHA_VALIDA,
  TEST_ENV,
  type Fixture,
} from './support/app.js';

let f: Fixture;
before(async () => {
  f = await freshApp();
});
after(async () => f.close());

test('a sessao expira em no maximo 24 h (LGPD-RT07)', () => {
  assert.ok(SESSION_MAX_AGE_SECONDS <= 60 * 60 * 24);
});

test('/health responde sem autenticacao — e a unica excecao', async () => {
  const r = await f.app.request('/health');
  assert.equal(r.status, 200);
  const corpo = (await r.json()) as Record<string, unknown>;
  // Nao toca no banco de identidade: nao ha o que vazar.
  assert.deepEqual(Object.keys(corpo), ['status']);
});

test('/api/me sem sessao e recusada', async () => {
  const r = await f.app.request('/api/me');
  assert.equal(r.status, 401);
});

test('nao existe rota publica de autocadastro', async () => {
  // `disableSignUp: true`. Um endpoint publico de cadastro num sistema que
  // publica orientacao clinica e uma porta para a rede inteira.
  const r = await f.app.request('/api/auth/sign-up/email', {
    method: 'POST',
    headers: { 'content-type': 'application/json', origin: 'http://localhost' },
    body: JSON.stringify({
      email: 'invasor@exemplo.invalid',
      name: 'Invasor',
      password: SENHA_VALIDA,
    }),
  });
  assert.ok(r.status >= 400, `autocadastro respondeu ${r.status}`);
});

test('requisicao AUTENTICADA sem Origin e recusada (CSRF)', async () => {
  // Descoberto ao escrever os testes. O `sign-in` nao exige `Origin` — nao ha
  // sessao para sequestrar ainda —, mas rota autenticada que muda estado exige.
  // Vale afirmar como garantia em vez de so mandar o cabecalho e seguir: se uma
  // atualizacao afrouxar isso, um site de terceiros passa a disparar acoes na
  // sessao de um operador logado.
  const operador = await novoOperador(f, 'editor', 'sem-origin@exemplo.invalid');
  const { cookie } = await login(f, operador.email);

  const r = await f.app.request('/api/auth/two-factor/enable', {
    method: 'POST',
    headers: { cookie: cookie!, 'content-type': 'application/json' },
    body: JSON.stringify({ password: SENHA_VALIDA }),
  });
  assert.equal(r.status, 403);
});

test('o rate limit por endpoint vem LIGADO por padrao', () => {
  // Os testes o desligam para nao saturarem; esta afirmacao impede que a
  // excecao dos testes vire o comportamento de producao sem ninguem decidir.
  const padrao = createAuth({ client: f.client, env: TEST_ENV });
  assert.equal(padrao.options.rateLimit?.enabled, true);
  assert.equal(padrao.options.rateLimit?.customRules?.['/sign-in/email']?.max, 5);
});

test('senha errada nao autentica', async () => {
  const operador = await novoOperador(f, 'editor', 'senha-errada@exemplo.invalid');
  const r = await login(f, operador.email, 'senha-errada-mesmo-123456');
  assert.ok(r.status >= 400, `login com senha errada respondeu ${r.status}`);
});

test('login correto SEM 2FA nao alcanca rota protegida', async () => {
  // A LGPD-RF11 diz 2FA obrigatoria; o Better Auth trata como opt-in. A
  // obrigacao e este 403.
  const operador = await novoOperador(f, 'editor', 'sem-2fa@exemplo.invalid');
  const { cookie } = await login(f, operador.email);
  assert.ok(cookie, 'login correto deveria ter devolvido cookie de sessao');

  const r = await f.app.request('/api/me', { headers: { cookie } });
  assert.equal(r.status, 403);
  const corpo = (await r.json()) as { next?: string };
  assert.match(corpo.next ?? '', /two-factor\/enable/, 'a recusa precisa dizer como sair dela');
});

test('com 2FA ativa, /api/me devolve papel e permissoes resolvidas', async () => {
  const operador = await novoOperador(f, 'clinical_reviewer', 'com-2fa@exemplo.invalid');
  const segredo = await ativar2fa(f, operador.email);
  const cookie = await loginCom2fa(f, operador.email, segredo);

  const r = await f.app.request('/api/me', { headers: { cookie } });
  assert.equal(r.status, 200);
  const corpo = (await r.json()) as { role: string; permissions: string[] };
  assert.equal(corpo.role, 'clinical_reviewer');
  assert.ok(corpo.permissions.includes('approval:decide'));
  assert.ok(!corpo.permissions.includes('content:write'), 'revisor nao escreve o que aprova');
});

test('a resposta de /api/me nao carrega credencial nenhuma', async () => {
  const operador = await novoOperador(f, 'editor', 'sem-credencial@exemplo.invalid');
  const segredo = await ativar2fa(f, operador.email);
  const cookie = await loginCom2fa(f, operador.email, segredo);
  const r = await f.app.request('/api/me', { headers: { cookie } });
  const texto = await r.text();
  for (const proibido of ['password', 'senha', 'secret', 'backup']) {
    assert.ok(!texto.toLowerCase().includes(proibido), `"${proibido}" apareceu em /api/me`);
  }
});

test('editor nao alcanca a gestao de operadores', async () => {
  const operador = await novoOperador(f, 'editor', 'editor-barrado@exemplo.invalid');
  const segredo = await ativar2fa(f, operador.email);
  const cookie = await loginCom2fa(f, operador.email, segredo);
  const r = await f.app.request('/api/users', { headers: { cookie } });
  assert.equal(r.status, 403);
});

test('admin lista operadores, e a lista nao traz credencial', async () => {
  const operador = await novoOperador(f, 'admin', 'admin-lista@exemplo.invalid');
  const segredo = await ativar2fa(f, operador.email);
  const cookie = await loginCom2fa(f, operador.email, segredo);

  const r = await f.app.request('/api/users', { headers: { cookie } });
  assert.equal(r.status, 200);
  const texto = await r.text();
  assert.ok(texto.includes('admin-lista@exemplo.invalid'));
  // Gerir pessoas nao e motivo para ver a credencial delas.
  assert.ok(!texto.includes('$argon2id$'), 'a lista vazou hash de senha');
  assert.ok(!texto.includes('"password"'), 'a lista vazou o campo de senha');
});

test('um operador nao altera a propria conta', async () => {
  // Sem isto, RBAC de tres papeis seria decorativo: bastaria pedir `admin`
  // para si.
  const operador = await novoOperador(f, 'admin', 'auto-promocao@exemplo.invalid');
  const segredo = await ativar2fa(f, operador.email);
  const cookie = await loginCom2fa(f, operador.email, segredo);

  const r = await f.app.request(`/api/users/${operador.id}`, {
    method: 'PATCH',
    headers: { cookie, 'content-type': 'application/json', origin: 'http://localhost' },
    body: JSON.stringify({ role: 'admin' }),
  });
  assert.equal(r.status, 403);
});

test('operador desligado nao usa sessao que ja tinha', async () => {
  // O carimbo `disabled_at` so vale se algo o consultar: sem esta guarda,
  // desligar alguem so faria efeito quando o cookie dela expirasse — ate 24 h
  // depois.
  const admin = await novoOperador(f, 'admin', 'admin-desliga@exemplo.invalid');
  const segredoAdmin = await ativar2fa(f, admin.email);
  const alvo = await novoOperador(f, 'editor', 'sera-desligado@exemplo.invalid');
  const segredoAlvo = await ativar2fa(f, alvo.email);

  const sessaoAlvo = await loginCom2fa(f, alvo.email, segredoAlvo);
  assert.equal((await f.app.request('/api/me', { headers: { cookie: sessaoAlvo } })).status, 200);

  const sessaoAdmin = await loginCom2fa(f, admin.email, segredoAdmin);
  const desligou = await f.app.request(`/api/users/${alvo.id}`, {
    method: 'PATCH',
    headers: { cookie: sessaoAdmin, 'content-type': 'application/json', origin: 'http://localhost' },
    body: JSON.stringify({ disabled: true }),
  });
  assert.equal(desligou.status, 200);

  const depois = await f.app.request('/api/me', { headers: { cookie: sessaoAlvo } });
  assert.equal(depois.status, 403, 'a sessao anterior ao desligamento continuou valendo');
});
