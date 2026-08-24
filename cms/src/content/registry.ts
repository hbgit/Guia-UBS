/**
 * As entidades de conteudo, como DADO.
 *
 * O CRUD delas nao e escrito uma vez por entidade: e gerado deste registro por
 * `crud.ts`. O motivo nao e economia de linhas — sao tres passos que precisam
 * acontecer em TODA escrita (conferir a versao, gravar, registrar na trilha), e
 * a forma de falhar de dezessete copias e a decima setima esquecer o terceiro.
 * Ninguem nota ate precisar da trilha.
 *
 * `test/crud-registry.test.ts` percorre este registro e exige os tres de cada
 * entidade. Entidade nova sem entrada aqui nao ganha rota; entrada aqui sem os
 * invariantes reprova.
 *
 * ## Como as 17 tabelas de conteudo se distribuem
 *
 *   9 com CRUD proprio     asset, symptom_token, routing_outcome, venue, card,
 *                          service, document, service_document, flow_step
 *   6 traducoes ANINHADAS  token/venue/card/service/document/flow_step_translation
 *   2 no editor de regras  routing_rule + routing_rule_term (`routes/rules.ts`)
 *
 * `municipality` entra tambem, embora nao exista no pack: sem ela nao ha como
 * criar as entidades municipais.
 *
 * ## Traducao e aninhada, nao entidade irma
 *
 * Um cartao sem traducao e um cartao incompleto — o packer recusa publicar
 * assim. Modela-la como entidade propria convidaria a criar um sem o outro e
 * descobrir na publicacao.
 */
import type { SQLiteTable } from 'drizzle-orm/sqlite-core';

import {
  asset,
  card,
  cardTranslation,
  document,
  documentTranslation,
  flowStep,
  flowStepTranslation,
  municipality,
  routingOutcome,
  service,
  serviceDocument,
  serviceTranslation,
  symptomToken,
  tokenTranslation,
  venue,
  venueTranslation,
} from '../db/schema/content.js';

/**
 * Colunas que o SERVIDOR preenche e o cliente nunca envia.
 *
 * `version` merece nota: ela chega pelo cabecalho `If-Match`, como ETag, e nao
 * pelo corpo. Aceita-la no corpo convidaria um cliente a reenviar o valor que
 * acabou de ler — que e exatamente o conflito que o travamento otimista existe
 * para detectar.
 */
export const AUTHORING_FIELDS = ['version', 'updatedBy', 'updatedAt'] as const;

export interface Traducao {
  tabela: SQLiteTable;
  /**
   * Colunas da traducao que correspondem, NA ORDEM, a chave da entidade.
   * Em `service_translation` sao `municipalityId` e `serviceId`, que apontam
   * para `municipalityId` e `id` de `service`.
   */
  chaveEstrangeira: readonly string[];
}

export interface EntidadeConteudo {
  /** Segmento da URL: `/api/content/<nome>`. */
  nome: string;
  tabela: SQLiteTable;
  /**
   * Propriedades da chave primaria, na ordem em que aparecem no caminho.
   *
   * Nao e sempre `['id']`: `asset` usa `ref`, as municipais sao compostas com
   * `municipalityId` na frente, e `service_document` e juncao de tres.
   */
  chave: readonly string[];
  escopo: 'global' | 'municipal';
  traducao?: Traducao;
  /**
   * `false` quando a entidade e alvo de regra clinica ou de FK estrutural.
   *
   * A FK ja recusaria o DELETE, mas o caminho certo para tirar um token de
   * circulacao e `deprecated = 1`: as regras que o citam continuam validas e o
   * packer bloqueia a publicacao ate elas serem reescritas. Oferecer um DELETE
   * que sempre falha ensina o editor a ignorar mensagem de erro.
   */
  apagavel: boolean;
}

export const CONTENT_ENTITIES: readonly EntidadeConteudo[] = [
  // --- fora do pack, mas pre-requisito das municipais -----------------------
  {
    nome: 'municipalities',
    tabela: municipality,
    chave: ['id'],
    escopo: 'global',
    apagavel: false, // apagar o municipio levaria junto todo o conteudo dele
  },

  // --- globais --------------------------------------------------------------
  {
    nome: 'assets',
    tabela: asset,
    chave: ['ref'],
    escopo: 'global',
    // Alvo de FK de quase todas as outras: icone, imagem e audio.
    apagavel: false,
  },
  {
    nome: 'symptom-tokens',
    tabela: symptomToken,
    chave: ['id'],
    escopo: 'global',
    traducao: { tabela: tokenTranslation, chaveEstrangeira: ['tokenId'] },
    // Alvo de `routing_rule_term`: sai de circulacao por `deprecated`.
    apagavel: false,
  },
  {
    nome: 'routing-outcomes',
    tabela: routingOutcome,
    chave: ['id'],
    escopo: 'global',
    // Alvo de `routing_rule.outcome_id` e do desfecho padrao do pack.
    apagavel: false,
  },
  {
    nome: 'venues',
    tabela: venue,
    chave: ['id'],
    escopo: 'global',
    traducao: { tabela: venueTranslation, chaveEstrangeira: ['venueId'] },
    // Vocabulario fixo de tres (UBS, UPA, HOSPITAL).
    apagavel: false,
  },
  {
    nome: 'cards',
    tabela: card,
    chave: ['id'],
    escopo: 'global',
    traducao: { tabela: cardTranslation, chaveEstrangeira: ['cardId'] },
    // Alvo de `routing_outcome.card_id`.
    apagavel: false,
  },

  // --- municipais -----------------------------------------------------------
  {
    nome: 'services',
    tabela: service,
    chave: ['municipalityId', 'id'],
    escopo: 'municipal',
    traducao: { tabela: serviceTranslation, chaveEstrangeira: ['municipalityId', 'serviceId'] },
    apagavel: true,
  },
  {
    nome: 'documents',
    tabela: document,
    chave: ['municipalityId', 'id'],
    escopo: 'municipal',
    traducao: { tabela: documentTranslation, chaveEstrangeira: ['municipalityId', 'documentId'] },
    apagavel: true,
  },
  {
    nome: 'service-documents',
    tabela: serviceDocument,
    chave: ['municipalityId', 'serviceId', 'documentId'],
    escopo: 'municipal',
    apagavel: true,
  },
  {
    nome: 'flow-steps',
    tabela: flowStep,
    chave: ['municipalityId', 'id'],
    escopo: 'municipal',
    traducao: { tabela: flowStepTranslation, chaveEstrangeira: ['municipalityId', 'stepId'] },
    apagavel: true,
  },
];

export function entidadePorNome(nome: string): EntidadeConteudo | undefined {
  return CONTENT_ENTITIES.find((e) => e.nome === nome);
}
