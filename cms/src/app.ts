/**
 * Montagem do aplicativo Hono — separada de `index.ts` para que os testes
 * exercitem exatamente o mesmo grafo de rotas SEM subir porta nenhuma
 * (`app.request()`).
 *
 * Um app de teste montado a parte seria um app que diverge do que roda: a rota
 * esquecida no meio ficaria protegida no teste e aberta em producao.
 */
import type { Client } from '@libsql/client';
import { Hono } from 'hono';

import { createAuth, type Auth } from './auth/config.js';
import {
  auditAndThrottleAuth,
  require2fa,
  requireSession,
  type AuthVariables,
} from './auth/middleware.js';
import { mensagemDoErro } from './db/errors.js';
import type { Env } from './env.js';
import { contentRoutes } from './routes/content.js';
import { approvalRoutes } from './routes/approvals.js';
import { meRoutes } from './routes/me.js';
import { releaseRoutes } from './routes/releases.js';
import { telemetryRoutes } from './routes/telemetry.js';
import { ruleRoutes } from './routes/rules.js';
import { userRoutes } from './routes/users.js';
import { montarSpa, RAIZ_DA_SPA } from './web.js';

export interface App {
  app: Hono<{ Variables: AuthVariables }>;
  auth: Auth;
}

export function createApp({
  client,
  env,
  rateLimit = true,
  spa = RAIZ_DA_SPA,
}: {
  client: Client;
  env: Env;
  /** Ver `AuthOptions.rateLimit`: so o teste passa `false`. */
  rateLimit?: boolean;
  /**
   * Raiz da interface construida. So o teste informa outra coisa — e informa um
   * diretorio temporario, para que a suite nao dependa de alguem ter rodado
   * `npm run web:build`.
   */
  spa?: string;
}): App {
  const auth = createAuth({ client, env, rateLimit });
  const app = new Hono<{ Variables: AuthVariables }>();

  /**
   * Unica rota sem autenticacao, e a excecao e declarada (lgpd.md LGPD-RT01):
   * e o healthcheck do compose. Responde uma constante e nao toca no banco de
   * identidade — nao ha o que vazar.
   */
  app.get('/health', (c) => c.json({ status: 'ok' }));

  /**
   * SEGUNDA excecao declarada a LGPD-RT01, e a ultima.
   *
   * Nao ha alternativa: autenticar exigiria identidade de dispositivo, que a
   * INV-2 proibe. Fica ANTES do grupo protegido de proposito — montada dentro
   * dele, herdaria `requireSession` e nenhum produtor conseguiria falar com ela.
   *
   * `test/telemetry-ingest.test.ts` afirma que esta e a unica rota de `/api` que
   * dispensa sessao.
   */
  app.route('/api/telemetry', telemetryRoutes(client));

  // Trava progressiva e trilha ANTES do handler do Better Auth.
  app.use('/api/auth/*', auditAndThrottleAuth(auth, client, env.hashSalt));
  app.on(['GET', 'POST'], '/api/auth/*', (c) => auth.handler(c.req.raw));

  // Tudo abaixo exige sessao valida, operador ativo e 2FA ativa.
  const protegido = new Hono<{ Variables: AuthVariables }>();
  protegido.use('*', requireSession(auth));
  protegido.use('*', require2fa());
  protegido.route('/me', meRoutes());
  protegido.route('/users', userRoutes(client, env.hashSalt));
  protegido.route('/content', contentRoutes(client, env.hashSalt));
  protegido.route('/rules', ruleRoutes(client, env.hashSalt));
  protegido.route('/releases', releaseRoutes(client, env.hashSalt));
  protegido.route('/approvals', approvalRoutes(client, env.hashSalt));

  app.route('/api', protegido);

  /**
   * A interface entra por ULTIMO, e a ordem e a garantia: o Hono compoe os
   * handlers na ordem de registro, entao `/health` e `/api/*` ja responderam
   * quando a SPA e consultada. Um arquivo chamado `health` dentro de `dist/` nao
   * sombreia o healthcheck do compose. `test/web-static.test.ts` afirma isso.
   *
   * Montada com `app.use`, nunca com `app.get('*')`: `use` grava `method: 'ALL'`,
   * que `test/doc-operacao.test.ts` filtra ao percorrer `app.routes`. Um
   * `GET *` no catalogo faria o teste "toda rota aparece no manual" passar
   * VAZIAMENTE — o manual contem `*` em qualquer negrito. Asserção verde por
   * vacuidade e pior que vermelha.
   */
  montarSpa(app, spa);

  /**
   * Erro nao vaza detalhe (LGPD-RT01): a resposta e generica e o servidor fica
   * com o rastro. Mensagem de excecao pode carregar valor de coluna, e coluna
   * daqui carrega dado pessoal.
   */
  app.onError((erro, c) => {
    // A cadeia inteira de `cause`, e nao so `erro.message`: o Drizzle SUBSTITUI
    // a mensagem do driver por "Failed query: <sql>" e guarda a original em
    // `cause`. Logar so a superficie esconde exatamente a linha que diz o que
    // deu errado — foi assim que uma violacao de FK apareceu como 500 sem
    // explicacao durante o item 18.
    console.error('[cms]', mensagemDoErro(erro));
    return c.json({ error: 'erro interno' }, 500);
  });

  return { app, auth };
}

