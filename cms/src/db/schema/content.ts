/**
 * Autoria de conteudo: o espelho MUTAVEL do `content.db` (arquitetura.md 4.3-B).
 *
 * O pack e read-only e trocado inteiro; aqui o conteudo e editado, revisado e
 * versionado. As colunas de dominio sao as MESMAS de
 * `contract/src/content-schema.ts` — e `test/schema-conformance.test.ts` compara
 * as duas listas nos dois sentidos, porque duas copias escritas a mao que
 * ninguem confere divergem (arquitetura.md 7, risco de probabilidade Alta).
 *
 * As unicas diferencas permitidas estao em `AUTHORING_ONLY_COLUMNS`
 * (schema/index.ts). Acrescentar coluna aqui sem par no contrato — ou la sem
 * par aqui — reprova o CI.
 *
 * ## Escopo: clinico global, logistica municipal
 *
 * O pack e por municipio; este banco e unico. O corte NAO e preferencia: e a
 * direcao das chaves estrangeiras que o decide.
 *
 *   GLOBAL     asset, symptom_token(+trad), routing_outcome, routing_rule(+term),
 *              venue(+trad), card(+trad)
 *   MUNICIPAL  service(+trad), document(+trad), service_document, flow_step(+trad)
 *
 * `symptom_token.icon_ref -> asset.ref` e `routing_outcome.venue_id -> venue.id`
 * saem de tabelas globais. Se `asset` ou `venue` fossem municipais, a PK deles
 * viraria composta e o lado global nao teria `municipality_id` para oferecer: a
 * FK nao fecharia. Municipal -> global e valido e e o unico sentido que ocorre.
 *
 * O ganho clinico e o motivo de as REGRAS estarem do lado global: uma red flag
 * corrigida alcanca toda a rede por construcao. Nao existe o estado "corrigido
 * em Boa Vista, esquecido no interior".
 *
 * Municipio que precise de escala de severidade propria e migracao ADITIVA
 * depois (acrescentar `municipality_id`); o inverso — colapsar N copias de uma
 * regra clinica numa so — nao e.
 */
import { COLOR_TOKENS, LANGS, VENUES } from '@guia-ubs/contract';
import { sql } from 'drizzle-orm';
import {
  check,
  foreignKey,
  index,
  integer,
  primaryKey,
  sqliteTable,
  text,
} from 'drizzle-orm/sqlite-core';

import { adminUser } from './auth.js';

/** Estados de uma regra de encaminhamento. Aprovada nunca e editada in-place. */
export const RULE_STATUSES = ['draft', 'approved'] as const;

/**
 * Colunas de autoria comuns a toda entidade editavel.
 *
 * FABRICA, nao constante: um `ColumnBuilder` do Drizzle e consumido ao ser
 * montado na tabela. Reusar a MESMA instancia em duas tabelas produz erro
 * silencioso de pertencimento; uma chamada nova por tabela nao.
 *
 * `version` e o travamento otimista (409 no item 18) e tem gatilho de
 * monotonicidade — ver `../triggers.ts`.
 *
 * `updated_by` e NOT NULL de proposito: conteudo clinico sem autor e conteudo
 * sem responsavel. A carga inicial a partir de `seed/` usa uma conta de servico
 * com linha propria em `admin_user`, que e auditavel; um NULL nao seria.
 */
const authoring = () => ({
  version: integer('version').notNull().default(1),
  updatedBy: text('updated_by')
    .notNull()
    .references(() => adminUser.id),
  updatedAt: text('updated_at').notNull(),
});

// ---------------------------------------------------------------------------
// 0. Municipio — nao existe no pack (o pack JA e de um municipio so)
// ---------------------------------------------------------------------------

/**
 * Ganha as colunas de autoria como qualquer entidade editavel, embora nao exista
 * no pack.
 *
 * A alternativa seria isenta-la, e ai a fabrica de CRUD teria um caso especial:
 * uma entidade onde `If-Match` nao vale e a trilha nao registra versao. Caso
 * especial em fabrica generica e o lugar onde o proximo defeito se esconde — e o
 * risco real existe, dois admins renomeando o mesmo municipio ao mesmo tempo.
 */
export const municipality = sqliteTable('municipality', {
  id: text('id').primaryKey(),
  /** Codigo IBGE de 7 digitos. */
  code: text('code').notNull().unique(),
  name: text('name').notNull(),
  active: integer('active').notNull().default(1),
  ...authoring(),
});

// ---------------------------------------------------------------------------
// 1. Assets — GLOBAL (alvo de FK de tabelas globais)
// ---------------------------------------------------------------------------

/**
 * O pool de arquivos e global; o USO e que e municipal. Um municipio publica
 * `image.ubs.0000000` e so ele o referencia.
 *
 * `storage_key` e o objeto no MinIO — unica coluna de dominio que existe aqui e
 * nao no pack: o pack carrega `path` relativo dentro do artefato publicado, que
 * o packer resolve na hora de empacotar.
 */
