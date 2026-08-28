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
 *
 * E vale, pelo mesmo motivo, para o esquema do `BETTER_AUTH_URL` — ver
 * `exigirTlsForaDoLoopback`.
 */

/**
 * `source` explicito, e nao `process.env` direto.
 *
 * `loadEnv` recebe um ambiente e ate o item 24 esta funcao ignorava: um teste que
 * montasse um ambiente proprio via parametro exercitava metade do arquivo contra
 * o ambiente REAL do processo. Passava por acidente enquanto o `.env` do
 * desenvolvedor tinha os segredos, e falharia em CI por um motivo que nao e o do
 * teste.
 */
function obrigatorio(source: NodeJS.ProcessEnv, nome: string, minimo = 32): string {
  const valor = source[nome];
  if (!valor || valor.length < minimo) {
    throw new Error(
      `${nome} ausente ou curto demais (minimo ${minimo} caracteres). ` +
        'Gere com `openssl rand -base64 48` e defina em infra/.env — ' +
        'nunca versione o valor.',
    );
  }
  return valor;
}

/**
 * `http://` so e aceito quando o destino e o proprio computador.
 *
 * O Better Auth deriva `secure` e o prefixo `__Secure-` do cookie de sessao de
 * exatamente um predicado (`cookies/index.mjs`:
 * `baseURLString.startsWith("https://")`, e `secure: !!secureCookiePrefix` — a
 * mesma variavel decide os dois). Nao ha bloco `advanced` em `auth/config.ts`
 * que sobrescreva. Entao um `BETTER_AUTH_URL` em `http://` significa senha,
 * codigo TOTP e cookie de sessao trafegando em claro, e **nada acusa**.
 *
 * ## Por que o criterio e o LOOPBACK, e nao `NODE_ENV`
 *
 * A primeira versao desta guarda recusava `http://` quando `NODE_ENV` era
 * `production` — e quebrou o proprio ambiente de desenvolvimento, porque o
 * `cms/Dockerfile` define `ENV NODE_ENV=production` e o compose de dev roda essa
 * mesma imagem por HTTP. Descoberto subindo a topologia, nao em teste.
 *
 * Consertar seria facil (bastava `NODE_ENV=development` no override), mas o
 * criterio estaria errado do mesmo jeito: ele apostava num ROTULO, e quem
 * implanta com o rotulo trocado perde a protecao em silencio — que e exatamente
 * o modo de falha que esta guarda existe para impedir.
 *
 * O loopback e o risco em si: `127.0.0.1` nao atravessa rede nenhuma, e
 * qualquer outro host atravessa. Vale em producao, em desenvolvimento e numa
 * maquina de CI, sem depender de ninguem configurar nada certo.
 *
 * Consequencia deliberada: testar de um celular na mesma rede
 * (`http://192.168.1.10:8082`) tambem e recusado — ali a credencial cruza um
 * cabo de verdade. Para esse caso, `tls internal` no Caddy de desenvolvimento.
 */
const LOOPBACK = new Set(['127.0.0.1', 'localhost', '[::1]', '::1']);

function exigirTlsForaDoLoopback(url: string): void {
  if (url.startsWith('https://')) return;

  let host: string;
  try {
    host = new URL(url).hostname;
  } catch {
    throw new Error(`BETTER_AUTH_URL nao e uma URL valida: "${url}"`);
  }
  if (LOOPBACK.has(host)) return;

  throw new Error(
    `BETTER_AUTH_URL precisa ser "https://" fora do loopback — recebido "${url}". ` +
      'Com http, o cookie de sessao sai SEM `Secure` e sem o prefixo `__Secure-`, ' +
      'e senha, codigo TOTP e sessao atravessam a rede em claro. Aponte para o ' +
      'hostname do CMS atras do edge (CMS_DOMAIN em infra/.env).',
  );
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
  const authBaseUrl = source.BETTER_AUTH_URL ?? 'http://127.0.0.1:8787';
  exigirTlsForaDoLoopback(authBaseUrl);

  return {
    databaseUrl: source.CMS_DATABASE_URL ?? 'http://127.0.0.1:8080',
    databaseAuthToken: source.CMS_DATABASE_AUTH_TOKEN,
    authSecret: obrigatorio(source, 'BETTER_AUTH_SECRET'),
    authBaseUrl,
    hashSalt: obrigatorio(source, 'IP_HASH_SALT'),
    port: Number(source.PORT ?? 8787),
  };
}
