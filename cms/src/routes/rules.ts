/**
 * Editor de regras em forma normal disjuntiva.
 *
 * Uma regra e `routing_rule` mais N `routing_rule_term` — E dentro do
 * `group_no`, OU entre grupos. As duas tabelas sao gravadas numa TRANSACAO so:
 * regra sem termos e regra que nunca dispara, e o packer so descobriria na
 * publicacao, com a regra ja aprovada.
 *
 * Nao usa a fabrica de `content/crud.ts` de proposito: uma regra nao e uma linha
 * editavel, e um par regra+termos com validacao clinica e simulacao antes de
 * gravar. Forcar as duas coisas na mesma fabrica tornaria a fabrica um lugar
 * cheio de excecoes.
 */
import type { Client } from '@libsql/client';
import { and, eq } from 'drizzle-orm';
import { Hono } from 'hono';
import { z } from 'zod';

import type { AuthVariables } from '../auth/middleware.js';
import { requirePermission } from '../auth/middleware.js';
import { createDb } from '../db/client.js';
import { classificarViolacao } from '../db/errors.js';
import { routingRule, routingRuleTerm } from '../db/schema/content.js';
import { recordAudit } from '../services/audit.js';
import { simularRegra } from '../services/rule-simulation.js';
import { validarRegra, type RegraProposta } from '../services/rule-validation.js';

const termo = z.object({
  groupNo: z.number().int().min(0),
  tokenId: z.string().min(1),
  negated: z.boolean().default(false),
});

const regra = z.object({
  id: z.string().min(1),
  priority: z.number().int().min(0),
  outcomeId: z.string().min(1),
  rationale: z.string().nullish(),
  clinicalSource: z.string().nullish(),
  terms: z.array(termo),
});

async function carregarRegra(client: Client, id: string) {
  const db = createDb(client);
  const linhas = await db.select().from(routingRule).where(eq(routingRule.id, id)).limit(1);
  if (linhas.length === 0) return null;
  const termos = await db
    .select()
    .from(routingRuleTerm)
    .where(eq(routingRuleTerm.ruleId, id));
  return { regra: linhas[0]!, termos };
}

