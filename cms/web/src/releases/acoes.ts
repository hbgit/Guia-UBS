/**
 * O que fazer para cada transicao que o servidor oferecer.
 *
 * ## A SPA nao conhece a FSM
 *
 * `GET /api/releases/<id>` devolve `transicoes` — as transicoes possiveis a
 * partir do estado atual —, e e dali que os botoes saem. A `operacao.md`
 * §4.4 e explicita sobre isso: "e dali que uma interface monta os botoes, em vez
 * de manter uma segunda copia das regras".
 *
 * Este arquivo NAO decide o que e possivel. Ele traduz `(de, para)` na chamada
 * HTTP correspondente — que e informacao de transporte, e nao regra de negocio.
 * A diferenca importa: uma transicao acrescentada a `TRANSICOES` sem entrada aqui
 * reprova em `cms/test/web-releases-conformance.test.ts`, e uma entrada aqui sem
 * transicao real reprova tambem. Nos dois sentidos, como o resto do projeto.
 *
 * ## Sem DOM
 *
 * Importado por um teste `node:test` do workspace do servidor, que roda sem lib
 * de DOM. Nada de React aqui.
 */
import type { ReleaseStatus } from '@guia-ubs/cms/src/services/approval-workflow.js';

export interface Acao {
  de: ReleaseStatus;
  para: ReleaseStatus;
  /** Texto do botao. O `motivo` da transicao vira a explicacao ao lado. */
  rotulo: string;
  caminho: (id: string) => string;
  /**
   * Corpo do POST. Ausente = sem corpo.
   *
   * As aprovacoes viajam por `/api/approvals`, e nao por uma rota da release: e
   * la que moram o quorum e o gatilho anti-auto-aprovacao.
   */
  corpo?: (id: string, comentario: string) => unknown;
  /**
   * Pede comentario antes de enviar?
   *
   * So as decisoes de revisao. Comentario obrigatorio em "revogar" atrasaria a
   * unica acao que existe para ser rapida.
   */
  pedeComentario: boolean;
}

export const ACOES: readonly Acao[] = [
  {
    de: 'draft',
    para: 'pending_review',
    rotulo: 'Submeter para revisao',
    caminho: (id) => `/api/releases/${id}/submeter`,
    pedeComentario: false,
  },
  {
    de: 'pending_review',
    para: 'approved',
    rotulo: 'Aprovar',
    caminho: () => '/api/approvals',
    corpo: (id, comentario) => ({ releaseId: id, decision: 'approve', comment: comentario }),
    pedeComentario: true,
  },
  {
    de: 'pending_review',
    para: 'draft',
    rotulo: 'Rejeitar',
    caminho: () => '/api/approvals',
    corpo: (id, comentario) => ({ releaseId: id, decision: 'reject', comment: comentario }),
    pedeComentario: true,
  },
  {
    de: 'building',
    para: 'approved',
    rotulo: 'Reenfileirar',
    caminho: (id) => `/api/releases/${id}/reenfileirar`,
    pedeComentario: false,
  },
  {
    de: 'built',
    para: 'revoked',
    rotulo: 'Revogar',
    caminho: (id) => `/api/releases/${id}/revogar`,
    pedeComentario: false,
  },
  {
    de: 'published',
    para: 'revoked',
    rotulo: 'Revogar',
    caminho: (id) => `/api/releases/${id}/revogar`,
    pedeComentario: false,
  },
];

export function acaoDe(de: ReleaseStatus, para: ReleaseStatus): Acao | undefined {
  return ACOES.find((a) => a.de === de && a.para === para);
}

/**
 * Rotulos dos estados, em portugues.
 *
 * `Record<ReleaseStatus, string>` de proposito: um estado novo em
 * `RELEASE_STATUSES` deixa este mapa incompleto e reprova `tsc -p cms/web` no
 * mesmo PR — em vez de aparecer cru na tela, em ingles, meses depois.
 */
export const ROTULO_DO_ESTADO: Readonly<Record<ReleaseStatus, string>> = {
  draft: 'rascunho',
  pending_review: 'em revisao',
  approved: 'aprovada',
  building: 'em construcao',
  built: 'construida',
  published: 'publicada',
  revoked: 'revogada',
};
