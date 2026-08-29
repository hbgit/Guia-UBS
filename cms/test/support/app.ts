/**
 * Aplicativo de teste: o MESMO `createApp()` que roda em producao, contra libSQL
 * em memoria.
 *
 * libSQL e nao `node:sqlite` como nos testes do item 16, e a diferenca importa:
 * o Better Auth fala com o banco pelo adapter Drizzle/libSQL. Testar por outro
 * caminho exercitaria uma aproximacao do que roda, e o adapter e justamente onde
 * um mapeamento errado de coluna se esconde.
 *
 * Nenhuma porta e aberta: Hono responde a `app.request()` em processo.
 */
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { base32 } from '@better-auth/utils/base32';
import { createOTP } from '@better-auth/utils/otp';
import { createClient, type Client } from '@libsql/client';

import { createApp, type App } from '../../src/app.js';
import { migrationStatements } from '../../src/db/client.js';
import type { Env } from '../../src/env.js';
import { createOperator } from '../../src/services/operators.js';
import type { AdminRole } from '../../src/auth/permissions.js';

/** Segredos FICTICIOS, longos o bastante para passar pela validacao de `loadEnv`. */
export const TEST_ENV: Env = {
  databaseUrl: ':memory:',
  authSecret: 'segredo-de-teste-ficticio-com-mais-de-32-caracteres',
  authBaseUrl: 'http://localhost',
  hashSalt: 'sal-de-teste-ficticio-com-mais-de-32-caracteres',
  port: 0,
};

export interface Fixture extends App {
  client: Client;
  close(): Promise<void>;
}

/**
 * Banco em ARQUIVO temporario, nao `:memory:`.
 *
 * Descoberto ao escrever o editor de regras: com `url: ':memory:'`, cada conexao
 * do libSQL abre um banco PROPRIO e vazio. Uma transacao — que abre conexao nova
 * — cai num schema inexistente, e o sintoma e "no such table" numa tabela que
 * acabou de ser usada. Nada no fixture denunciaria isso; os testes anteriores
 * passavam porque nenhum deles usava transacao.
 *
 * Um arquivo tambem aproxima o teste do que roda: o `sqld` e um servidor com um
 * banco so, e nao um banco por conexao.
 */
export async function freshApp(spa?: string): Promise<Fixture> {
  const diretorio = mkdtempSync(join(tmpdir(), 'gubs-cms-'));
  const client = createClient({ url: `file:${join(diretorio, 'cms.db')}` });
  for (const statement of migrationStatements()) await client.execute(statement);
  // Rate limit desligado: dezenas de logins em segundos bateriam no teto de
  // 5/60s e cada teste seguinte viraria falso vermelho. A trava progressiva por
  // CONTA — que e a protecao exigida pela LGPD-RT07 — continua ligada.
  //
  // `spa` aponta, por padrao, para um diretorio temporario SEM `index.html`. Sem
  // isso a suite mudaria de comportamento conforme quem a roda tivesse ou nao
  // executado `npm run web:build`: com um `dist` presente, toda rota inexistente
  // devolveria a casca em vez de 404. Quem quer a interface servida informa a
  // raiz (ver `web-static.test.ts`).
  const montado = createApp({
    client,
    env: TEST_ENV,
    rateLimit: false,
    spa: spa ?? join(diretorio, 'sem-interface'),
  });
  return {
    ...montado,
    client,
    close: async () => {
      client.close();
      rmSync(diretorio, { recursive: true, force: true });
    },
  };
}

export const SENHA_VALIDA = 'senha-ficticia-de-teste-123';

/**
 * Cabecalhos de uma requisicao que muda estado.
 *
 * O `origin` nao e enfeite: o Better Auth RECUSA POST sem ele, como protecao
 * contra CSRF. Um navegador sempre envia; o cliente de teste tem que enviar
 * tambem, senao os testes exercitariam um caminho que nenhum navegador percorre.
 * A garantia em si esta afirmada em `auth-flow.test.ts`.
 */
function cabecalhos(cookie?: string): Record<string, string> {
  return {
    'content-type': 'application/json',
    origin: TEST_ENV.authBaseUrl,
    ...(cookie ? { cookie } : {}),
  };
}

/** Cria um operador com credencial utilizavel. */
export async function novoOperador(
  fixture: Fixture,
  role: AdminRole,
  email = `${role}@exemplo.invalid`,
): Promise<{ id: string; email: string }> {
  const criado = await createOperator(
    fixture.client,
    TEST_ENV.hashSalt,
    { email, name: `Operador ${role}`, role, password: SENHA_VALIDA },
    null,
  );
  return { id: criado.id, email: criado.email };
}

/** Faz login e devolve o cookie de sessao, ou `null` se a resposta nao for 2xx. */
export async function login(
  fixture: Fixture,
  email: string,
  password = SENHA_VALIDA,
): Promise<{ status: number; cookie: string | null }> {
  const resposta = await fixture.app.request('/api/auth/sign-in/email', {
    method: 'POST',
    headers: cabecalhos(),
    body: JSON.stringify({ email, password }),
  });
  return { status: resposta.status, cookie: resposta.headers.get('set-cookie') };
}

/**
 * Ativa a 2FA pelo fluxo REAL, do jeito que um operador faz.
 *
 * A tentacao era carimbar `two_factor_enabled = 1` no banco e seguir. Isso
 * mascararia o comportamento que mais importa aqui: com 2FA ativa, o
 * `sign-in/email` NAO devolve sessao — devolve um estado pendente, e a sessao so
 * nasce depois do codigo TOTP. Um atalho no banco produziria testes verdes sobre
 * um fluxo que nunca foi exercitado.
 *
 * Devolve o segredo TOTP, que os logins seguintes precisam para gerar o codigo.
 */
