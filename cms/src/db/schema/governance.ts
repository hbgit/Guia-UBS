/**
 * Governanca: trilha de auditoria, documentos legais e registro de aceite
 * (arquitetura.md 4.3-A).
 *
 * Duas destas tabelas sao APPEND-ONLY, e nao por capricho de modelagem: o valor
 * de uma trilha de auditoria e de um aceite de termo esta inteiro em serem
 * irrefutaveis. Uma linha que pode ser editada nao prova nada.
 *
 * A proibicao NAO mora aqui — o Drizzle nao expressa gatilho. Mora em
 * `../triggers.ts`, gerada a partir de `APPEND_ONLY_TABLES` (schema/index.ts).
 */
import { sql } from 'drizzle-orm';
import { check, sqliteTable, text, unique } from 'drizzle-orm/sqlite-core';

import { adminUser } from './auth.js';

/** Tipos de documento legal versionado (lgpd.md LGPD-DOC01–04). */
export const LEGAL_DOC_TYPES = ['tos', 'privacy', 'consent'] as const;

/**
 * Quem fez o que, quando, sobre qual entidade. APPEND-ONLY (lgpd.md LGPD-RT03).
 *
 * `before_json` e `after_json` carregam PII quando a entidade auditada e
 * `admin_user` — o expurgo por retencao (LGPD-RF07) alcanca esta tabela pelo
 * procedimento descrito em `../triggers.ts`.
 */
export const auditEntry = sqliteTable('audit_entry', {
  id: text('id').primaryKey(),
  /**
   * Quem agiu. **Nulo quando nao houve ator autenticado** — e o caso de um login
   * recusado, que e exatamente o evento que mais interessa registrar.
   *
   * O item 16 declarou esta coluna NOT NULL com o argumento de que entrada sem
   * ator e entrada sem responsavel. O argumento vale para acao de operador e nao
   * vale para autenticacao: ali "nao sabemos quem era" E o fato registrado. As
   * alternativas eram piores — inventar uma linha `system` em `admin_user`
   * criaria um operador que parece porta dos fundos numa auditoria, e atribuir a
   * tentativa a conta visada afirmaria que a pessoa agiu quando pode ter sido
   * um ataque contra ela.
   *
   * Quem a tentativa visava fica em `entity_id`, ja pseudonimizado.
   */
  actorId: text('actor_id').references(() => adminUser.id),
  action: text('action').notNull(),
  entityType: text('entity_type').notNull(),
  entityId: text('entity_id').notNull(),
  beforeJson: text('before_json'),
  afterJson: text('after_json'),
  /** Hash, nunca o IP: LGPD-RT03 proibe dado pessoal em log. PII pseudonimizada. */
  ipHash: text('ip_hash'),
  occurredAt: text('occurred_at').notNull(),
});

/**
 * Texto legal versionado. O aceite referencia versao E hash exatos, porque
 * mudanca material do texto dispara re-aceite (lgpd.md LGPD-RT04) — e "material"
 * so e verificavel se o texto aceito estiver fixado por hash.
 */
export const legalDocument = sqliteTable(
  'legal_document',
  {
    id: text('id').primaryKey(),
    type: text('type', { enum: LEGAL_DOC_TYPES }).notNull(),
    version: text('version').notNull(),
    contentMd: text('content_md').notNull(),
    contentHash: text('content_hash').notNull(),
    effectiveFrom: text('effective_from').notNull(),
  },
  (t) => [
    unique('legal_document_type_version').on(t.type, t.version),
    check('legal_document_type_valid', sql`${t.type} IN ('tos', 'privacy', 'consent')`),
  ],
);

/**
 * Registro de aceite. APPEND-ONLY (lgpd.md LGPD-RT05).
 *
 * O onus da prova do consentimento e do controlador (art. 8 §2 da Lei
 * 13.709/2018). Uma tabela onde o controlador pode reescrever o aceite nao
 * serve como prova — nem a favor, nem contra.
 *
 * `subject_ref` e o titular do aceite: operador do CMS ou participante do
 * piloto. Nao existe usuario final do app aqui — o app nao coleta identidade
 * (INV-2). PII.
 */
export const consentRecord = sqliteTable('consent_record', {
  id: text('id').primaryKey(),
  subjectRef: text('subject_ref').notNull(),
  docType: text('doc_type', { enum: LEGAL_DOC_TYPES }).notNull(),
  docVersion: text('doc_version').notNull(),
  /** Copia do hash no momento do aceite: o vinculo nao pode depender de JOIN. */
  docHash: text('doc_hash').notNull(),
  method: text('method').notNull(),
  acceptedAt: text('accepted_at').notNull(),
});
