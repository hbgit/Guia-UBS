/**
 * Ciclo de vida da release e a metade AGREGADA do dual review.
 *
 * ## As tres metades da segregacao
 *
 * A LGPD-RF11 exige que quem edita nao aprove. Isso se decompoe em regras de
 * naturezas diferentes, e cada uma mora onde consegue ser cumprida:
 *
 *   por PAPEL   `editor` nao tem `approval:decide` — matriz do item 17
 *   por LINHA   quem criou a release nao aprova ESTA release — gatilho do banco
 *   por QUORUM  ao menos um `clinical_reviewer` aprovou — aqui
 *
 * A terceira nao e restricao de linha: e uma pergunta sobre o CONJUNTO de
 * aprovacoes. Gatilho so a expressaria com subquery agregada disparada a cada
 * insercao, e a decisao que ela informa — transicionar de estado — nao pertence a
 * uma restricao de integridade.
 *
 * ## A FSM e dado
 *
 * `TRANSICOES` e percorrida pelo teste. Escrita como `if` espalhados, o que o
 * teste cobre e o que alguem lembrou de cobrir — e uma transicao ilegal que passe
 * despercebida aqui significa pack publicado sem aprovacao clinica.
 */
import { randomUUID } from 'node:crypto';

import type { Client } from '@libsql/client';
import { and, eq } from 'drizzle-orm';

import { createDb } from '../db/client.js';
import { approval, packRelease, type RELEASE_STATUSES } from '../db/schema/publishing.js';
import { recordAudit } from './audit.js';

export type ReleaseStatus = (typeof RELEASE_STATUSES)[number];

/** Quem pode mover. `job` e o packer, que nao tem operador. */
export type Ator = 'editor' | 'clinical_reviewer' | 'admin' | 'job';

export interface Transicao {
  de: ReleaseStatus;
  para: ReleaseStatus;
  por: readonly Ator[];
  motivo: string;
}

/**
 * A FSM inteira, como dado.
 *
 * O que NAO esta aqui importa tanto quanto o que esta: nao existe
 * `pending_review -> built`, nem `draft -> approved`. Publicar sem passar por
 * revisao clinica precisa ser impossivel de escrever, nao apenas desaconselhado.
 */
export const TRANSICOES: readonly Transicao[] = [
  {
    de: 'draft',
    para: 'pending_review',
    por: ['editor', 'admin'],
    motivo: 'submete para revisao clinica',
  },
  {
    de: 'pending_review',
    para: 'draft',
    por: ['clinical_reviewer'],
    motivo: 'rejeicao devolve para correcao',
  },
  {
    de: 'pending_review',
    para: 'approved',
    por: ['clinical_reviewer'],
    motivo: 'quorum de revisao clinica alcancado',
  },
  { de: 'approved', para: 'building', por: ['job'], motivo: 'posse por compare-and-set' },
  { de: 'building', para: 'built', por: ['job'], motivo: 'portoes verdes e manifest assinado' },
  {
    de: 'building',
    para: 'approved',
    por: ['admin'],
    motivo: 'recuperacao de job interrompido',
  },
  { de: 'built', para: 'published', por: ['job'], motivo: 'artefatos no storage' },
  { de: 'built', para: 'revoked', por: ['admin'], motivo: 'revogacao antes de publicar' },
  { de: 'published', para: 'revoked', por: ['admin'], motivo: 'revogacao de pack publicado' },
];

export function transicaoPermitida(de: ReleaseStatus, para: ReleaseStatus, por: Ator): boolean {
  return TRANSICOES.some((t) => t.de === de && t.para === para && t.por.includes(por));
}

export type ResultadoTransicao =
  | { estado: 'ok'; de: ReleaseStatus; para: ReleaseStatus }
  | { estado: 'ausente' }
  | { estado: 'transicao_invalida'; atual: ReleaseStatus }
  | { estado: 'sem_quorum'; faltam: string };

/**
 * Move a release exigindo que o estado ATUAL seja o esperado.
 *
 * O `WHERE status = ?` nao e redundante com a leitura anterior: entre ler e
 * escrever, outro processo pode ter movido a release. Sem ele, duas transicoes
 * concorrentes a partir do mesmo estado passariam as duas.
 */