export const asset = sqliteTable('asset', {
  ref: text('ref').primaryKey(),
  kind: text('kind', { enum: ['icon', 'image', 'audio'] }).notNull(),
  path: text('path').notNull(),
  sha256: text('sha256').notNull(),
  bytes: integer('bytes').notNull(),
  storageKey: text('storage_key').notNull(),
  ...authoring(),
});

// ---------------------------------------------------------------------------
// 2. Ontologia de sintomas — GLOBAL
// ---------------------------------------------------------------------------

export const symptomToken = sqliteTable('symptom_token', {
  id: text('id').primaryKey(),
  kind: text('kind', { enum: ['body_part', 'symptom', 'modifier'] }).notNull(),
  iconRef: text('icon_ref')
    .notNull()
    .references(() => asset.ref),
  sortOrder: integer('sort_order').notNull().default(0),
  deprecated: integer('deprecated').notNull().default(0),
  ...authoring(),
});

export const tokenTranslation = sqliteTable(
  'token_translation',
  {
    tokenId: text('token_id')
      .notNull()
      .references(() => symptomToken.id),
    lang: text('lang', { enum: LANGS }).notNull(),
    label: text('label').notNull(),
    audioRef: text('audio_ref').references(() => asset.ref),
    ...authoring(),
  },
  (t) => [primaryKey({ columns: [t.tokenId, t.lang] })],
);

// ---------------------------------------------------------------------------
// 3. Motor de encaminhamento — GLOBAL (correcao clinica alcanca toda a rede)
// ---------------------------------------------------------------------------

export const routingOutcome = sqliteTable('routing_outcome', {
  id: text('id').primaryKey(),
  severityLevel: integer('severity_level').notNull(),
  cardId: text('card_id')
    .notNull()
    .references(() => card.id),
  venueId: text('venue_id', { enum: VENUES })
    .notNull()
    .references(() => venue.id),
  ...authoring(),
});

/**
 * `status` e a unica coluna alem das de autoria que o pack nao tem: regra
 * aprovada nao e editada in-place, gera linha nova (arquitetura.md 4.3-B). Um
 * gatilho recusa UPDATE quando `OLD.status = 'approved'` — a frase de documento
 * que nada aplica e a frase que alguem contraria sem perceber, e o que se
 * contraria aqui e conteudo clinico ja revisado em dupla.
 */
export const routingRule = sqliteTable(
  'routing_rule',
  {
    id: text('id').primaryKey(),
    priority: integer('priority').notNull(),
    outcomeId: text('outcome_id')
      .notNull()
      .references(() => routingOutcome.id),
    rationale: text('rationale'),
    clinicalSource: text('clinical_source'),
    status: text('status', { enum: RULE_STATUSES }).notNull().default('draft'),
    ...authoring(),
  },
  (t) => [check('routing_rule_status_valid', sql`${t.status} IN ('draft', 'approved')`)],
);

export const routingRuleTerm = sqliteTable(
  'routing_rule_term',
  {
    ruleId: text('rule_id')
      .notNull()
      .references(() => routingRule.id),
    groupNo: integer('group_no').notNull(),
    tokenId: text('token_id')
      .notNull()
      .references(() => symptomToken.id),
    negated: integer('negated').notNull().default(0),
    ...authoring(),
  },
  (t) => [
    primaryKey({ columns: [t.ruleId, t.groupNo, t.tokenId] }),
    index('routing_rule_term_token_idx').on(t.tokenId),
  ],
);

// ---------------------------------------------------------------------------
// 4. Locais e cartoes — GLOBAL
// ---------------------------------------------------------------------------

export const venue = sqliteTable(
  'venue',
  {
    id: text('id', { enum: VENUES }).primaryKey(),
    iconRef: text('icon_ref')
      .notNull()
      .references(() => asset.ref),
    colorToken: text('color_token', { enum: COLOR_TOKENS }).notNull(),
    sortOrder: integer('sort_order').notNull().default(0),
    ...authoring(),
  },
  (t) => [check('venue_color_valid', sql`${t.colorToken} IN ('green', 'red', 'blue')`)],
);

export const venueTranslation = sqliteTable(
  'venue_translation',
  {
    venueId: text('venue_id', { enum: VENUES })
      .notNull()
      .references(() => venue.id),
    lang: text('lang', { enum: LANGS }).notNull(),
    label: text('label').notNull(),
    audioRef: text('audio_ref').references(() => asset.ref),
    ...authoring(),
  },
  (t) => [primaryKey({ columns: [t.venueId, t.lang] })],
);

export const card = sqliteTable(
  'card',
  {
    id: text('id').primaryKey(),
    kind: text('kind', { enum: ['result', 'info', 'step', 'document'] }).notNull(),
    iconRef: text('icon_ref')
      .notNull()
      .references(() => asset.ref),
    colorToken: text('color_token', { enum: COLOR_TOKENS }).notNull(),
    sortOrder: integer('sort_order').notNull().default(0),
    ...authoring(),
  },
  (t) => [check('card_color_valid', sql`${t.colorToken} IN ('green', 'red', 'blue')`)],
);