export async function ativar2fa(fixture: Fixture, email: string): Promise<string> {
  const inicial = await login(fixture, email);
  assert.ok(inicial.cookie, 'login inicial deveria abrir sessao antes da 2FA existir');

  const resposta = await fixture.app.request('/api/auth/two-factor/enable', {
    method: 'POST',
    headers: cabecalhos(inicial.cookie),
    body: JSON.stringify({ password: SENHA_VALIDA }),
  });
  assert.equal(resposta.status, 200, `enable respondeu ${resposta.status}`);
  const corpo = (await resposta.json()) as { totpURI: string };

  const segredo = new URL(corpo.totpURI).searchParams.get('secret');
  assert.ok(segredo, 'o totpURI deveria carregar o segredo');

  // `enable` NAO liga a 2FA: ele entrega o segredo e deixa `verified = 0`. A
  // ativacao so acontece quando a pessoa prova ter o autenticador, num login
  // novo — o que e a ordem correta, porque o contrario trancaria para fora quem
  // digitou o segredo errado no aplicativo.
  return segredo;
}

/**
 * Codigo TOTP do instante, pelo mesmo gerador que o Better Auth usa.
 *
 * O `secret` que vem no `totpURI` esta em **base32** — e o formato que o
 * aplicativo autenticador le. `createOTP` espera o segredo BRUTO. Passar a
 * string base32 direto produz um codigo que parece valido, tem seis digitos, e
 * nunca confere: o erro so aparece como "Invalid code" na verificacao.
 */
export async function totp(segredoBase32: string): Promise<string> {
  const bruto = base32.decode(segredoBase32);
  const texto = typeof bruto === 'string' ? bruto : new TextDecoder().decode(bruto);
  return createOTP(texto, { digits: 6, period: 30 }).totp();
}

/**
 * Login completo de operador com 2FA: senha e depois codigo.
 *
 * Devolve o cookie de SESSAO, nao o de 2FA pendente — sao coisas diferentes, e
 * confundi-los foi o primeiro defeito que estes testes pegaram.
 */
export async function loginCom2fa(
  fixture: Fixture,
  email: string,
  segredo: string,
): Promise<string> {
  const primeira = await login(fixture, email);
  assert.ok(primeira.cookie, 'a etapa de senha deveria devolver cookie');

  const segunda = await fixture.app.request('/api/auth/two-factor/verify-totp', {
    method: 'POST',
    headers: cabecalhos(primeira.cookie),
    body: JSON.stringify({ code: await totp(segredo) }),
  });
  assert.equal(segunda.status, 200, `verify-totp respondeu ${segunda.status}`);
  const cookie = segunda.headers.get('set-cookie');
  assert.ok(cookie, 'a verificacao do TOTP deveria emitir a sessao');
  return cookie;
}

export async function auditRows(
  fixture: Fixture,
): Promise<{ action: string; actor_id: string | null; entity_id: string; ip_hash: string | null; before_json: string | null; after_json: string | null }[]> {
  const r = await fixture.client.execute('SELECT * FROM audit_entry ORDER BY occurred_at');
  return r.rows as never;
}

/**
 * Sessao pronta de um papel: cria operador, ativa 2FA pelo fluxo real e loga.
 *
 * Existe porque toda rota protegida exige os tres passos, e repeti-los em cada
 * teste esconderia o que o teste realmente afirma no meio do preparo.
 */
export async function sessaoDe(
  fixture: Fixture,
  role: AdminRole,
  email = `${role}-${Math.random().toString(36).slice(2, 8)}@exemplo.invalid`,
): Promise<{ cookie: string; id: string; email: string }> {
  const operador = await novoOperador(fixture, role, email);
  const segredo = await ativar2fa(fixture, operador.email);
  const cookie = await loginCom2fa(fixture, operador.email, segredo);
  return { cookie, id: operador.id, email: operador.email };
}

/** Requisicao autenticada com corpo JSON. `If-Match` entra como cabecalho. */
export async function pedido(
  fixture: Fixture,
  cookie: string,
  metodo: string,
  caminho: string,
  corpo?: unknown,
  ifMatch?: string | number,
): Promise<Response> {
  const headers: Record<string, string> = {
    cookie,
    origin: TEST_ENV.authBaseUrl,
    ...(corpo === undefined ? {} : { 'content-type': 'application/json' }),
    ...(ifMatch === undefined ? {} : { 'if-match': `"${ifMatch}"` }),
  };
  return await fixture.app.request(caminho, {
    method: metodo,
    headers,
    ...(corpo === undefined ? {} : { body: JSON.stringify(corpo) }),
  });
}

/**
 * Conteudo minimo para as entidades que dependem de FK: um asset (alvo de quase
 * todas) e um municipio (exigido pelas municipais).
 */
export async function seedConteudo(fixture: Fixture, cookie: string): Promise<void> {
  await pedido(fixture, cookie, 'POST', '/api/content/assets', {
    ref: 'icon.exemplo',
    kind: 'icon',
    path: 'assets/exemplo.svg',
    // Sem `sha256` nem `bytes`: desde o item 25 eles saem do ENVIO do binario,
    // e o `$defaultFn` os torna opcionais no POST. Digita-los aqui manteria vivo
    // o habito que a rota de envio existe para encerrar.
  });
  await pedido(fixture, cookie, 'POST', '/api/content/municipalities', {
    id: 'mun-1',
    code: '0000000',
    name: 'Municipio Exemplo',
  });
}
