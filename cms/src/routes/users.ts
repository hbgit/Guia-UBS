/**
 * Gestao de operadores — exclusiva do papel `admin` (lgpd.md LGPD-RF11).
 *
 * Nao ha rota de auto-cadastro nem de auto-promocao: um operador nunca muda o
 * proprio papel. Sem isso, RBAC de tres papeis seria decorativo — bastaria um
 * editor pedir `role: 'admin'` para si.
 */
import type { Client } from '@libsql/client';
import { Hono } from 'hono';
import { z } from 'zod';

import type { AuthVariables } from '../auth/middleware.js';
import { requirePermission } from '../auth/middleware.js';
import { ADMIN_ROLES } from '../db/schema/auth.js';
import { createDb } from '../db/client.js';
import { MIN_PASSWORD_LENGTH } from '../auth/config.js';
import { createOperator, setOperatorDisabled, setOperatorRole } from '../services/operators.js';

const novoOperador = z.object({
  email: z.email(),
  name: z.string().min(1).max(120),
  role: z.enum(ADMIN_ROLES),
  password: z.string().min(MIN_PASSWORD_LENGTH).max(128),
});

const alteracao = z.object({
  role: z.enum(ADMIN_ROLES).optional(),
  disabled: z.boolean().optional(),
});

export function userRoutes(client: Client, salt: string) {
  return (
    new Hono<{ Variables: AuthVariables }>()
      .use('*', requirePermission('user:manage'))

      /**
       * Lista sem credencial nenhuma. `password`, `two_factor.secret` e
       * `backup_codes` nao saem daqui nem para um admin: gerir pessoas nao e
       * motivo para ver a credencial delas.
       */
      .get('/', async (c) => {
        const db = createDb(client);
        const linhas = await db.query.adminUser.findMany({
          columns: {
            id: true,
            email: true,
            name: true,
            role: true,
            disabledAt: true,
            twoFactorEnabled: true,
            createdAt: true,
          },
        });
        return c.json({ operators: linhas });
      })

      .post('/', async (c) => {
        const corpo = novoOperador.safeParse(await c.req.json().catch(() => null));
        // A mensagem de erro NAO ecoa o corpo recebido (LGPD-RT01): ecoar
        // devolveria a senha na resposta e, de quebra, no log de quem estiver
        // no meio.
        if (!corpo.success) return c.json({ error: 'dados invalidos' }, 400);

        const criado = await createOperator(client, salt, corpo.data, c.get('operador').id);
        return c.json(criado, 201);
      })

      .patch('/:id', async (c) => {
        const alvo = c.req.param('id');
        const ator = c.get('operador');
        if (alvo === ator.id) {
          // Um admin que se rebaixa por engano tranca a gestao de pessoas para
          // fora; um que se desliga faz o mesmo. E, sobretudo: auto-promocao
          // esvaziaria a segregacao de papeis.
          return c.json({ error: 'um operador nao altera a propria conta' }, 403);
        }

        const corpo = alteracao.safeParse(await c.req.json().catch(() => null));
        if (!corpo.success) return c.json({ error: 'dados invalidos' }, 400);

        if (corpo.data.role) await setOperatorRole(client, salt, alvo, corpo.data.role, ator.id);
        if (corpo.data.disabled !== undefined) {
          await setOperatorDisabled(client, salt, alvo, corpo.data.disabled, ator.id);
        }
        return c.json({ ok: true });
      })
  );
}
