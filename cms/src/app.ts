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
import type { Env } from './env.js';
import { meRoutes } from './routes/me.js';
import { userRoutes } from './routes/users.js';

export interface App {
  app: Hono<{ Variables: AuthVariables }>;
  auth: Auth;
}

export function createApp({
  client,
  env,
  rateLimit = true,
}: {
  client: Client;
  env: Env;
  /** Ver `AuthOptions.rateLimit`: so o teste passa `false`. */
  rateLimit?: boolean;
}): App {
  const auth = createAuth({ client, env, rateLimit });
  const app = new Hono<{ Variables: AuthVariables }>();

  /**
   * Unica rota sem autenticacao, e a excecao e declarada (lgpd.md LGPD-RT01):
   * e o healthcheck do compose. Responde uma constante e nao toca no banco de
   * identidade — nao ha o que vazar.
   */
  app.get('/health', (c) => c.json({ status: 'ok' }));

  // Trava progressiva e trilha ANTES do handler do Better Auth.
  app.use('/api/auth/*', auditAndThrottleAuth(auth, client, env.hashSalt));
  app.on(['GET', 'POST'], '/api/auth/*', (c) => auth.handler(c.req.raw));

  // Tudo abaixo exige sessao valida, operador ativo e 2FA ativa.
  const protegido = new Hono<{ Variables: AuthVariables }>();
  protegido.use('*', requireSession(auth));
  protegido.use('*', require2fa());
  protegido.route('/me', meRoutes());
  protegido.route('/users', userRoutes(client, env.hashSalt));

  app.route('/api', protegido);

  /**
   * Erro nao vaza detalhe (LGPD-RT01): a resposta e generica e o servidor fica
   * com o rastro. Mensagem de excecao pode carregar valor de coluna, e coluna
   * daqui carrega dado pessoal.
   */
  app.onError((erro, c) => {
    console.error('[cms]', erro.message);
    return c.json({ error: 'erro interno' }, 500);
  });

  return { app, auth };
}
