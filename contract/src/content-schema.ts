/**
 * Schema do `content.db` — arquivo SQLite read-only distribuido aos dispositivos.
 *
 * FONTE UNICA DE VERDADE: deste modulo derivam, por codegen (`npm run contract:generate`),
 * o `pack-schema.json` e os modelos Dart do app. Alterar uma coluna aqui quebra o build
 * do Flutter no mesmo PR — e essa e a intencao (stack.md 3.3).
 *
 * Nao contem nenhum dado de usuario: o pack e conteudo publico assinado (lgpd.md RF13).
 */
import { integer, primaryKey, sqliteTable, text } from 'drizzle-orm/sqlite-core';

/** Idiomas do MVP. Linguas indigenas entram na v2 (brainstorm.md). */
export const LANGS = ['pt', 'es'] as const;

/** Semantica de cor fixa do design: verde=rotina, vermelho=emergencia, azul=informacao. */
export const COLOR_TOKENS = ['green', 'red', 'blue'] as const;

/** Locais de atendimento do SUS cobertos pelo guia. */
export const VENUES = ['UBS', 'UPA', 'HOSPITAL'] as const;

// ---------------------------------------------------------------------------
// 1. Metadados do pacote
// ---------------------------------------------------------------------------

/** Linha unica (id=1) com a identidade do pacote. */
export const packMeta = sqliteTable('pack_meta', {
  id: integer('id').primaryKey(),
  /** Inteiro monotonico por municipio. Base do anti-downgrade (espec.md INV-7). */
  packVersion: integer('pack_version').notNull(),
  /** major.minor; o app rejeita major incompativel (espec.md INV-6). */
  schemaVersion: text('schema_version').notNull(),
  municipalityCode: text('municipality_code'),
  builtAt: text('built_at').notNull(),
  /** Desfecho aplicado quando nenhuma regra casa — nunca silencio (fail-closed). */
  defaultOutcomeId: text('default_outcome_id').notNull(),
  sourceCommit: text('source_commit'),
});

// ---------------------------------------------------------------------------
// 2. Ontologia de sintomas
// ---------------------------------------------------------------------------

/**
 * Vocabulario de icones que o usuario compoe na triagem.
 * O `id` e um contrato imutavel: renomear orfana regras silenciosamente,
 * por isso o packer valida integridade referencial antes de assinar.
 */
export const symptomToken = sqliteTable('symptom_token', {
  id: text('id').primaryKey(),
  kind: text('kind', { enum: ['body_part', 'symptom', 'modifier'] }).notNull(),
  iconRef: text('icon_ref').notNull().references(() => asset.ref),
  sortOrder: integer('sort_order').notNull().default(0),
  /** Token descontinuado continua legivel por packs antigos, mas some da UI. */
  deprecated: integer('deprecated').notNull().default(0),
});

export const tokenTranslation = sqliteTable(
  'token_translation',
  {
    tokenId: text('token_id').notNull().references(() => symptomToken.id),
    lang: text('lang', { enum: LANGS }).notNull(),
    /** Redundante ao icone: a UI nunca exige leitura (espec.md RNF-06). */
    label: text('label').notNull(),
    audioRef: text('audio_ref').references(() => asset.ref),
  },
  (t) => [primaryKey({ columns: [t.tokenId, t.lang] })],
);

// ---------------------------------------------------------------------------
// 3. Motor de encaminhamento (dados, nao codigo)
// ---------------------------------------------------------------------------

/**
 * Desfechos possiveis, ordenados por `severityLevel`.
 * O inteiro torna trivial a invariante `severity_final = max(gate, llm)` (INV-1)
 * e permite inserir niveis intermediarios sem tocar na logica.
 */
export const routingOutcome = sqliteTable('routing_outcome', {
  id: text('id').primaryKey(),
  severityLevel: integer('severity_level').notNull(),
  cardId: text('card_id').notNull().references(() => card.id),
  venueId: text('venue_id').notNull().references(() => venue.id),
});

/**
 * Regra de encaminhamento em forma normal disjuntiva.
 *
 * Tabela UNICA para o gate deterministico e para o RuleOnlyEngine — e o que
 * torna estruturalmente impossivel as duas divergirem (espec.md 7.2).
 * As "red flags" da especificacao sao o subconjunto cujo outcome tem o maior
 * `severityLevel`; o gate as avalia ANTES de qualquer inferencia.
 */
export const routingRule = sqliteTable('routing_rule', {
  id: text('id').primaryKey(),
  /** Menor valor vence quando mais de uma regra casa. */
  priority: integer('priority').notNull(),
  outcomeId: text('outcome_id').notNull().references(() => routingOutcome.id),
  /** Justificativa clinica — auditavel, nunca exibida ao usuario. */
  rationale: text('rationale'),
  clinicalSource: text('clinical_source'),
});

/**
 * Termo de uma regra: E dentro do mesmo `groupNo`, OU entre grupos distintos.
 * A regra dispara se existir um grupo em que todos os termos sao satisfeitos.
 */
export const routingRuleTerm = sqliteTable(
  'routing_rule_term',
  {
    ruleId: text('rule_id').notNull().references(() => routingRule.id),
    groupNo: integer('group_no').notNull(),
    tokenId: text('token_id').notNull().references(() => symptomToken.id),
    negated: integer('negated').notNull().default(0),
  },
  (t) => [primaryKey({ columns: [t.ruleId, t.groupNo, t.tokenId] })],
);

