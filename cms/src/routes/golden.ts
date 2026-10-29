/**
 * Casos golden e a revisao clinica que os ativa (P0-2).
 *
 * Um caso nasce INATIVO. So a revisao de ao menos `MIN_REVISORES` profissionais
 * atestados o ativa, e a revisao e so ACRESCIMO: nao ha PUT nem DELETE aqui, e o
 * gatilho do banco recusa UPDATE/DELETE de `golden_case_review`. Registrar
 * revisao errada nao se corrige por rota — fica para a issue de revogacao
 * auditada (D4).
 *
 * A rota nao le `atestados.yaml`: o arquivo e versionado com o codigo e chega ao
 * CMS por implantacao. A coerencia CMS x registro e conferida pelo importador e
 * pelo worker, que e onde ela decide alguma coisa.
 */
import { randomUUID } from 'node:crypto';

import { avaliarAtestado, avaliarDataRevisao, MIN_REVISORES } from '@guia-ubs/contract';
import type { Client } from '@libsql/client';
import { and, eq } from 'drizzle-orm';
import { Hono } from 'hono';
import { z } from 'zod';

import { requirePermission, type AuthVariables } from '../auth/middleware.js';
import { createDb } from '../db/client.js';
import { classificarViolacao } from '../db/errors.js';
import { goldenAttestation, goldenCase, goldenCaseReview } from '../db/schema/publishing.js';
import { recordAudit } from '../services/audit.js';

const novoCaso = z.object({
  id: z.string().min(1),
  tokens: z.array(z.string().min(1)).min(1),
  expect: z.string().min(1),
  clinicalSource: z.string().nullish(),
  active: z.number().int().optional(),
});

const novaRevisao = z.object({ atestado: z.unknown().optional(), reviewed_at: z.unknown().optional() });

