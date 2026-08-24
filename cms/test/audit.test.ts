/**
 * A trilha registra o que aconteceu — e NAO registra credencial (lgpd.md
 * LGPD-RT03).
 *
 * O teste mais importante daqui e o que varre a tabela INTEIRA procurando a
 * senha. Ele nao verifica um campo especifico de proposito: um vazamento de
 * credencial para a trilha quase nunca acontece no campo que alguem pensou em
 * conferir — acontece num `before_json` que alguem passou inteiro sem filtrar.
 */
import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { pseudonymize, subjectKey } from '../src/auth/pseudonymize.js';
import {
  auditRows,
  ativar2fa,
  freshApp,
  login,
  loginCom2fa,
  novoOperador,
  SENHA_VALIDA,
  TEST_ENV,
  type Fixture,
} from './support/app.js';

const IP = '203.0.113.7'; // faixa TEST-NET-3, reservada para documentacao

let f: Fixture;
before(async () => {
  f = await freshApp();
});
after(async () => f.close());

test('login recusado entra na trilha SEM ator e SEM o e-mail em claro', async () => {
  const operador = await novoOperador(f, 'editor', 'falhou@exemplo.invalid');
  await f.app.request('/api/auth/sign-in/email', {
    method: 'POST',
    headers: { 'content-type': 'application/json', origin: TEST_ENV.authBaseUrl, 'x-forwarded-for': IP },
    body: JSON.stringify({ email: operador.email, password: 'senha-errada-de-teste-123' }),
  });

  const linhas = await auditRows(f);
  const falha = linhas.find((l) => l.action === 'sign_in_failed');
  assert.ok(falha, 'a tentativa recusada precisa aparecer na trilha');

  // Sem ator: nao havia ninguem autenticado. Atribuir a tentativa a conta
  // visada afirmaria que a pessoa agiu, quando pode ter sido um ataque contra ela.
  assert.equal(falha.actor_id, null);

  // A entidade e o identificador ja hasheado. Registrar o e-mail transformaria
  // a trilha numa lista de quem tem conta.
  assert.equal(falha.entity_id, subjectKey(operador.email, TEST_ENV.hashSalt));
  assert.ok(!falha.entity_id.includes('@'));
});

test('o IP e gravado hasheado, nunca como veio', async () => {
  const linhas = await auditRows(f);
  const comIp = linhas.filter((l) => l.ip_hash !== null);
  assert.ok(comIp.length > 0, 'nenhuma entrada registrou origem');
  for (const linha of comIp) {
    assert.notEqual(linha.ip_hash, IP);
    assert.equal(linha.ip_hash, pseudonymize(IP, TEST_ENV.hashSalt));
    assert.match(linha.ip_hash!, /^[0-9a-f]{64}$/);
  }
});

test('o hash do IP depende do sal — sem ele seria reversivel', () => {
  // IPv4 tem 2^32 enderecos: `sha256(ip)` puro se inverte por forca bruta em
  // minutos, e a coluna voltaria a ser PII em claro.
  assert.notEqual(pseudonymize(IP, TEST_ENV.hashSalt), pseudonymize(IP, 'outro-sal-qualquer'));
});

test('a senha NAO aparece em lugar nenhum da trilha', async () => {
  const operador = await novoOperador(f, 'admin', 'senha-na-trilha@exemplo.invalid');
  const segredo = await ativar2fa(f, operador.email);
  await loginCom2fa(f, operador.email, segredo);

  const linhas = await auditRows(f);
  const tudo = JSON.stringify(linhas);
  assert.ok(!tudo.includes(SENHA_VALIDA), 'a senha vazou para a trilha');
  assert.ok(!tudo.includes('$argon2id$'), 'o hash da senha vazou para a trilha');
  assert.ok(!tudo.includes(segredo), 'o segredo TOTP vazou para a trilha');
});

test('login e ativacao de 2FA registram QUEM agiu', async () => {
  // Achado no roteiro contra o sqld real: sem resolver o ator, estas rotas
  // entravam na trilha com `actor_id` nulo, porque nao passam por
  // `requireSession`. "Quem ativou o segundo fator?" ficava sem resposta — que e
  // justamente a pergunta de uma auditoria de acesso.
  const operador = await novoOperador(f, 'editor', 'sucesso@exemplo.invalid');
  const segredo = await ativar2fa(f, operador.email);
  await loginCom2fa(f, operador.email, segredo);

  const linhas = await auditRows(f);
  const entrou = linhas.find((l) => l.action === 'sign_in' && l.actor_id === operador.id);
  assert.ok(entrou, 'login bem-sucedido sem ator na trilha');

  const ativou = linhas.find(
    (l) => l.action === 'two_factor_enable' && l.actor_id === operador.id,
  );
  assert.ok(ativou, 'ativacao de 2FA sem ator na trilha');
});

test('login RECUSADO continua sem ator', async () => {
  // Deliberado: atribuir a tentativa a conta visada afirmaria que a pessoa agiu,
  // quando pode ter sido um ataque contra ela.
  const linhas = await auditRows(f);
  for (const linha of linhas.filter((l) => l.action.endsWith('_failed'))) {
    assert.equal(linha.actor_id, null, `${linha.action} recebeu ator`);
  }
});

test('criacao de operador e registrada com papel, sem credencial', async () => {
  const criado = await novoOperador(f, 'clinical_reviewer', 'auditado@exemplo.invalid');
  const linhas = await auditRows(f);
  const entrada = linhas.find((l) => l.action === 'user_create' && l.entity_id === criado.id);
  assert.ok(entrada);
  const depois = JSON.parse(entrada.after_json ?? '{}') as Record<string, unknown>;
  assert.equal(depois.role, 'clinical_reviewer');
  assert.ok(!('password' in depois));
});

test('troca de papel guarda o ANTES e o DEPOIS', async () => {
  // Sem o "antes", a trilha diz que alguem virou admin e nao diz de onde veio —
  // que e justamente o que uma auditoria de escalada de privilegio procura.
  const admin = await novoOperador(f, 'admin', 'promotor@exemplo.invalid');
  const segredo = await ativar2fa(f, admin.email);
  const cookie = await loginCom2fa(f, admin.email, segredo);
  const alvo = await novoOperador(f, 'editor', 'promovido@exemplo.invalid');

  const r = await f.app.request(`/api/users/${alvo.id}`, {
    method: 'PATCH',
    headers: { cookie, 'content-type': 'application/json', origin: TEST_ENV.authBaseUrl },
    body: JSON.stringify({ role: 'admin' }),
  });
  assert.equal(r.status, 200);

  const linhas = await auditRows(f);
  const troca = linhas.find((l) => l.action === 'user_role_change' && l.entity_id === alvo.id);
  assert.ok(troca);
  assert.equal(troca.actor_id, admin.id, 'a trilha precisa dizer QUEM promoveu');
  assert.deepEqual(JSON.parse(troca.before_json!), { role: 'editor' });
  assert.deepEqual(JSON.parse(troca.after_json!), { role: 'admin' });
});

test('a trilha continua append-only por gatilho, com o app rodando', async () => {
  // O gatilho e do item 16; esta afirmacao existe porque a trilha so vale se o
  // caminho de aplicacao tambem nao conseguir apagar.
  await assert.rejects(() => f.client.execute('DELETE FROM audit_entry'), /append-only/);
  await assert.rejects(
    () => f.client.execute("UPDATE audit_entry SET action = 'nada'"),
    /append-only/,
  );
});
