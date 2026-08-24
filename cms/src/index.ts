/**
 * Ponto de entrada do plano de controle.
 *
 * O ambiente e lido ANTES de qualquer coisa subir: `loadEnv()` derruba o
 * processo se faltar `BETTER_AUTH_SECRET` ou `IP_HASH_SALT`. Falhar no boot e o
 * comportamento certo — um servidor que sobe sem sal grava PII em claro na
 * trilha e nada acusa.
 */
import { serve } from '@hono/node-server';

import { createApp } from './app.js';
import { createDatabaseClient } from './db/client.js';
import { loadEnv } from './env.js';

const env = loadEnv();
const client = createDatabaseClient(env.databaseUrl);
const { app } = createApp({ client, env });

serve({ fetch: app.fetch, port: env.port }, (info) => {
  console.log(`[cms] escutando em http://127.0.0.1:${info.port}`);
});