export function goldenRoutes(client: Client, salt: string) {
  const app = new Hono<{ Variables: AuthVariables }>();

  app.post('/', requirePermission('content:write'), async (c) => {
    const corpo = novoCaso.safeParse(await c.req.json().catch(() => null));
    if (!corpo.success) {
      return c.json({ error: 'dados invalidos', detalhes: corpo.error.issues }, 400);
    }
    const dados = corpo.data;
    if (dados.active === 1) {
      return c.json(
        {
          error: 'caso ativo exige revisao clinica registrada',
          next: `POST /api/golden-cases/${dados.id}/revisores`,
        },
        422,
      );
    }

    const ator = c.get('operador');
    const db = createDb(client);
    try {
      await db.insert(goldenCase).values({
        id: dados.id,
        tokensJson: JSON.stringify(dados.tokens),
        expectedOutcomeId: dados.expect,
        clinicalSource: dados.clinicalSource ?? null,
        addedBy: ator.id,
        active: 0,
      });
    } catch (erro) {
      if (classificarViolacao(erro) === 'duplicidade') {
        return c.json({ error: 'ja existe caso com esse id' }, 409);
      }
      throw erro;
    }
    await recordAudit(client, salt, {
      actorId: ator.id,
      action: 'golden_case_create',
      entityType: 'golden_case',
      entityId: dados.id,
      after: { tokens: dados.tokens, expect: dados.expect, active: 0 },
    });
    return c.json({ ok: true, id: dados.id, active: 0 }, 201);
  });

  app.post('/atestados', requirePermission('approval:decide'), async (c) => {
    const avaliado = avaliarAtestado(await c.req.json().catch(() => null));
    if (!avaliado.ok) {
      return c.json({ error: 'atestado invalido', problemas: avaliado.problemas }, 422);
    }
    const a = avaliado.atestado;
    const categoria = a.conselho === 'COREN' ? a.categoria : null;
    const db = createDb(client);

    const mesmoId = (
      await db.select().from(goldenAttestation).where(eq(goldenAttestation.id, a.id)).limit(1)
    )[0];
    if (mesmoId) {
      // Nunca atualiza: o atestado de uma pessoa nao e reescrito por outra chamada.
      const identico =
        mesmoId.nome === a.nome &&
        mesmoId.conselho === a.conselho &&
        mesmoId.uf === a.uf &&
        mesmoId.categoria === categoria &&
        mesmoId.registro === a.registro &&
        mesmoId.termoSha256 === a.termo_sha256;
      return c.json(
        {
          error: identico ? 'atestado ja registrado' : 'este ID ja pertence a outro atestado',
        },
        409,
      );
    }

    const mesmaPessoa = (
      await db
        .select({ id: goldenAttestation.id })
        .from(goldenAttestation)
        .where(
          and(
            eq(goldenAttestation.conselho, a.conselho),
            eq(goldenAttestation.uf, a.uf),
            eq(goldenAttestation.registro, a.registro),
          ),
        )
        .limit(1)
    )[0];
    if (mesmaPessoa) {
      return c.json(
        {
          error: 'este profissional ja esta registrado sob outro ID',
          existente: mesmaPessoa.id,
        },
        409,
      );
    }

    const ator = c.get('operador');
    try {
      await db.insert(goldenAttestation).values({
        id: a.id,
        nome: a.nome,
        conselho: a.conselho,
        uf: a.uf,
        categoria,
        registro: a.registro,
        termoSha256: a.termo_sha256,
        createdBy: ator.id,
        createdAt: new Date().toISOString(),
      });
    } catch (erro) {
      if (classificarViolacao(erro) === 'duplicidade') {
        return c.json({ error: 'este termo ja pertence a outro atestado' }, 409);
      }
      throw erro;
    }
    await recordAudit(client, salt, {
      actorId: ator.id,
      action: 'golden_attestation_create',
      entityType: 'golden_attestation',
      entityId: a.id,
      // Sem nome e registro: `golden_attestation` e a UNICA morada deles
      // (spec/lgpd.md). A trilha e append-only e permanente; uma copia aqui nao
      // sairia com o expurgo do atestado. O `termo_sha256` liga a linha ao termo.
      after: {
        id: a.id,
        conselho: a.conselho,
        uf: a.uf,
        categoria,
        termo_sha256: a.termo_sha256,
      },
    });
    return c.json({ ok: true, id: a.id }, 201);
  });

  app.post('/:id/revisores', requirePermission('approval:decide'), async (c) => {
    const corpo = novaRevisao.safeParse(await c.req.json().catch(() => null));
    if (!corpo.success) {
      return c.json({ error: 'dados invalidos', detalhes: corpo.error.issues }, 400);
    }
    const caseId = c.req.param('id');
    const db = createDb(client);

    const alvo = (await db.select().from(goldenCase).where(eq(goldenCase.id, caseId)).limit(1))[0];
    if (!alvo) return c.json({ error: 'caso nao encontrado' }, 404);

    const ator = c.get('operador');
    // Promocao: quem criou o caso e depois virou revisor nao revisa o proprio
    // caso. A matriz de papeis nao ve isso; so a regra por LINHA.
    if (alvo.addedBy === ator.id) {
      return c.json(
        { error: 'quem cadastra o caso nao o revisa: a revisao precisa ser de outra pessoa' },
        403,
      );
    }

    const { atestado, reviewed_at: reviewedAt } = corpo.data;
    const problemas = avaliarDataRevisao(reviewedAt, new Date()).map((p) => `reviewed_at: ${p}`);
    if (typeof atestado !== 'string' || atestado === '') {
      problemas.push('atestado: esperado o ID do atestado (AT-0000)');
    }
    if (problemas.length > 0) return c.json({ error: 'revisao invalida', problemas }, 422);
    const atestadoId = atestado as string;
    const data = reviewedAt as string;

    const registrado = (
      await db
        .select({ id: goldenAttestation.id })
        .from(goldenAttestation)
        .where(eq(goldenAttestation.id, atestadoId))
        .limit(1)
    )[0];
    if (!registrado) {
      return c.json(
        { error: 'atestado nao registrado neste CMS', next: 'POST /api/golden-cases/atestados' },
        422,
      );
    }

    const revisoesAtuais = () =>
      db.select().from(goldenCaseReview).where(eq(goldenCaseReview.caseId, caseId));
    const conflito = async () =>
      c.json(
        { error: 'este atestado ja revisou o caso', revisoes: await revisoesAtuais() },
        409,
      );
    if ((await revisoesAtuais()).some((r) => r.attestationId === atestadoId)) return await conflito();

    try {
      // Uma batch so: a revisao e a ativacao nao podem se separar. O UPDATE conta
      // as linhas no proprio banco, entao dois revisores concorrentes nao deixam
      // o caso inativo com quorum fechado.
      await client.batch(
        [
          {
            sql: `INSERT INTO golden_case_review
                    (id, case_id, attestation_id, reviewed_at, recorded_by, recorded_at)
                  VALUES (?, ?, ?, ?, ?, ?)`,
            args: [randomUUID(), caseId, atestadoId, data, ator.id, new Date().toISOString()],
          },
          {
            sql: `UPDATE golden_case SET active = 1
                  WHERE id = ?
                    AND (SELECT COUNT(*) FROM golden_case_review WHERE case_id = ?) >= ?`,
            args: [caseId, caseId, MIN_REVISORES],
          },
        ],
        'write',
      );
    } catch (erro) {
      if (classificarViolacao(erro) === 'duplicidade') return await conflito();
      throw erro;
    }

    const ativo = (await db.select().from(goldenCase).where(eq(goldenCase.id, caseId)))[0]!.active;
    await recordAudit(client, salt, {
      actorId: ator.id,
      action: 'golden_case_review',
      entityType: 'golden_case',
      entityId: caseId,
      after: { atestado: atestadoId, reviewed_at: data, active: ativo },
    });
    return c.json({ ok: true, caso: caseId, atestado: atestadoId, active: ativo }, 201);
  });

  return app;
}