export const cardTranslation = sqliteTable(
  'card_translation',
  {
    cardId: text('card_id')
      .notNull()
      .references(() => card.id),
    lang: text('lang', { enum: LANGS }).notNull(),
    title: text('title').notNull(),
    body: text('body'),
    audioRef: text('audio_ref').references(() => asset.ref),
    ...authoring(),
  },
  (t) => [
    primaryKey({ columns: [t.cardId, t.lang] }),
    index('card_translation_lang_idx').on(t.lang),
  ],
);

// ---------------------------------------------------------------------------
// 5. Servicos e documentos — MUNICIPAL
// ---------------------------------------------------------------------------

export const service = sqliteTable(
  'service',
  {
    municipalityId: text('municipality_id')
      .notNull()
      .references(() => municipality.id),
    id: text('id').notNull(),
    venueId: text('venue_id', { enum: VENUES })
      .notNull()
      .references(() => venue.id),
    iconRef: text('icon_ref')
      .notNull()
      .references(() => asset.ref),
    sortOrder: integer('sort_order').notNull().default(0),
    ...authoring(),
  },
  (t) => [primaryKey({ columns: [t.municipalityId, t.id] })],
);

export const serviceTranslation = sqliteTable(
  'service_translation',
  {
    municipalityId: text('municipality_id').notNull(),
    serviceId: text('service_id').notNull(),
    lang: text('lang', { enum: LANGS }).notNull(),
    label: text('label').notNull(),
    audioRef: text('audio_ref').references(() => asset.ref),
    ...authoring(),
  },
  (t) => [
    primaryKey({ columns: [t.municipalityId, t.serviceId, t.lang] }),
    foreignKey({
      columns: [t.municipalityId, t.serviceId],
      foreignColumns: [service.municipalityId, service.id],
    }),
  ],
);

export const document = sqliteTable(
  'document',
  {
    municipalityId: text('municipality_id')
      .notNull()
      .references(() => municipality.id),
    id: text('id').notNull(),
    iconRef: text('icon_ref')
      .notNull()
      .references(() => asset.ref),
    imageRef: text('image_ref').references(() => asset.ref),
    ...authoring(),
  },
  (t) => [primaryKey({ columns: [t.municipalityId, t.id] })],
);

export const documentTranslation = sqliteTable(
  'document_translation',
  {
    municipalityId: text('municipality_id').notNull(),
    documentId: text('document_id').notNull(),
    lang: text('lang', { enum: LANGS }).notNull(),
    label: text('label').notNull(),
    hint: text('hint'),
    audioRef: text('audio_ref').references(() => asset.ref),
    ...authoring(),
  },
  (t) => [
    primaryKey({ columns: [t.municipalityId, t.documentId, t.lang] }),
    foreignKey({
      columns: [t.municipalityId, t.documentId],
      foreignColumns: [document.municipalityId, document.id],
    }),
  ],
);

export const serviceDocument = sqliteTable(
  'service_document',
  {
    municipalityId: text('municipality_id').notNull(),
    serviceId: text('service_id').notNull(),
    documentId: text('document_id').notNull(),
    required: integer('required').notNull().default(1),
    ...authoring(),
  },
  (t) => [
    primaryKey({ columns: [t.municipalityId, t.serviceId, t.documentId] }),
    foreignKey({
      columns: [t.municipalityId, t.serviceId],
      foreignColumns: [service.municipalityId, service.id],
    }),
    foreignKey({
      columns: [t.municipalityId, t.documentId],
      foreignColumns: [document.municipalityId, document.id],
    }),
    index('service_document_document_idx').on(t.municipalityId, t.documentId),
  ],
);

// ---------------------------------------------------------------------------
// 6. Fluxo de atendimento na unidade — MUNICIPAL
// ---------------------------------------------------------------------------

export const flowStep = sqliteTable(
  'flow_step',
  {
    municipalityId: text('municipality_id')
      .notNull()
      .references(() => municipality.id),
    id: text('id').notNull(),
    venueId: text('venue_id', { enum: VENUES })
      .notNull()
      .references(() => venue.id),
    stepOrder: integer('step_order').notNull(),
    iconRef: text('icon_ref')
      .notNull()
      .references(() => asset.ref),
    ...authoring(),
  },
  (t) => [
    primaryKey({ columns: [t.municipalityId, t.id] }),
    index('flow_step_venue_order_idx').on(t.municipalityId, t.venueId, t.stepOrder),
  ],
);

export const flowStepTranslation = sqliteTable(
  'flow_step_translation',
  {
    municipalityId: text('municipality_id').notNull(),
    stepId: text('step_id').notNull(),
    lang: text('lang', { enum: LANGS }).notNull(),
    title: text('title').notNull(),
    body: text('body'),
    audioRef: text('audio_ref').references(() => asset.ref),
    ...authoring(),
  },
  (t) => [
    primaryKey({ columns: [t.municipalityId, t.stepId, t.lang] }),
    foreignKey({
      columns: [t.municipalityId, t.stepId],
      foreignColumns: [flowStep.municipalityId, flowStep.id],
    }),
  ],
);