// ---------------------------------------------------------------------------
// 4. Locais, cartoes e servicos
// ---------------------------------------------------------------------------

export const venue = sqliteTable('venue', {
  id: text('id', { enum: VENUES }).primaryKey(),
  iconRef: text('icon_ref').notNull().references(() => asset.ref),
  colorToken: text('color_token', { enum: COLOR_TOKENS }).notNull(),
});

export const venueTranslation = sqliteTable(
  'venue_translation',
  {
    venueId: text('venue_id', { enum: VENUES }).notNull().references(() => venue.id),
    lang: text('lang', { enum: LANGS }).notNull(),
    label: text('label').notNull(),
    audioRef: text('audio_ref').references(() => asset.ref),
  },
  (t) => [primaryKey({ columns: [t.venueId, t.lang] })],
);

/** Unidade de resposta exibida ao usuario (resultado, informacao, passo, documento). */
export const card = sqliteTable('card', {
  id: text('id').primaryKey(),
  kind: text('kind', { enum: ['result', 'info', 'step', 'document'] }).notNull(),
  iconRef: text('icon_ref').notNull().references(() => asset.ref),
  colorToken: text('color_token', { enum: COLOR_TOKENS }).notNull(),
  sortOrder: integer('sort_order').notNull().default(0),
});

export const cardTranslation = sqliteTable(
  'card_translation',
  {
    cardId: text('card_id').notNull().references(() => card.id),
    lang: text('lang', { enum: LANGS }).notNull(),
    title: text('title').notNull(),
    body: text('body'),
    /** Narracao offline: essencial para publico de baixo letramento. */
    audioRef: text('audio_ref').references(() => asset.ref),
  },
  (t) => [primaryKey({ columns: [t.cardId, t.lang] })],
);

export const service = sqliteTable('service', {
  id: text('id').primaryKey(),
  venueId: text('venue_id', { enum: VENUES }).notNull().references(() => venue.id),
  iconRef: text('icon_ref').notNull().references(() => asset.ref),
  sortOrder: integer('sort_order').notNull().default(0),
});

export const serviceTranslation = sqliteTable(
  'service_translation',
  {
    serviceId: text('service_id').notNull().references(() => service.id),
    lang: text('lang', { enum: LANGS }).notNull(),
    label: text('label').notNull(),
    audioRef: text('audio_ref').references(() => asset.ref),
  },
  (t) => [primaryKey({ columns: [t.serviceId, t.lang] })],
);

// ---------------------------------------------------------------------------
// 5. Documentacao exigida
// ---------------------------------------------------------------------------

export const document = sqliteTable('document', {
  id: text('id').primaryKey(),
  iconRef: text('icon_ref').notNull().references(() => asset.ref),
  /** Foto ilustrativa do documento — o usuario reconhece pela imagem. */
  imageRef: text('image_ref').references(() => asset.ref),
});

export const documentTranslation = sqliteTable(
  'document_translation',
  {
    documentId: text('document_id').notNull().references(() => document.id),
    lang: text('lang', { enum: LANGS }).notNull(),
    label: text('label').notNull(),
    hint: text('hint'),
    audioRef: text('audio_ref').references(() => asset.ref),
  },
  (t) => [primaryKey({ columns: [t.documentId, t.lang] })],
);

export const serviceDocument = sqliteTable(
  'service_document',
  {
    serviceId: text('service_id').notNull().references(() => service.id),
    documentId: text('document_id').notNull().references(() => document.id),
    required: integer('required').notNull().default(1),
  },
  (t) => [primaryKey({ columns: [t.serviceId, t.documentId] })],
);

// ---------------------------------------------------------------------------
// 6. Fluxo de atendimento na unidade
// ---------------------------------------------------------------------------

export const flowStep = sqliteTable('flow_step', {
  id: text('id').primaryKey(),
  venueId: text('venue_id', { enum: VENUES }).notNull().references(() => venue.id),
  stepOrder: integer('step_order').notNull(),
  iconRef: text('icon_ref').notNull().references(() => asset.ref),
});

export const flowStepTranslation = sqliteTable(
  'flow_step_translation',
  {
    stepId: text('step_id').notNull().references(() => flowStep.id),
    lang: text('lang', { enum: LANGS }).notNull(),
    title: text('title').notNull(),
    body: text('body'),
    audioRef: text('audio_ref').references(() => asset.ref),
  },
  (t) => [primaryKey({ columns: [t.stepId, t.lang] })],
);

// ---------------------------------------------------------------------------
// 7. Assets binarios
// ---------------------------------------------------------------------------

/**
 * Icones, imagens e audios empacotados junto ao pack.
 * O `sha256` de cada asset e verificado na instalacao: o servidor de conteudo e
 * qualquer espelho sao infraestrutura nao-confiavel (espec.md RNF-05).
 */
export const asset = sqliteTable('asset', {
  ref: text('ref').primaryKey(),
  kind: text('kind', { enum: ['icon', 'image', 'audio'] }).notNull(),
  /** Caminho relativo dentro do pacote publicado. */
  path: text('path').notNull(),
  sha256: text('sha256').notNull(),
  bytes: integer('bytes').notNull(),
});
