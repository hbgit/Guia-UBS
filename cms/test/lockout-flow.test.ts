/**
 * A trava progressiva vista de fora, pelo HTTP (lgpd.md LGPD-RT07).
 *
 * `lockout.test.ts` prova a curva; este prova que ela esta LIGADA no caminho
 * real. Sao coisas diferentes: uma funcao de backoff perfeita que ninguem chama
 * e um backoff que nao existe.
 *
 * O rate limit por endpoint esta desligado nestes testes, entao tudo o que
 * segura aqui e a trava por conta — que e exatamente o que se quer medir.
 */
import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { FREE_ATTEMPTS } from '../src/auth/lockout.js';
import { subjectKey } from '../src/auth/pseudonymize.js';
import {
  auditRows,
  freshApp,
  login,
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

async function erra(email: string): Promise<number> {
  const r = await login(f, email, 'senha-errada-de-teste-000');
  return r.status;
}

test('as primeiras falhas nao travam — errar a senha acontece', async () => {
  const operador = await novoOperador(f, 'editor', 'folga@exemplo.invalid');
  for (let n = 0; n < FREE_ATTEMPTS; n += 1) {
    const status = await erra(operador.email);
    assert.notEqual(status, 429, `travou ja na tentativa ${n + 1}`);
  }
  // Dentro da folga, a senha certa ainda entra.
  const certa = await login(f, operador.email);
  assert.equal(certa.status, 200);
});

test('a conta trava depois da folga', async () => {
  const operador = await novoOperador(f, 'editor', 'trava@exemplo.invalid');
  for (let n = 0; n <= FREE_ATTEMPTS; n += 1) await erra(operador.email);

  const seguinte = await erra(operador.email);
  assert.equal(seguinte, 429, 'a conta deveria estar travada');
});

test('travada, ate a senha CERTA e recusada', async () => {
  // E o ponto da trava: se a senha certa passasse, um ataque que a descobrisse
  // na tentativa seguinte entraria assim mesmo.
  const operador = await novoOperador(f, 'editor', 'trava-senha-certa@exemplo.invalid');
  for (let n = 0; n <= FREE_ATTEMPTS + 1; n += 1) await erra(operador.email);

  const certa = await login(f, operador.email, SENHA_VALIDA);
  assert.equal(certa.status, 429);
  assert.equal(certa.cookie, null, 'conta travada nao pode emitir sessao');
});

test('a resposta nao diz quanto falta nem quantas restam', async () => {
  // Seria um oraculo sobre o estado de uma conta para quem nao a possui.
  const operador = await novoOperador(f, 'editor', 'sem-oraculo@exemplo.invalid');
  for (let n = 0; n <= FREE_ATTEMPTS + 1; n += 1) await erra(operador.email);

  const r = await f.app.request('/api/auth/sign-in/email', {
    method: 'POST',
    headers: { 'content-type': 'application/json', origin: TEST_ENV.authBaseUrl },
    body: JSON.stringify({ email: operador.email, password: SENHA_VALIDA }),
  });
  const corpo = await r.text();
  assert.ok(!/\d+\s*(s|seg|min)/i.test(corpo), `a resposta revelou tempo: ${corpo}`);
  assert.ok(!corpo.includes(operador.email));
});

test('a trava e por CONTA: outra conta nao e afetada', async () => {
  // O rate limit embutido e por endpoint e travaria todo mundo junto. Progressivo
  // so faz sentido contra o alvo.
  const vitima = await novoOperador(f, 'editor', 'alvo@exemplo.invalid');
  const vizinha = await novoOperador(f, 'editor', 'vizinha@exemplo.invalid');
  for (let n = 0; n <= FREE_ATTEMPTS + 1; n += 1) await erra(vitima.email);

  const outra = await login(f, vizinha.email);
  assert.equal(outra.status, 200, 'a conta vizinha foi arrastada pela trava');
});

test('login bem-sucedido zera o contador', async () => {
  const operador = await novoOperador(f, 'editor', 'zera@exemplo.invalid');
  for (let n = 0; n < FREE_ATTEMPTS; n += 1) await erra(operador.email);
  assert.equal((await login(f, operador.email)).status, 200);

  const chave = subjectKey(operador.email, TEST_ENV.hashSalt);
  const restou = await f.client.execute({
    sql: 'SELECT COUNT(*) AS n FROM login_attempt WHERE subject_key = ?',
    args: [chave],
  });
  // Zerar e nao apagar manteria historico de falhas de quem ja provou ser dona
  // da conta — dado pessoal sem finalidade vigente (LGPD-RF07).
  assert.equal(Number(restou.rows[0]!.n), 0);
});

test('a tentativa em conta travada entra na trilha', async () => {
  const linhas = await auditRows(f);
  assert.ok(
    linhas.some((l) => l.action === 'sign_in_locked'),
    'bloqueio sem registro e bloqueio que ninguem investiga',
  );
});

test('a trava nao guarda o e-mail em claro', async () => {
  const linhas = await f.client.execute('SELECT subject_key FROM login_attempt');
  for (const linha of linhas.rows) {
    const chave = String(linha.subject_key);
    assert.ok(!chave.includes('@'), 'a tabela virou uma lista de quem tem conta');
    assert.match(chave, /^[0-9a-f]{64}$/);
  }
});
