/**
 * Segredos e configuracao de ambiente, lidos UMA vez e validados no boot.
 *
 * A regra deste arquivo: **falta de segredo derruba o processo**, nunca cai num
 * padrao. Um `IP_HASH_SALT` ausente que virasse string vazia produziria
 * `sha256(ip)` puro — e o espaco IPv4 tem 2^32 enderecos, entao hash sem sal e
 * reversivel por forca bruta em minutos. A trilha de auditoria passaria a
 * guardar PII em claro com um passo a mais, e nada no sistema acusaria.
 *
 * O mesmo vale para o `BETTER_AUTH_SECRET`: e a chave que cifra o segredo TOTP
 * em repouso. Um padrao previsivel ali significa 2FA decorativa.
 */

function obrigatorio(nome: string, minimo = 32): string {
  const valor = process.env[nome];
  if (!valor || valor.length < minimo) {
    throw new Error(
      `${nome} ausente ou curto demais (minimo ${minimo} caracteres). ` +
        'Gere com `openssl rand -base64 48` e defina em infra/.env — ' +
        'nunca versione o valor.',
    );
  }
  return valor;
}

export interface Env {
  databaseUrl: string;
  databaseAuthToken?: string;
  authSecret: string;
  authBaseUrl: string;
  /** Sal dos hashes de pseudonimizacao (IP na trilha, e-mail na trava). */
  hashSalt: string;
  port: number;
}

/**
 * Le o ambiente. Chamada no boot e nos testes; nao guarda estado global, para
 * que um teste possa montar um ambiente proprio sem contaminar o seguinte.
 */
export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  return {
    databaseUrl: source.CMS_DATABASE_URL ?? 'http://127.0.0.1:8080',
    databaseAuthToken: source.CMS_DATABASE_AUTH_TOKEN,
    authSecret: obrigatorio('BETTER_AUTH_SECRET'),
    authBaseUrl: source.BETTER_AUTH_URL ?? 'http://127.0.0.1:8787',
    hashSalt: obrigatorio('IP_HASH_SALT'),
    port: Number(source.PORT ?? 8787),
  };
}
