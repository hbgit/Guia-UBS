/**
 * Decisao de revisao clinica.
 *
 * A rota e fina de proposito: `requirePermission('approval:decide')` cobre a
 * segregacao por PAPEL (so `clinical_reviewer` tem essa permissao), o gatilho do
 * banco cobre a segregacao por LINHA, e o servico cobre o quorum. Aqui so se
 * traduz o resultado.
 */
import type { Client } from '@libsql/client';
import { Hono } from 'hono';
import { z } from 'zod';

import { requirePermission, type AuthVariables } from '../auth/middleware.js';
import { mensagemDoErro } from '../db/errors.js';
import { TRANSICOES, registrarDecisao } from '../services/approval-workflow.js';

const decisao = z.object({
  releaseId: z.string().min(1),
  decision: z.enum(['approve', 'reject']),
  /** Comentario do revisor. Vai para `approval.comment`, que e append-only. */
  comment: z.string().max(2000).nullish(),
});

export function approvalRoutes(client: Client, salt: string) {
  return new Hono<{ Variables: AuthVariables }>().post(
    '/',
    requirePermission('approval:decide'),
    async (c) => {
      const corpo = decisao.safeParse(await c.req.json().catch(() => null));
      if (!corpo.success) {
        return c.json({ error: 'dados invalidos', detalhes: corpo.error.issues }, 400);
      }

      const ator = c.get('operador');
      let resultado;
      try {
        resultado = await registrarDecisao(client, salt, {
          releaseId: corpo.data.releaseId,
          approverId: ator.id,
          // O papel viaja para a LINHA de `approval`: promover ou rebaixar
          // alguem depois nao pode reescrever quem aprovou o que, sob qual papel.
          role: 'clinical_reviewer',
          decision: corpo.data.decision,
          comment: corpo.data.comment,
        });
      } catch (erro) {
        // O gatilho do banco recusou. Traduzir aqui — e nao deixar virar 500 — e
        // o que transforma "erro interno" em "voce nao pode aprovar a release
        // que voce mesmo criou".
        if (/nao aprova a propria release/.test(mensagemDoErro(erro))) {
          return c.json(
            {
              error:
                'quem cria a release nao aprova a propria release: a revisao precisa ser ' +
                'de outra pessoa (LGPD-RF11)',
            },
            403,
          );
        }
        throw erro;
      }

      switch (resultado.estado) {
        case 'ok':
          return c.json({ ok: true, de: resultado.de, para: resultado.para });
        case 'ausente':
          return c.json({ error: 'release nao encontrada' }, 404);
        case 'sem_quorum':
          return c.json({ ok: true, transicionou: false, faltam: resultado.faltam });
        case 'transicao_invalida':
          return c.json(
            {
              error: 'a release nao esta em revisao',
              atual: resultado.atual,
              permitidas: TRANSICOES.filter((t) => t.de === resultado.atual),
            },
            409,
          );
      }
    },
  );
}