async function moverSeEstiverEm(
  client: Client,
  releaseId: string,
  de: ReleaseStatus,
  para: ReleaseStatus,
  extras: Record<string, unknown> = {},
): Promise<boolean> {
  const db = createDb(client);
  const linhas = await db
    .update(packRelease)
    .set({ status: para, ...extras })
    .where(and(eq(packRelease.id, releaseId), eq(packRelease.status, de)))
    .returning({ id: packRelease.id });
  return linhas.length === 1;
}

async function lerRelease(client: Client, releaseId: string) {
  const db = createDb(client);
  const linhas = await db.select().from(packRelease).where(eq(packRelease.id, releaseId)).limit(1);
  return linhas[0];
}

/**
 * Ha quorum quando existe ao menos uma aprovacao de `clinical_reviewer` e
 * nenhuma rejeicao.
 *
 * O papel considerado e o gravado NA LINHA de `approval`, nao o papel atual da
 * pessoa: promover ou rebaixar alguem depois nao pode reescrever o passado — uma
 * aprovacao dada por quem era revisor continua valendo, e uma dada por quem virou
 * revisor depois nao passa a valer.
 */
export async function temQuorumClinico(
  client: Client,
  releaseId: string,
): Promise<{ ok: boolean; aprovacoes: number; rejeicoes: number }> {
  const db = createDb(client);
  const decisoes = await db.select().from(approval).where(eq(approval.packReleaseId, releaseId));

  const aprovacoes = decisoes.filter(
    (d) => d.role === 'clinical_reviewer' && d.decision === 'approve',
  ).length;
  const rejeicoes = decisoes.filter((d) => d.decision === 'reject').length;
  return { ok: aprovacoes >= 1 && rejeicoes === 0, aprovacoes, rejeicoes };
}

export async function submeterParaRevisao(
  client: Client,
  salt: string,
  releaseId: string,
  ator: { id: string; role: Ator },
): Promise<ResultadoTransicao> {
  const atual = await lerRelease(client, releaseId);
  if (!atual) return { estado: 'ausente' };
  if (!transicaoPermitida(atual.status, 'pending_review', ator.role)) {
    return { estado: 'transicao_invalida', atual: atual.status };
  }

  const moveu = await moverSeEstiverEm(client, releaseId, atual.status, 'pending_review');
  if (!moveu) return { estado: 'transicao_invalida', atual: atual.status };

  await recordAudit(client, salt, {
    actorId: ator.id,
    action: 'release_submit',
    entityType: 'pack_release',
    entityId: releaseId,
    before: { status: atual.status },
    after: { status: 'pending_review' },
  });
  return { estado: 'ok', de: atual.status, para: 'pending_review' };
}

/**
 * Registra a decisao e, se ela fechar o quorum, move a release.
 *
 * A insercao em `approval` acontece ANTES da transicao, de proposito: se a
 * transicao falhar, a decisao clinica ja esta registrada e nao se perde. O
 * inverso deixaria uma release aprovada sem quem a aprovou.
 */
export async function registrarDecisao(
  client: Client,
  salt: string,
  entrada: {
    releaseId: string;
    approverId: string;
    role: Exclude<Ator, 'job'>;
    decision: 'approve' | 'reject';
    comment?: string | null;
  },
): Promise<ResultadoTransicao> {
  const atual = await lerRelease(client, entrada.releaseId);
  if (!atual) return { estado: 'ausente' };

  const destino: ReleaseStatus = entrada.decision === 'approve' ? 'approved' : 'draft';
  if (!transicaoPermitida(atual.status, destino, entrada.role)) {
    return { estado: 'transicao_invalida', atual: atual.status };
  }

  const db = createDb(client);
  const agora = new Date().toISOString();
  // O gatilho `approval_no_self_approval` recusa aqui se o aprovador for quem
  // criou a release. Deixar a excecao subir e deliberado: a rota a traduz, e o
  // BANCO continua sendo quem decide.
  await db.insert(approval).values({
    id: randomUUID(),
    packReleaseId: entrada.releaseId,
    approverId: entrada.approverId,
    role: entrada.role,
    decision: entrada.decision,
    comment: entrada.comment ?? null,
    decidedAt: agora,
  });

  await recordAudit(client, salt, {
    actorId: entrada.approverId,
    action: entrada.decision === 'approve' ? 'release_approve' : 'release_reject',
    entityType: 'pack_release',
    entityId: entrada.releaseId,
    after: { decision: entrada.decision },
  });

  if (entrada.decision === 'reject') {
    await moverSeEstiverEm(client, entrada.releaseId, atual.status, 'draft');
    return { estado: 'ok', de: atual.status, para: 'draft' };
  }

  const quorum = await temQuorumClinico(client, entrada.releaseId);
  if (!quorum.ok) {
    return {
      estado: 'sem_quorum',
      faltam:
        quorum.rejeicoes > 0
          ? 'ha rejeicao registrada; a release volta para rascunho'
          : 'falta aprovacao de um revisor clinico',
    };
  }

  const moveu = await moverSeEstiverEm(client, entrada.releaseId, atual.status, 'approved');
  if (!moveu) return { estado: 'transicao_invalida', atual: atual.status };
  return { estado: 'ok', de: atual.status, para: 'approved' };
}

