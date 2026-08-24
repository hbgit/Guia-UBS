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
import { assertForeignKeysEnforced, createDatabaseClient } from './db/client.js';
import { loadEnv } from './env.js';

const env = loadEnv();
const client = createDatabaseClient(env.databaseUrl);

// Antes de aceitar a primeira requisicao: sem FK, apagar um token deixa regra
// clinica orfa em silencio, e o CRUD do item 18 depende inteiro disso.
await assertForeignKeysEnforced(client);

const { app } = createApp({ client, env });

serve({ fetch: app.fetch, port: env.port }, (info) => {
  console.log(`[cms] escutando em http://127.0.0.1:${info.port}`);
});
