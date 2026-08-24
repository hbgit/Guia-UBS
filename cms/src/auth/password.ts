/**
 * Argon2id para senha de operador (lgpd.md LGPD-RT06).
 *
 * O Better Auth usa scrypt por padrao. Trocar nao e preferencia: o requisito
 * nomeia Argon2id, e a substituicao e suportada pela propria biblioteca
 * (`emailAndPassword.password.hash/verify`) — nao ha fork nem monkey-patch.
 *
 * Parametros conforme a recomendacao da OWASP para Argon2id: 19 MiB de memoria,
 * 2 iteracoes, paralelismo 1. Memoria alta e o ponto: e o que torna o ataque com
 * GPU caro, e o que scrypt tambem busca mas com margem menor.
 */
import { Algorithm, hash, verify } from '@node-rs/argon2';

const PARAMETROS = {
  algorithm: Algorithm.Argon2id,
  memoryCost: 19_456,
  timeCost: 2,
  parallelism: 1,
} as const;

export async function hashPassword(password: string): Promise<string> {
  return hash(password, PARAMETROS);
}

/**
 * Assinatura ditada pelo Better Auth: recebe `{ hash, password }`.
 *
 * Devolve `false` em vez de propagar quando o hash e ilegivel. Um hash
 * corrompido no banco nao pode virar erro 500 no login: 500 distingue "conta
 * existe com hash quebrado" de "conta nao existe", e essa diferenca e um oraculo
 * de enumeracao de contas.
 */
export async function verifyPassword({
  hash: hashed,
  password,
}: {
  hash: string;
  password: string;
}): Promise<boolean> {
  try {
    return await verify(hashed, password, PARAMETROS);
  } catch {
    return false;
  }
}
