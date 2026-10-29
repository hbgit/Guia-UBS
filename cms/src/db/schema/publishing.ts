/**
 * Publicacao: ciclo de vida do pack, aprovacao clinica e suite golden
 * (arquitetura.md 4.3-C).
 */
import { CATEGORIAS_COREN_ACEITAS, CONSELHOS, UFS } from '@guia-ubs/contract';
import { sql, type SQL } from 'drizzle-orm';
import { check, integer, sqliteTable, text, unique, type AnySQLiteColumn } from 'drizzle-orm/sqlite-core';

import { ADMIN_ROLES, adminUser } from './auth.js';
import { municipality } from './content.js';

/**
 * Ciclo de vida do artefato.
 *
 * `building` nao estava na lista original de `arquitetura.md 4.3-C` e entrou no
 * item 19 por um motivo: sem um estado de POSSE entre `approved` e `built`, dois
 * processos do job construiriam a mesma release em paralelo. Hoje o compose sobe
 * uma instancia so — mas "uma instancia hoje" e a mesma classe de suposicao que o
 * item 18 converteu em invariante ao medir o `PRAGMA foreign_keys`.
 *
 * A posse e tomada por compare-and-set (`approved -> building`): so um vence.
 */
export const RELEASE_STATUSES = [
  'draft',
  'pending_review',
  'approved',
  'building',
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
    /**
     * Quando o job tomou posse desta release.
     *
     * Serve para diagnostico, nao para exclusao mutua — quem garante a posse e o
     * compare-and-set sobre `status`. Existe porque uma release parada em
     * `building` precisa dizer HA QUANTO TEMPO: sem isso, "o job travou" e
     * indistinguivel de "o job esta trabalhando".
     */
    claimedAt: text('claimed_at'),
    /**
     * Quando o portao golden barrou esta release pela ultima vez — carimbado pelo
     * BANCO (`strftime`), nunca pelo processo, porque e comparado com
     * `audit_entry.occurred_at`, que tambem e. Nulo enquanto nao ha bloqueio.
     * Quem le e grava e o worker (P0-2, D11).
     */
    blockedAt: text('blocked_at'),
    createdBy: text('created_by')
      .notNull()
      .references(() => adminUser.id),
    createdAt: text('created_at').notNull(),
  },
  (t) => [
    unique('pack_release_municipality_version').on(t.municipalityId, t.packVersion),
    check(
      'pack_release_status_valid',
      sql`${t.status} IN ('draft', 'pending_review', 'approved', 'building', 'built', 'published', 'revoked')`,
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
 * `col IN ('a', 'b', ...)` a partir de uma constante do contrato.
 *
 * A lista NUNCA e digitada aqui: conselho ou UF acrescentados ao contrato chegam
 * ao `CHECK` por `npm run cms:generate`, e `cms:check` reprova se ninguem rodou.
 * Os valores sao literais do proprio repositorio, por isso o `sql.raw`.
 */
function emLista(coluna: AnySQLiteColumn, valores: readonly string[]): SQL {
  return sql`${coluna} IN (${sql.raw(valores.map((v) => `'${v}'`).join(', '))})`;
}

/**
 * Caso clinico da suite golden, versionado NO BANCO — junto das regras que ele
 * protege, e nao num arquivo que evolui em outro ritmo.
 *
 * `tokens_json` e uma composicao de sintomas ficticia, escrita pelo revisor
 * clinico. Nao ha aqui nenhuma sequencia de sintomas de pessoa real: o app nao
 * persiste nem transmite a dele (INV-2 / LGPD-RF13).
 *
 * Nao ha coluna de revisor. "Revisado" e ter ao menos `MIN_REVISORES` linhas em
 * `golden_case_review` — a antiga `reviewed_by` era FK para OPERADOR do CMS, e
 * quem revisa e um profissional que pode nem ter conta (P0-2, D6).
 */
export const goldenCase = sqliteTable('golden_case', {
  id: text('id').primaryKey(),
  tokensJson: text('tokens_json').notNull(),
  expectedOutcomeId: text('expected_outcome_id').notNull(),
  clinicalSource: text('clinical_source'),
  addedBy: text('added_by')
    .notNull()
    .references(() => adminUser.id),
  active: integer('active').notNull().default(1),
});

/**
 * Atestado de um profissional que revisa casos golden (P0-2, D3/D6).
 *
 * E o atestado de uma PESSOA, nao uma conta: nao autentica nada, e por isso nao
 * e a "segunda tabela de identidade" que o `CLAUDE.md` veta. Quem o registrou e o
 * `actor_id` da trilha, alem de `created_by`.
 *
 * `id` vem do registro publico `seed/golden/atestados.yaml` (`AT-NNNN`), nunca e
 * gerado aqui: cada CMS implantado recebe o mesmo ID para o mesmo profissional.
 * Nome e registro so existem neste banco (PII_COLUMNS); o repositorio guarda o
 * ID, o conselho, a UF e o hash do termo.
 */
export const goldenAttestation = sqliteTable(
  'golden_attestation',
  {
    id: text('id').primaryKey(),
    nome: text('nome').notNull(),
    conselho: text('conselho', { enum: CONSELHOS }).notNull(),
    uf: text('uf', { enum: UFS }).notNull(),
    categoria: text('categoria'),
    registro: text('registro').notNull(),
    termoSha256: text('termo_sha256').notNull(),
    createdBy: text('created_by')
      .notNull()
      .references(() => adminUser.id),
    createdAt: text('created_at').notNull(),
  },
  (t) => [
    /** Um profissional, um ID: senao uma pessoa contaria como duas no quorum. */
    unique('golden_attestation_profissional').on(t.conselho, t.uf, t.registro),
    /** Um termo assinado, um atestado. */
    unique('golden_attestation_termo').on(t.termoSha256),
    check('golden_attestation_conselho_valid', emLista(t.conselho, CONSELHOS)),
    check('golden_attestation_uf_valid', emLista(t.uf, UFS)),
    /**
     * COREN so de enfermeiro; CRM sem categoria. A inscricao de COREN carrega a
     * categoria (`-TE` e tecnico), e tecnico nao revisa triagem.
     *
     * O `IS NOT NULL` nao e redundante: `NULL IN (...)` da NULL, e CHECK que da
     * NULL PASSA. Sem ele, COREN sem categoria entraria.
     */
    check(
      'golden_attestation_categoria_valid',
      sql`(${t.conselho} = 'COREN' AND ${t.categoria} IS NOT NULL AND ${emLista(t.categoria, CATEGORIAS_COREN_ACEITAS)}) OR (${t.conselho} = 'CRM' AND ${t.categoria} IS NULL)`,
    ),
    check(
      'golden_attestation_termo_hex',
      sql`length(${t.termoSha256}) = 64 AND ${t.termoSha256} NOT GLOB '*[^0-9a-f]*'`,
    ),
  ],
);

/**
 * Revisao de um caso golden por um atestado. APPEND-ONLY.
 *
 * "Nunca remove nem troca quem atestou" e estrutural: o gatilho recusa UPDATE e
 * DELETE. Revisao registrada errada nao se corrige aqui — fica para a issue de
 * revogacao auditada (P0-2, D4).
 *
 * `reviewed_at` e a data em que o PROFISSIONAL revisou (AAAA-MM-DD, do termo);
 * `recorded_at`, quando o operador `recorded_by` a transcreveu. Uma por pessoa
 * por caso: a mesma revisao duas vezes contaria em dobro.
 */
export const goldenCaseReview = sqliteTable(
  'golden_case_review',
  {
    id: text('id').primaryKey(),
    caseId: text('case_id')
      .notNull()
      .references(() => goldenCase.id),
    attestationId: text('attestation_id')
      .notNull()
      .references(() => goldenAttestation.id),
    reviewedAt: text('reviewed_at').notNull(),
    recordedBy: text('recorded_by')
      .notNull()
      .references(() => adminUser.id),
    recordedAt: text('recorded_at').notNull(),
  },
  (t) => [unique('golden_case_review_case_attestation').on(t.caseId, t.attestationId)],
);

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
