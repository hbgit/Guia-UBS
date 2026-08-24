/**
 * Publicacao: ciclo de vida do pack, aprovacao clinica e suite golden
 * (arquitetura.md 4.3-C).
 */
import { sql } from 'drizzle-orm';
import { check, integer, sqliteTable, text, unique } from 'drizzle-orm/sqlite-core';

import { ADMIN_ROLES, adminUser } from './auth.js';
import { municipality } from './content.js';

/** Ciclo de vida do artefato. Ordem nao e livre — o item 19 monta a FSM sobre ela. */
export const RELEASE_STATUSES = [
  'draft',
  'pending_review',
  'approved',
  'built',
  'published',
  'revoked',
] as const;

export const APPROVAL_DECISIONS = ['approve', 'reject'] as const;

/**
 * Um pack, do rascunho a publicacao.
 *
 * `UNIQUE(municipality_id, pack_version)` e o anti-downgrade da INV-7 ancorado
 * no BANCO. O aparelho ja recusa versao menor que a ativa (`pack_verifier`), mas
 * essa defesa depende de o servidor nunca reemitir um numero: duas linhas com a
 * mesma versao e conteudos diferentes fariam metade da frota parar de atualizar
 * sem erro nenhum, porque cada aparelho ja teria "aquela versao".
 */
export const packRelease = sqliteTable(
  'pack_release',
  {
    id: text('id').primaryKey(),
    municipalityId: text('municipality_id')
      .notNull()
      .references(() => municipality.id),
    packVersion: integer('pack_version').notNull(),
    schemaVersion: text('schema_version').notNull(),
    status: text('status', { enum: RELEASE_STATUSES }).notNull().default('draft'),
    packSha256: text('pack_sha256'),
    manifestJson: text('manifest_json'),
    signedAt: text('signed_at'),
    publishedAt: text('published_at'),
    createdBy: text('created_by')
      .notNull()
      .references(() => adminUser.id),
    createdAt: text('created_at').notNull(),
  },
  (t) => [
    unique('pack_release_municipality_version').on(t.municipalityId, t.packVersion),
    check(
      'pack_release_status_valid',
      sql`${t.status} IN ('draft', 'pending_review', 'approved', 'built', 'published', 'revoked')`,
    ),
    /** Versao e monotonica E positiva — o mesmo dominio que `manifestSchema` exige. */
    check('pack_release_version_positive', sql`${t.packVersion} > 0`),
  ],
);

/**
 * Decisao de revisao. APPEND-ONLY.
 *
 * Uma aprovacao clinica que pode ser editada depois nao e aprovacao: e um campo
 * de estado. Retratar-se aqui e inserir uma linha nova de `reject`, que deixa as
 * duas visiveis.
 *
 * As regras de dual review — `approver_id != pack_release.created_by` e ao menos
 * um `clinical_reviewer` — NAO viram gatilho. A segunda e um agregado sobre
 * outras linhas, que gatilho SQLite so expressa com subquery fragil; e a
 * primeira sozinha daria a impressao de que a regra inteira esta no banco,
 * quando so metade estaria. Ambas sao do item 19, com teste proprio.
 */
export const approval = sqliteTable(
  'approval',
  {
    id: text('id').primaryKey(),
    packReleaseId: text('pack_release_id')
      .notNull()
      .references(() => packRelease.id),
    approverId: text('approver_id')
      .notNull()
      .references(() => adminUser.id),
    /** Papel NO MOMENTO da decisao: promover alguem depois nao reescreve o passado. */
    role: text('role', { enum: ADMIN_ROLES }).notNull(),
    decision: text('decision', { enum: APPROVAL_DECISIONS }).notNull(),
    comment: text('comment'),
    decidedAt: text('decided_at').notNull(),
  },
  (t) => [
    check('approval_decision_valid', sql`${t.decision} IN ('approve', 'reject')`),
    check('approval_role_valid', sql`${t.role} IN ('editor', 'clinical_reviewer', 'admin')`),
  ],
);

/**
 * Caso clinico da suite golden, versionado NO BANCO — junto das regras que ele
 * protege, e nao num arquivo que evolui em outro ritmo.
 *
 * `tokens_json` e uma composicao de sintomas ficticia, escrita pelo revisor
 * clinico. Nao ha aqui nenhuma sequencia de sintomas de pessoa real: o app nao
 * persiste nem transmite a dele (INV-2 / LGPD-RF13).
 */
export const goldenCase = sqliteTable('golden_case', {
  id: text('id').primaryKey(),
  tokensJson: text('tokens_json').notNull(),
  expectedOutcomeId: text('expected_outcome_id').notNull(),
  clinicalSource: text('clinical_source'),
  addedBy: text('added_by')
    .notNull()
    .references(() => adminUser.id),
  reviewedBy: text('reviewed_by').references(() => adminUser.id),
  active: integer('active').notNull().default(1),
});

/** Resultado de uma execucao da suite. Falha bloqueia a assinatura (PRD risco R5). */
export const goldenRun = sqliteTable('golden_run', {
  id: text('id').primaryKey(),
  packReleaseId: text('pack_release_id')
    .notNull()
    .references(() => packRelease.id),
  passed: integer('passed').notNull(),
  total: integer('total').notNull(),
  failuresJson: text('failures_json'),
  ranAt: text('ran_at').notNull(),
});

/**
 * Chaves de assinatura Ed25519. Duas ativas ao mesmo tempo permitem rotacionar
 * sem release do app: o aparelho ja conhece `k2` antes de `k1` ser aposentada
 * (PRD risco R4).
 *
 * So a PUBLICA mora aqui. A privada vive no cofre do provedor (LGPD-RT06) e
 * nunca toca este banco.
 */
export const signingKey = sqliteTable('signing_key', {
  keyId: text('key_id').primaryKey(),
  publicKey: text('public_key').notNull(),
  activatedAt: text('activated_at').notNull(),
  retiredAt: text('retired_at'),
});
