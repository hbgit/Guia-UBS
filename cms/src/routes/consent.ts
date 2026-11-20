/**
 * `/api/consentimento` — ler e aceitar o termo de uso vigente (issue #10).
 *
 * E a unica rota protegida que `requireConsent` deixa passar. O cliente ecoa
 * versao e hash do que leu; o servidor confere contra o vigente, e quem diz o
 * que foi aceito e o hash calculado no servidor (`services/legal.ts`).
 */
import type { Client } from '@libsql/client';
import { Hono } from 'hono';
import { z } from 'zod';

import type { AuthVariables } from '../auth/middleware.js';
import { aceitouVigente, documentoVigente, registrarAceite } from '../services/legal.js';

const SEM_TERMO = { error: 'nenhum termo de uso publicado' } as const;

const aceite = z.object({
  version: z.string().min(1),
  hash: z.string().regex(/^[0-9a-f]{64}$/),
});

export function consentRoutes(client: Client, salt: string) {
  return new Hono<{ Variables: AuthVariables }>()
    .get('/', async (c) => {
      const documento = await documentoVigente(client);
      if (!documento) return c.json(SEM_TERMO, 404);
      return c.json({ ...documento, aceito: await aceitouVigente(client, c.get('operador').id) });
    })

    .post('/', async (c) => {
      const corpo = aceite.safeParse(await c.req.json().catch(() => null));
      if (!corpo.success) return c.json({ error: 'dados invalidos' }, 400);

      const r = await registrarAceite(client, salt, c.get('operador').id, corpo.data);
      if (r.ok) return c.json({ aceito: true, version: r.documento.version, hash: r.documento.hash });
      if (r.motivo === 'sem_documento') return c.json(SEM_TERMO, 404);
      // `vigente`, nunca `atual`: na SPA `CorpoDeErro.atual` e o estado da FSM
      // (string), e um objeto ali viraria um `conflito_estado` torto.
      return c.json({ error: 'o termo mudou', vigente: r.documento }, 409);
    });
}
