/**
 * Argon2id, e nao "algum hash" (lgpd.md LGPD-RT06).
 *
 * O teste olha o PREFIXO do hash porque e a unica evidencia verificavel de qual
 * algoritmo rodou: `verify` devolveria `true` igualmente se alguem trocasse por
 * scrypt, e a troca passaria despercebida ate uma auditoria perguntar.
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { hashPassword, verifyPassword } from '../src/auth/password.js';

const SENHA = 'senha-ficticia-de-teste-123';

test('o hash e Argon2id, e o prefixo prova qual algoritmo rodou', async () => {
  const hash = await hashPassword(SENHA);
  assert.ok(hash.startsWith('$argon2id$'), `algoritmo inesperado: ${hash.slice(0, 20)}`);
});

test('parametros da OWASP presentes no hash', async () => {
  // m=19456 KiB, t=2, p=1. Estao no proprio hash, entao um downgrade de custo
  // e visivel aqui — e downgrade de custo e a forma silenciosa de enfraquecer
  // um hash sem trocar de algoritmo.
  const hash = await hashPassword(SENHA);
  assert.match(hash, /\$m=19456,t=2,p=1\$/);
});

test('senha correta verifica', async () => {
  const hash = await hashPassword(SENHA);
  assert.equal(await verifyPassword({ hash, password: SENHA }), true);
});

test('senha errada nao verifica', async () => {
  const hash = await hashPassword(SENHA);
  assert.equal(await verifyPassword({ hash, password: `${SENHA}x` }), false);
});

test('dois hashes da mesma senha diferem (sal por hash)', async () => {
  assert.notEqual(await hashPassword(SENHA), await hashPassword(SENHA));
});

test('hash corrompido devolve false em vez de explodir', async () => {
  // 500 no login distinguiria "conta existe com hash quebrado" de "conta nao
  // existe", e essa diferenca e um oraculo de enumeracao de contas.
  assert.equal(await verifyPassword({ hash: 'lixo', password: SENHA }), false);
});