export function ruleRoutes(client: Client, salt: string) {
  const app = new Hono<{ Variables: AuthVariables }>();

  app.get('/', requirePermission('content:read'), async (c) => {
    const db = createDb(client);
    return c.json({ items: await db.select().from(routingRule) });
  });

  app.get('/:id', requirePermission('content:read'), async (c) => {
    const encontrada = await carregarRegra(client, c.req.param('id'));
    if (!encontrada) return c.json({ error: 'nao encontrada' }, 404);
    c.header('ETag', `"${String(encontrada.regra.version)}"`);
    return c.json(encontrada);
  });

  /**
   * Simula sem gravar NADA.
   *
   * Deliberadamente aberta a quem le conteudo, e nao so a quem escreve: o
   * revisor clinico precisa poder perguntar "o que esta regra faria?" sem ter
   * permissao de escrever — que e exatamente a segregacao da LGPD-RF11.
   */
  app.post('/simular', requirePermission('content:read'), async (c) => {
    const corpo = regra.safeParse(await c.req.json().catch(() => null));
    if (!corpo.success) {
      return c.json({ error: 'dados invalidos', detalhes: corpo.error.issues }, 400);
    }
    const proposta = corpo.data as RegraProposta;
    const problemas = await validarRegra(client, proposta);

    // Sem o desfecho, a simulacao nao tem o que comparar: `desfechoPadrao()`
    // deriva o padrao dos desfechos cadastrados e lanca quando nao ha nenhum.
    // Deixar subir virava 500 — "erro interno" para quem so precisava saber que
    // o desfecho nao existe. Descoberto seguindo o manual num CMS recem-criado,
    // que e exatamente o estado em que alguem simula a primeira regra.
    const semDesfecho = problemas.some((p) => p.codigo === 'desfecho_inexistente');
    return c.json({
      problemas,
      simulacao: semDesfecho ? null : await simularRegra(client, proposta),
    });
  });

  app.post('/', requirePermission('content:write'), async (c) => {
    const corpo = regra.safeParse(await c.req.json().catch(() => null));
    if (!corpo.success) {
      return c.json({ error: 'dados invalidos', detalhes: corpo.error.issues }, 400);
    }
    const proposta = corpo.data as RegraProposta;

    const problemas = await validarRegra(client, proposta);
    if (problemas.length > 0) return c.json({ error: 'regra invalida', problemas }, 422);

    const ator = c.get('operador');
    const agora = new Date().toISOString();
    const db = createDb(client);

    // Regra e termos numa transacao: gravar a regra e falhar nos termos deixaria
    // uma regra que nunca dispara, indistinguivel de uma regra desligada.
    await db.transaction(async (tx) => {
      await tx.insert(routingRule).values({
        id: proposta.id,
        priority: proposta.priority,
        outcomeId: proposta.outcomeId,
        rationale: proposta.rationale ?? null,
        clinicalSource: proposta.clinicalSource ?? null,
        status: 'draft',
        version: 1,
        updatedBy: ator.id,
        updatedAt: agora,
      });
      for (const t of proposta.terms) {
        await tx.insert(routingRuleTerm).values({
          ruleId: proposta.id,
          groupNo: t.groupNo,
          tokenId: t.tokenId,
          negated: t.negated ? 1 : 0,
          version: 1,
          updatedBy: ator.id,
          updatedAt: agora,
        });
      }
    });

    await recordAudit(client, salt, {
      actorId: ator.id,
      action: 'rule_create',
      entityType: 'routing_rule',
      entityId: proposta.id,
      after: proposta,
    });
    c.header('ETag', '"1"');
    return c.json({ ok: true, id: proposta.id, versao: 1 }, 201);
  });

  app.put('/:id', requirePermission('content:write'), async (c) => {
    const id = c.req.param('id');
    const esperada = Number((c.req.header('if-match') ?? '').replace(/^W\/|"/g, ''));
    if (!Number.isInteger(esperada) || esperada < 1) {
      return c.json({ error: 'informe a versao lida no cabecalho If-Match' }, 428);
    }

    const atual = await carregarRegra(client, id);
    if (!atual) return c.json({ error: 'nao encontrada' }, 404);

    // Regra aprovada nao e editada in-place — o gatilho do item 16 recusaria de
    // qualquer forma, mas responder aqui diz O QUE FAZER em vez de devolver um
    // erro de banco.
    if (atual.regra.status === 'approved') {
      return c.json(
        {
          error: 'regra aprovada nao e editada; crie uma revisao',
          next: `/api/rules/${id}/revisao`,
        },
        409,
      );
    }
    if (Number(atual.regra.version) !== esperada) {
      return c.json(
        { error: 'a regra mudou desde a leitura', versaoAtual: Number(atual.regra.version) },
        409,
      );
    }

    const corpo = regra.safeParse(await c.req.json().catch(() => null));
    if (!corpo.success) {
      return c.json({ error: 'dados invalidos', detalhes: corpo.error.issues }, 400);
    }
    const proposta = { ...corpo.data, id } as RegraProposta;

    const problemas = await validarRegra(client, proposta);
    if (problemas.length > 0) return c.json({ error: 'regra invalida', problemas }, 422);

    const ator = c.get('operador');
    const agora = new Date().toISOString();
    const db = createDb(client);

    await db.transaction(async (tx) => {
      await tx
        .update(routingRule)
        .set({
          priority: proposta.priority,
          outcomeId: proposta.outcomeId,
          rationale: proposta.rationale ?? null,
          clinicalSource: proposta.clinicalSource ?? null,
          version: esperada + 1,
          updatedBy: ator.id,
          updatedAt: agora,
        })
        .where(and(eq(routingRule.id, id), eq(routingRule.version, esperada)));

      // Os termos sao substituidos em bloco: editar termo a termo obrigaria o
      // cliente a versionar cada linha da tabela de juncao, e o que o revisor
      // edita e a REGRA, nao um termo solto.
      await tx.delete(routingRuleTerm).where(eq(routingRuleTerm.ruleId, id));
      for (const t of proposta.terms) {
        await tx.insert(routingRuleTerm).values({
          ruleId: id,
          groupNo: t.groupNo,
          tokenId: t.tokenId,
          negated: t.negated ? 1 : 0,
          version: 1,
          updatedBy: ator.id,
          updatedAt: agora,
        });
      }
    });

    await recordAudit(client, salt, {
      actorId: ator.id,
      action: 'rule_update',
      entityType: 'routing_rule',
      entityId: id,
      before: { regra: atual.regra, termos: atual.termos },
      after: proposta,
    });
    c.header('ETag', `"${esperada + 1}"`);
    return c.json({ ok: true, versao: esperada + 1 });
  });

  /**
   * Clona uma regra aprovada como rascunho novo.
   *
   * E o caminho que `arquitetura.md 4.3-B` ja descrevia em prosa: regra aprovada
   * gera linha nova em vez de ser alterada. A original fica intacta — o pack que
   * ja foi publicado com ela continua explicavel.
   */
  app.post('/:id/revisao', requirePermission('content:write'), async (c) => {
    const origem = c.req.param('id');
    const atual = await carregarRegra(client, origem);
    if (!atual) return c.json({ error: 'nao encontrada' }, 404);

    const corpo = z
      .object({ novoId: z.string().min(1) })
      .safeParse(await c.req.json().catch(() => null));
    if (!corpo.success) return c.json({ error: 'informe novoId' }, 400);
    const novoId = corpo.data.novoId;

    const ator = c.get('operador');
    const agora = new Date().toISOString();
    const db = createDb(client);

    try {
      await db.transaction(async (tx) => {
        await tx.insert(routingRule).values({
          id: novoId,
          priority: Number(atual.regra.priority),
          outcomeId: String(atual.regra.outcomeId),
          rationale: atual.regra.rationale ?? null,
          clinicalSource: atual.regra.clinicalSource ?? null,
          status: 'draft',
          version: 1,
          updatedBy: ator.id,
          updatedAt: agora,
        });
        for (const t of atual.termos) {
          await tx.insert(routingRuleTerm).values({
            ruleId: novoId,
            groupNo: Number(t.groupNo),
            tokenId: String(t.tokenId),
            negated: Number(t.negated),
            version: 1,
            updatedBy: ator.id,
            updatedAt: agora,
          });
        }
      });
    } catch (erro) {
      // `classificarViolacao` le a cadeia de `cause`: o Drizzle esconde a
      // mensagem do driver, e casar so com `error.message` faria isto virar 500.
      if (classificarViolacao(erro) === 'duplicidade') {
        return c.json({ error: `ja existe uma regra com o id "${novoId}"` }, 409);
      }
      throw erro;
    }

    await recordAudit(client, salt, {
      actorId: ator.id,
      action: 'rule_revise',
      entityType: 'routing_rule',
      entityId: novoId,
      before: { origem },
      after: { id: novoId, status: 'draft' },
    });
    return c.json({ ok: true, id: novoId, origem }, 201);
  });

  return app;
}
