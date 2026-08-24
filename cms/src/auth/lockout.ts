/**
 * Bloqueio progressivo de forca bruta, por CONTA (lgpd.md LGPD-RT07).
 *
 * O rate limit do Better Auth e janela fixa por ENDPOINT. Quem distribui as
 * tentativas entre varios IPs — que e como um ataque real funciona — passa por
 * baixo dele sem esforco. Progressivo so faz sentido contra o ALVO.
 *
 * A conta e identificada por `subjectKey`: o e-mail hasheado com sal. Guardar o
 * e-mail em claro transformaria a tabela numa lista de quem tem conta no
 * sistema.
 */
import type { Client } from '@libsql/client';
import { eq } from 'drizzle-orm';

import { createDb } from '../db/client.js';
import { loginAttempt } from '../db/schema/auth.js';

/** Tentativas antes de comecar a atrasar. Erro de digitacao acontece. */
export const FREE_ATTEMPTS = 2;
/** Primeiro atraso, em segundos. */
export const BASE_DELAY_SECONDS = 30;
/**
 * Teto do atraso.
 *
 * Existe porque atraso que nao para de dobrar vira negacao de servico contra o
 * proprio operador: `2^11 * 30 s` passa de meio dia, e nesse ponto um ataque
 * barato derruba a conta de quem precisa publicar uma correcao clinica.
 */
export const MAX_DELAY_SECONDS = 15 * 60;

/**
 * Atraso para um dado numero de falhas CONSECUTIVAS. Funcao pura — testada fora
 * da faixa alcancavel, do jeito que o backoff do sync ja e.
 */
export function lockoutDelaySeconds(failures: number): number {
  if (failures <= FREE_ATTEMPTS) return 0;
  const dobras = failures - FREE_ATTEMPTS - 1;
  return Math.min(BASE_DELAY_SECONDS * 2 ** dobras, MAX_DELAY_SECONDS);
}

export interface LockoutState {
  failures: number;
  lockedUntil: Date | null;
}

export async function readLockout(client: Client, subjectKey: string): Promise<LockoutState> {
  const db = createDb(client);
  const linha = await db.query.loginAttempt.findFirst({
    where: (t, { eq: igual }) => igual(t.subjectKey, subjectKey),
  });
  return {
    failures: linha?.failures ?? 0,
    lockedUntil: linha?.lockedUntil ? new Date(linha.lockedUntil) : null,
  };
}

/** `true` quando a conta esta travada NESTE instante. */
export function isLocked(state: LockoutState, agora = new Date()): boolean {
  return state.lockedUntil !== null && state.lockedUntil > agora;
}

/** Registra uma falha e devolve o estado resultante. */
export async function registerFailure(
  client: Client,
  subjectKey: string,
  agora = new Date(),
): Promise<LockoutState> {
  const db = createDb(client);
  const atual = await readLockout(client, subjectKey);
  const failures = atual.failures + 1;
  const atraso = lockoutDelaySeconds(failures);
  const lockedUntil = atraso > 0 ? new Date(agora.getTime() + atraso * 1000) : null;

  await db
    .insert(loginAttempt)
    .values({
      subjectKey,
      failures,
      lastFailureAt: agora.toISOString(),
      lockedUntil: lockedUntil?.toISOString() ?? null,
    })
    .onConflictDoUpdate({
      target: loginAttempt.subjectKey,
      set: {
        failures,
        lastFailureAt: agora.toISOString(),
        lockedUntil: lockedUntil?.toISOString() ?? null,
      },
    });

  return { failures, lockedUntil };
}

/**
 * Zera apos autenticacao bem-sucedida.
 *
 * Zerar e nao apagar seria manter historico de falhas de quem ja provou ser
 * dono da conta — dado pessoal sem finalidade vigente (LGPD-RF07). A linha sai.
 */
export async function clearFailures(client: Client, subjectKey: string): Promise<void> {
  const db = createDb(client);
  await db.delete(loginAttempt).where(eq(loginAttempt.subjectKey, subjectKey));
}
