/**
 * Ciclo de vida da release, pelo HTTP.
 *
 * As rotas nao decidem nada: `services/approval-workflow.ts` e quem conhece a
 * FSM, e este arquivo traduz o resultado em codigo de status. Duplicar a regra
 * aqui faria a FSM ter duas descricoes, e a que ficasse para tras deixaria passar
 * uma transicao que a outra proibe.
 */
import type { Client } from '@libsql/client';
import { desc, eq } from 'drizzle-orm';
import { Hono } from 'hono';
import { z } from 'zod';

import { requirePermission, type AuthVariables } from '../auth/middleware.js';
import { isAdminRole } from '../auth/permissions.js';
import { createDb } from '../db/client.js';
import { classificarViolacao } from '../db/errors.js';
import { packRelease } from '../db/schema/publishing.js';
import {
  TRANSICOES,
  devolverParaFila,
  revogar,
  submeterParaRevisao,
  type Ator,
  type ResultadoTransicao,
} from '../services/approval-workflow.js';
import { recordAudit } from '../services/audit.js';

const novaRelease = z.object({
  id: z.string().min(1),
  municipalityId: z.string().min(1),
  packVersion: z.number().int().positive(),
  schemaVersion: z.string().min(1),
});

/** Traduz o resultado da FSM em resposta. Um lugar so, para as rotas nao divergirem. */
function responder(
  c: { json: (corpo: unknown, status: 200 | 404 | 409) => Response },
  resultado: ResultadoTransicao,
): Response {
  switch (resultado.estado) {
    case 'ok':
      return c.json({ ok: true, de: resultado.de, para: resultado.para }, 200);
    case 'ausente':
      return c.json({ error: 'release nao encontrada' }, 404);
    case 'sem_quorum':
      // 200: a decisao FOI registrada e conta para o quorum; o que nao aconteceu
      // foi a transicao. Devolver erro faria o revisor achar que o voto se perdeu.
      return c.json({ ok: true, transicionou: false, faltam: resultado.faltam }, 200);
    case 'transicao_invalida':
      return c.json(
        {
          error: 'transicao nao permitida a partir do estado atual',
          atual: resultado.atual,
          permitidas: TRANSICOES.filter((t) => t.de === resultado.atual).map((t) => ({
            para: t.para,
            por: t.por,
            motivo: t.motivo,
          })),
        },
        409,
      );
  }
}

/** O papel do operador, no vocabulario da FSM. */
function atorDaSessao(role: string): Ator {
  return isAdminRole(role) ? role : 'editor';
}

export function releaseRoutes(client: Client, salt: string) {
  const app = new Hono<{ Variables: AuthVariables }>();

  app.get('/', requirePermission('content:read'), async (c) => {
    const db = createDb(client);
    return c.json({
      items: await db.select().from(packRelease).orderBy(desc(packRelease.createdAt)),
    });
  });

  app.get('/:id', requirePermission('content:read'), async (c) => {
    const db = createDb(client);
    const linhas = await db
      .select()
      .from(packRelease)
      .where(eq(packRelease.id, c.req.param('id')))
      .limit(1);
    if (linhas.length === 0) return c.json({ error: 'release nao encontrada' }, 404);

    const atual = linhas[0]!.status;
    return c.json({
      release: linhas[0],
      // A FSM viaja na resposta: o cliente monta os botoes do que e possivel
      // agora, em vez de manter uma segunda copia das regras de transicao.
      transicoes: TRANSICOES.filter((t) => t.de === atual),
    });
  });

  app.post('/', requirePermission('content:write'), async (c) => {
    const corpo = novaRelease.safeParse(await c.req.json().catch(() => null));
    if (!corpo.success) {
      return c.json({ error: 'dados invalidos', detalhes: corpo.error.issues }, 400);
    }

    const ator = c.get('operador');
    const db = createDb(client);
    try {
      await db.insert(packRelease).values({
        ...corpo.data,
        status: 'draft',
        createdBy: ator.id,
        createdAt: new Date().toISOString(),
      });
    } catch (erro) {
      const classe = classificarViolacao(erro);
      if (classe === 'duplicidade') {
        // `UNIQUE(municipality_id, pack_version)` e o anti-downgrade da INV-7
        // ancorado no banco: reemitir um numero faria metade da frota parar de
        // atualizar sem erro nenhum.
        return c.json({ error: 'ja existe uma release com essa versao para este municipio' }, 409);
      }
      if (classe !== null) return c.json({ error: 'referencia invalida' }, 409);
      throw erro;
    }

    await recordAudit(client, salt, {
      actorId: ator.id,
      action: 'release_create',
      entityType: 'pack_release',
      entityId: corpo.data.id,
      after: corpo.data,
    });
    return c.json({ ok: true, id: corpo.data.id, status: 'draft' }, 201);
  });

  app.post('/:id/submeter', requirePermission('content:write'), async (c) => {
    const ator = c.get('operador');
    return responder(
      c,
      await submeterParaRevisao(client, salt, c.req.param('id'), {
        id: ator.id,
        role: atorDaSessao(ator.role),
      }),
    );
  });

  /**
   * Destrava release cujo job morreu no meio da construcao.
   *
   * Restrita a admin e auditada. Sem ela, um job interrompido deixaria a release
   * em `building` para sempre, e a unica saida seria SQL na mao — que e
   * exatamente o caminho que a trilha nao registra.
   */
  app.post('/:id/reenfileirar', requirePermission('release:publish'), async (c) =>
    responder(c, await devolverParaFila(client, salt, c.req.param('id'), c.get('operador').id)),
  );

  app.post('/:id/revogar', requirePermission('release:publish'), async (c) =>
    responder(c, await revogar(client, salt, c.req.param('id'), c.get('operador').id)),
  );

  return app;
}
