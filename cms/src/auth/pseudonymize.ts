/**
 * Pseudonimizacao com sal — usada pelo `ip_hash` da trilha e pelo `subject_key`
 * da trava de login.
 *
 * O sal e a diferenca entre pseudonimizar e nao fazer nada. Sem ele:
 *
 *   - IPv4 tem 2^32 enderecos. Um `sha256(ip)` puro se inverte por forca bruta
 *     em minutos num laptop, e a coluna volta a ser PII em claro.
 *   - E-mail tem entropia baixa em populacao conhecida (nomes de servidores
 *     municipais seguem padrao), entao vale o mesmo.
 *
 * `loadEnv()` recusa subir sem `IP_HASH_SALT`, entao nao existe caminho de
 * codigo que produza hash sem sal.
 */
import { createHash } from 'node:crypto';

export function pseudonymize(valor: string, sal: string): string {
  if (!sal) throw new Error('pseudonymize chamada sem sal — ver loadEnv()');
  return createHash('sha256').update(`${sal}:${valor}`).digest('hex');
}

/** Normaliza antes de hashear: `Ana@X.org` e `ana@x.org` sao a mesma conta. */
export function subjectKey(email: string, sal: string): string {
  return pseudonymize(email.trim().toLowerCase(), sal);
}
