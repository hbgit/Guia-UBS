/**
 * Monta a fabrica de CRUD sobre o registro de entidades.
 *
 * Este arquivo e curto de proposito: ele nao decide nada. Toda decisao sobre uma
 * entidade — chave, escopo, traducao, se pode ser apagada — mora em
 * `content/registry.ts`, e e la que o teste vai buscar o que exigir.
 */
import type { Client } from '@libsql/client';
import { Hono } from 'hono';

import type { AuthVariables } from '../auth/middleware.js';
import { crudRoutes } from '../content/crud.js';
import { CONTENT_ENTITIES } from '../content/registry.js';

export function contentRoutes(client: Client, salt: string) {
  const app = new Hono<{ Variables: AuthVariables }>();
  for (const entidade of CONTENT_ENTITIES) {
    app.route(`/${entidade.nome}`, crudRoutes(entidade, client, salt));
  }
  return app;
}
