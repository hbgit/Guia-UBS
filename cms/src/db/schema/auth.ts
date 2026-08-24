/**
 * Identidade dos operadores do plano de controle (arquitetura.md 4.3-A).
 *
 * ESCOPO DESTE ITEM: apenas `admin_user`, que e tabela nossa e o alvo das FKs
 * de `audit_entry`, `approval` e de toda coluna `updated_by`. As tabelas de
 * sessao do Better Auth (`session`, `account`, `verification`) entram no item
 * 17, geradas pelo CLI dele — escreve-las a mao agora seria adivinhar o schema
 * de outra ferramenta e corrigi-lo uma semana depois.
 */
import { sql } from 'drizzle-orm';
import { check, sqliteTable, text } from 'drizzle-orm/sqlite-core';

/** RBAC de tres papeis (lgpd.md LGPD-RF11). O item 17 monta a matriz sobre esta lista. */
export const ADMIN_ROLES = ['editor', 'clinical_reviewer', 'admin'] as const;

export const adminUser = sqliteTable(
  'admin_user',
  {
    id: text('id').primaryKey(),
    /** PII. */
    email: text('email').notNull().unique(),
    /** PII. */
    name: text('name').notNull(),
    /** Argon2id (lgpd.md LGPD-RT06). PII: hash de credencial. */
    passwordHash: text('password_hash').notNull(),
    role: text('role', { enum: ADMIN_ROLES }).notNull(),
    /** Segredo TOTP cifrado em repouso; 2FA e obrigatorio (LGPD-RT07). PII. */
    totpSecretEnc: text('totp_secret_enc'),
    /**
     * Desligamento e carimbo, nao DELETE.
     *
     * Apagar a linha orfanaria toda a trilha de auditoria que esta pessoa
     * assinou — e essa trilha e append-only justamente para nao sumir. Um
     * operador desligado precisa continuar sendo o autor do que aprovou.
     */
    disabledAt: text('disabled_at'),
    createdAt: text('created_at').notNull(),
  },
  (t) => [
    // O `enum` do drizzle e tipagem so de TypeScript: nao emite CHECK nenhum no
    // DDL. Aqui um papel invalido e escalada de privilegio, entao a restricao
    // precisa existir no banco e nao apenas no compilador.
    check('admin_user_role_valid', sql`${t.role} IN ('editor', 'clinical_reviewer', 'admin')`),
  ],
);
