/**
 * Casos golden e a revisao clinica que os ativa (P0-2).
 *
 * Um caso nasce INATIVO. So a revisao de ao menos `MIN_REVISORES` profissionais
 * atestados, do conteudo ATUAL (`reviewed_hash`), o ativa. A revisao e so
 * ACRESCIMO: nao ha PUT nem DELETE aqui, e o gatilho do banco recusa
 * UPDATE/DELETE de `golden_case_review`. Revisao errada se corrige por
 * revogacao auditada (#43), outra linha append-only, e o caso sai da suite por
 * desativacao definitiva. Ser definitiva e a recusa para red flag sao gatilhos
 * do banco; a rota so traduz o erro.
 *
 * A rota nao le `atestados.yaml`: o arquivo e versionado com o codigo e chega ao
 * CMS por implantacao. A coerencia CMS x registro e conferida pelo importador e
 * pelo worker, que e onde ela decide alguma coisa.
 */
import { randomUUID } from 'node:crypto';

import {
  avaliarAtestado,
  avaliarDataRevisao,
  hashConteudoGolden,
  MIN_REVISORES,
  SQL_REVISAO_NAO_REVOGADA,
} from '@guia-ubs/contract';
import type { Client, InStatement } from '@libsql/client';
import { and, eq } from 'drizzle-orm';
import { Hono } from 'hono';
import { z } from 'zod';

import { requirePermission, type AuthVariables } from '../auth/middleware.js';
import { createDb } from '../db/client.js';
import { classificarViolacao, mensagemDoErro } from '../db/errors.js';
import { goldenAttestation, goldenCase, goldenCaseReview } from '../db/schema/publishing.js';
import { comandoDeAuditoria } from '../services/audit.js';

const novoCaso = z.object({
  id: z.string().min(1),
  tokens: z.array(z.string().min(1)).min(1),
  expect: z.string().min(1),
  clinicalSource: z.string().nullish(),
  active: z.number().int().optional(),
});

const novaRevisao = z.object({ atestado: z.unknown().optional(), reviewed_at: z.unknown().optional() });

// Mesmo minimo do CHECK de golden_case_review_revocation.reason.
const comMotivo = z.object({ motivo: z.string().trim().min(10) });

const semAcento = (s: string) =>
  s.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase().replace(/\s+/g, ' ').trim();

/**
 * O motivo vai para a trilha, que e permanente: nome e registro do profissional
 * so moram em `golden_attestation` (spec/lgpd.md). Confere contra TODOS os
 * atestados, nao so o revogado: o motivo pode citar outra pessoa.
 */
export async function motivoComDadoPessoal(client: Client, motivo: string): Promise<boolean> {
  const texto = semAcento(motivo);
  // AT-NNNN e a forma permitida de citar o profissional; nao pode casar como registro.
  const semAt = texto.replace(/\bat-\d+\b/gi, ' ');
  const { rows } = await client.execute('SELECT nome, registro FROM golden_attestation');
  return rows.some((a) => {
    const registro = String(a.registro).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    return texto.includes(semAcento(String(a.nome))) || new RegExp(`\\b${registro}\\b`).test(semAt);
  });
}

/**
 * O batch da desativacao, exportado para o teste montar a corrida com os
 * comandos reais. `active` e `deactivated_at` no MESMO UPDATE: o gatilho de red
 * flag so dispara na transicao de deactivated_at, e a rota nao reimplementa a regra.
 */