/**
 * Toma posse de uma release aprovada. Usada pelo job do packer.
 *
 * Compare-and-set: `approved -> building` acontece uma vez so, e o segundo
 * processo recebe `false` e segue adiante. Sem isto, dois jobs construiriam o
 * mesmo pack e publicariam um por cima do outro.
 */
export async function reivindicar(client: Client, releaseId: string): Promise<boolean> {
  return moverSeEstiverEm(client, releaseId, 'approved', 'building', {
    claimedAt: new Date().toISOString(),
  });
}

/** `building -> approved`, para destravar release cujo job morreu. */
export async function devolverParaFila(
  client: Client,
  salt: string,
  releaseId: string,
  atorId: string,
): Promise<ResultadoTransicao> {
  const atual = await lerRelease(client, releaseId);
  if (!atual) return { estado: 'ausente' };
  if (!transicaoPermitida(atual.status, 'approved', 'admin')) {
    return { estado: 'transicao_invalida', atual: atual.status };
  }
  const moveu = await moverSeEstiverEm(client, releaseId, 'building', 'approved', {
    claimedAt: null,
  });
  if (!moveu) return { estado: 'transicao_invalida', atual: atual.status };

  await recordAudit(client, salt, {
    actorId: atorId,
    action: 'release_requeue',
    entityType: 'pack_release',
    entityId: releaseId,
    before: { status: 'building', claimedAt: atual.claimedAt },
    after: { status: 'approved' },
  });
  return { estado: 'ok', de: 'building', para: 'approved' };
}

/** Transicao executada pelo job — sem operador, `actorId` nulo. */
export async function moverPeloJob(
  client: Client,
  salt: string,
  releaseId: string,
  de: ReleaseStatus,
  para: ReleaseStatus,
  extras: Record<string, unknown> = {},
): Promise<boolean> {
  if (!transicaoPermitida(de, para, 'job')) {
    throw new Error(`transicao ${de} -> ${para} nao e permitida ao job`);
  }
  const moveu = await moverSeEstiverEm(client, releaseId, de, para, extras);
  if (!moveu) return false;

  await recordAudit(client, salt, {
    // Nulo de proposito: o job nao tem operador. `audit_entry.actor_id` e
    // nulavel desde o item 17 exatamente para este caso.
    actorId: null,
    action: `release_${para}`,
    entityType: 'pack_release',
    entityId: releaseId,
    before: { status: de },
    after: { status: para },
  });
  return true;
}

export async function revogar(
  client: Client,
  salt: string,
  releaseId: string,
  atorId: string,
): Promise<ResultadoTransicao> {
  const atual = await lerRelease(client, releaseId);
  if (!atual) return { estado: 'ausente' };
  if (!transicaoPermitida(atual.status, 'revoked', 'admin')) {
    return { estado: 'transicao_invalida', atual: atual.status };
  }
  const moveu = await moverSeEstiverEm(client, releaseId, atual.status, 'revoked');
  if (!moveu) return { estado: 'transicao_invalida', atual: atual.status };

  await recordAudit(client, salt, {
    actorId: atorId,
    action: 'release_revoke',
    entityType: 'pack_release',
    entityId: releaseId,
    before: { status: atual.status },
    after: { status: 'revoked' },
  });
  return { estado: 'ok', de: atual.status, para: 'revoked' };
}
