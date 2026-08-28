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
import { RAIZ_DA_SPA, temInterface } from './web.js';

const env = loadEnv();
const client = createDatabaseClient(env.databaseUrl);

// Antes de aceitar a primeira requisicao: sem FK, apagar um token deixa regra
// clinica orfa em silencio, e o CRUD do item 18 depende inteiro disso.
await assertForeignKeysEnforced(client);

const { app } = createApp({ client, env });

/**
 * Aviso, nao falha.
 *
 * A ausencia da interface nao impede o CMS de servir a API — que e o que o
 * `packer` e os scripts consomem. Mas descobrir isso por um 503 no navegador,
 * sem nada no log do servidor, e uma tarde perdida.
 */
if (!temInterface()) {
  console.warn(
    `[cms] sem interface em ${RAIZ_DA_SPA}: a API responde, as telas devolvem 503.\n` +
      '      Construa com `npm run web:build`.',
  );
}

serve({ fetch: app.fetch, port: env.port }, (info) => {
  console.log(`[cms] escutando em http://127.0.0.1:${info.port}`);
});
