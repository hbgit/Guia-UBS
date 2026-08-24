/**
 * Bloqueio progressivo por conta (lgpd.md LGPD-RT07).
 *
 * A curva e funcao pura e e testada FORA da faixa alcancavel — do mesmo jeito
 * que o backoff do sync do app. Um teto que nunca binda com os parametros de
 * hoje continua sendo um teto que precisa estar certo quando alguem mexer nos
 * parametros.
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  BASE_DELAY_SECONDS,
  FREE_ATTEMPTS,
  MAX_DELAY_SECONDS,
  isLocked,
  lockoutDelaySeconds,
} from '../src/auth/lockout.js';

test('as primeiras tentativas nao atrasam — errar a senha acontece', () => {
  for (let n = 0; n <= FREE_ATTEMPTS; n += 1) {
    assert.equal(lockoutDelaySeconds(n), 0, `${n} falhas nao deveriam atrasar`);
  }
});

test('o atraso dobra a cada falha depois da folga', () => {
  assert.equal(lockoutDelaySeconds(3), BASE_DELAY_SECONDS);
  assert.equal(lockoutDelaySeconds(4), BASE_DELAY_SECONDS * 2);
  assert.equal(lockoutDelaySeconds(5), BASE_DELAY_SECONDS * 4);
  assert.equal(lockoutDelaySeconds(6), BASE_DELAY_SECONDS * 8);
});

test('o teto segura o crescimento', () => {
  // Fora da faixa que os parametros de hoje alcancam: e exatamente onde um teto
  // quebrado nao apareceria em teste nenhum.
  assert.equal(lockoutDelaySeconds(30), MAX_DELAY_SECONDS);
  assert.equal(lockoutDelaySeconds(1000), MAX_DELAY_SECONDS);
  assert.ok(Number.isFinite(lockoutDelaySeconds(1000)));
});

test('o teto nao e tao alto que o ataque derrube a conta do operador', () => {
  // Atraso que nao para de dobrar vira negacao de servico contra quem precisa
  // publicar uma correcao clinica.
  assert.ok(MAX_DELAY_SECONDS <= 60 * 60, 'teto acima de uma hora tranca o operador');
});

test('a trava expira', () => {
  const agora = new Date('2026-08-24T12:00:00Z');
  const passado = { failures: 5, lockedUntil: new Date('2026-08-24T11:59:59Z') };
  const futuro = { failures: 5, lockedUntil: new Date('2026-08-24T12:00:01Z') };
  assert.equal(isLocked(passado, agora), false);
  assert.equal(isLocked(futuro, agora), true);
  assert.equal(isLocked({ failures: 0, lockedUntil: null }, agora), false);
});