export function comandosDeDesativacao(
  salt: string,
  caseId: string,
  atorId: string,
  motivo: string,
  carimbo: string,
): InStatement[] {
  return [
    {
      sql: `UPDATE golden_case SET active = 0, deactivated_at = ?
            WHERE id = ? AND deactivated_at IS NULL`,
      args: [carimbo, caseId],
    },
    comandoDeAuditoria(
      salt,
      {
        actorId: atorId,
        action: 'golden_case_deactivate',
        entityType: 'golden_case',
        entityId: caseId,
        // Sem `before`: o estado anterior so seria lido fora deste lote, e uma
        // ativacao concorrente o deixaria falso numa trilha que nao se corrige.
        after: { active: 0, motivo },
      },
      // `changes()` do UPDATE logo acima: a trilha so entra se ESTE update mudou
      // a linha. Carimbo nao serve: duas requisicoes podem gerar o mesmo ms.
      { sql: 'changes() = 1', args: [] },
    ),
  ];
}

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
    try {
      // Trilha no mesmo batch: caso sem trilha nao fica.
      await client.batch(
        [
          {
            sql: `INSERT INTO golden_case
                    (id, tokens_json, expected_outcome_id, clinical_source, added_by, active)
                  VALUES (?, ?, ?, ?, ?, 0)`,
            args: [dados.id, JSON.stringify(dados.tokens), dados.expect, dados.clinicalSource ?? null, ator.id],
          },
          comandoDeAuditoria(salt, {
            actorId: ator.id,
            action: 'golden_case_create',
            entityType: 'golden_case',
            entityId: dados.id,
            after: { tokens: dados.tokens, expect: dados.expect, active: 0 },
          }),
        ],
        'write',
      );
    } catch (erro) {
      if (classificarViolacao(erro) === 'duplicidade') {
        return c.json({ error: 'ja existe caso com esse id' }, 409);
      }
      throw erro;
    }
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
      // Trilha no mesmo batch: atestado sem trilha nao fica.
      await client.batch(
        [
          {
            sql: `INSERT INTO golden_attestation
                    (id, nome, conselho, uf, categoria, registro, termo_sha256, created_by, created_at)
                  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            args: [
              a.id, a.nome, a.conselho, a.uf, categoria, a.registro, a.termo_sha256, ator.id,
              new Date().toISOString(),
            ],
          },
          comandoDeAuditoria(salt, {
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
          }),
        ],
        'write',
      );
    } catch (erro) {
      if (classificarViolacao(erro) === 'duplicidade') {
        return c.json({ error: 'este termo ja pertence a outro atestado' }, 409);
      }
      throw erro;
    }
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
    if (alvo.deactivatedAt) return c.json({ error: 'caso desativado' }, 409);

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
        {
          error: `este atestado ja tem revisao neste caso; revogue a anterior em POST /api/golden-cases/${caseId}/revisores/${atestadoId}/revogar`,
          revisoes: await revisoesAtuais(),
        },
        409,
      );
    // Mesma definicao do gatilho golden_case_review_one_live: nao revogada, qualquer hash.
    if (await revisaoViva(caseId, atestadoId)) return await conflito();

    const hash = await hashConteudoGolden(
      JSON.parse(alvo.tokensJson) as string[],
      alvo.expectedOutcomeId,
    );
    try {
      // Uma batch so: a revisao e a ativacao nao podem se separar. O UPDATE conta
      // as linhas no proprio banco, entao dois revisores concorrentes nao deixam
      // o caso inativo com quorum fechado. So conta revisao valida: nao revogada
      // e do conteudo atual. A trilha vai no mesmo batch: operacao sem trilha nao fica.
      await client.batch(
        [
          {
            sql: `INSERT INTO golden_case_review
                    (id, case_id, attestation_id, reviewed_at, recorded_by, recorded_at, reviewed_hash)
                  VALUES (?, ?, ?, ?, ?, ?, ?)`,
            args: [randomUUID(), caseId, atestadoId, data, ator.id, new Date().toISOString(), hash],
          },
          {
            sql: `UPDATE golden_case SET active = 1
                  WHERE id = ? AND deactivated_at IS NULL
                    AND (SELECT COUNT(DISTINCT r.attestation_id) FROM golden_case_review r
                          WHERE r.case_id = ? AND r.reviewed_hash = ? AND ${SQL_REVISAO_NAO_REVOGADA}) >= ?`,
            args: [caseId, caseId, hash, MIN_REVISORES],
          },
          // Sem `active`: so e conhecido depois do batch; a resposta HTTP o le.
          comandoDeAuditoria(salt, {
            actorId: ator.id,
            action: 'golden_case_review',
            entityType: 'golden_case',
            entityId: caseId,
            after: { atestado: atestadoId, reviewed_at: data },
          }),
        ],
        'write',
      );
    } catch (erro) {
      if (classificarViolacao(erro) === 'duplicidade') return await conflito();
      // So o gatilho golden_case_review_no_deactivated_case (desativado depois do
      // pre-check); outro CHECK e defeito e relanca.
      if (mensagemDoErro(erro).includes('em caso desativado')) {
        return c.json({ error: 'caso desativado' }, 409);
      }
      throw erro;
    }

    const ativo = (await db.select().from(goldenCase).where(eq(goldenCase.id, caseId)))[0]!.active;
    return c.json({ ok: true, caso: caseId, atestado: atestadoId, active: ativo }, 201);
  });

  // Pelo AT-, que e o que o operador tem no formulario; o UUID da revisao nunca chega a ele.
  app.post('/:id/revisores/:atestado/revogar', requirePermission('approval:decide'), async (c) => {
    const motivo = await motivoValido(c.req.json().catch(() => null));
    if (typeof motivo !== 'string') return c.json(motivo, 422);
    const caseId = c.req.param('id');
    const atestadoId = c.req.param('atestado');

    // Caso desativado tambem: corrigir o registro nao reativa nada.
    const reviewId = await revisaoViva(caseId, atestadoId);
    if (!reviewId) {
      return c.json({ error: 'sem revisao nao revogada deste atestado neste caso' }, 404);
    }
    const ator = c.get('operador');
    try {
      await client.batch(
        [
          {
            sql: `INSERT INTO golden_case_review_revocation (id, review_id, reason, revoked_by, revoked_at)
                  VALUES (?, ?, ?, ?, ?)`,
            args: [randomUUID(), reviewId, motivo, ator.id, new Date().toISOString()],
          },
          comandoDeAuditoria(salt, {
            actorId: ator.id,
            action: 'golden_review_revoke',
            entityType: 'golden_case',
            entityId: caseId,
            after: { atestado: atestadoId, motivo },
          }),
        ],
        'write',
      );
    } catch (erro) {
      // Revogacao concorrente da mesma revisao (review_id UNIQUE): ja nao ha viva.
      if (classificarViolacao(erro) === 'duplicidade') {
        return c.json({ error: 'sem revisao nao revogada deste atestado neste caso' }, 404);
      }
      throw erro;
    }
    // Sem recontagem: o caso segue `active` e o portao o reprova dizendo por que.
    const ativo = (
      await createDb(client).select().from(goldenCase).where(eq(goldenCase.id, caseId))
    )[0]!.active;
    return c.json({ ok: true, caso: caseId, atestado: atestadoId, active: ativo }, 201);
  });

  app.post('/:id/desativar', requirePermission('approval:decide'), async (c) => {
    const motivo = await motivoValido(c.req.json().catch(() => null));
    if (typeof motivo !== 'string') return c.json(motivo, 422);
    const caseId = c.req.param('id');
    const db = createDb(client);
    const alvo = (await db.select().from(goldenCase).where(eq(goldenCase.id, caseId)).limit(1))[0];
    if (!alvo) return c.json({ error: 'caso nao encontrado' }, 404);

    let afetadas: number;
    try {
      const [update] = await client.batch(
        comandosDeDesativacao(salt, caseId, c.get('operador').id, motivo, new Date().toISOString()),
        'write',
      );
      afetadas = update!.rowsAffected;
    } catch (erro) {
      if (classificarViolacao(erro) === 'dominio') {
        return c.json(
          {
            error: 'caso de severidade maxima (red flag) ou de desfecho desconhecido nao se desativa',
            next: 'docs/revisao-golden.md §4',
          },
          422,
        );
      }
      throw erro;
    }
    if (afetadas === 0) return c.json({ error: 'caso ja desativado' }, 409);
    return c.json({ ok: true, caso: caseId, active: 0 }, 200);
  });

  /** O motivo valido, ou o corpo do 422. */
  async function motivoValido(
    json: Promise<unknown>,
  ): Promise<string | { error: string; problemas?: unknown }> {
    const corpo = comMotivo.safeParse(await json);
    if (!corpo.success) {
      return { error: 'motivo invalido: ao menos 10 caracteres', problemas: corpo.error.issues };
    }
    if (await motivoComDadoPessoal(client, corpo.data.motivo)) {
      return { error: 'o motivo nao pode conter nome nem registro de profissional: a trilha e permanente' };
    }
    return corpo.data.motivo;
  }

  /** Id da revisao nao revogada de (caso, atestado), unica pelo gatilho. */
  async function revisaoViva(caseId: string, atestadoId: string): Promise<string | undefined> {
    const { rows } = await client.execute({
      sql: `SELECT r.id FROM golden_case_review r
             WHERE r.case_id = ? AND r.attestation_id = ? AND ${SQL_REVISAO_NAO_REVOGADA}`,
      args: [caseId, atestadoId],
    });
    return rows[0] ? String(rows[0].id) : undefined;
  }

  return app;
}
