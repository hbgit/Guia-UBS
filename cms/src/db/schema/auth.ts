/**
 * Identidade e autenticacao dos operadores do plano de controle
 * (arquitetura.md 4.3-A).
 *
 * ## A forma destas tabelas NAO e escolha nossa
 *
 * O Better Auth exige um conjunto de modelos com campos exatos. Este arquivo os
 * escreve a mao para poder anotar cada um, mas a forma vem da biblioteca — e
 * `test/auth-schema-conformance.test.ts` compara os dois, campo a campo, contra
 * o que `getAuthTables()` declara em RUNTIME. Atualizacao do Better Auth que
 * acrescente coluna reprova no CI, e nao no primeiro login em producao.
 *
 * O modelo `user` da biblioteca e MAPEADO para `admin_user`, em vez de criar uma
 * segunda tabela de identidade. Assim `audit_entry.actor_id`,
 * `approval.approver_id` e todo `updated_by` continuam apontando para uma linha
 * so — "quem e o autor disto?" nao pode ter duas respostas possiveis.
 *
 * ## Uma quebra de convencao, forcada e declarada
 *
 * O resto do banco usa `*_at` em ISO-8601 UTC como TEXT. Aqui os carimbos sao
 * `integer({ mode: 'timestamp_ms' })`: o Better Auth passa objetos `Date` ao
 * adapter, e o Drizzle so converte `Date` em coluna INTEGER. Forcar TEXT exigiria
 * um tipo de coluna customizado no caminho de autenticacao — fragil, e no lugar
 * errado. As tabelas NOSSAS (`audit_entry`, `login_attempt`, conteudo,
 * publicacao) seguem TEXT como sempre.
 */
import { sql } from 'drizzle-orm';
import { check, index, integer, sqliteTable, text, uniqueIndex } from 'drizzle-orm/sqlite-core';

/** RBAC de tres papeis (lgpd.md LGPD-RF11). `auth/permissions.ts` monta a matriz sobre esta lista. */
export const ADMIN_ROLES = ['editor', 'clinical_reviewer', 'admin'] as const;

// ---------------------------------------------------------------------------
// Identidade — o modelo `user` do Better Auth
// ---------------------------------------------------------------------------

export const adminUser = sqliteTable(
  'admin_user',
  {
    id: text('id').primaryKey(),
    /** PII. */
    name: text('name').notNull(),
    /** PII. E o identificador de login. */
    email: text('email').notNull().unique(),
    emailVerified: integer('email_verified', { mode: 'boolean' }).notNull().default(false),
    /**
     * PII (URL de foto). Exigida pelo core do Better Auth; NENHUMA rota nossa a
     * escreve. Esta declarada em `PII_COLUMNS` com esta justificativa porque
     * coluna de dado pessoal sem justificativa escrita e o que a LGPD-RT02
     * proibe — e "existe mas ninguem usa" so vale se estiver escrito.
     */
    image: text('image'),
    createdAt: integer('created_at', { mode: 'timestamp_ms' }).notNull(),
    updatedAt: integer('updated_at', { mode: 'timestamp_ms' }).notNull(),
    /**
     * Ligado pelo plugin `two-factor` quando a pessoa cadastra o TOTP.
     *
     * A LGPD-RF11 exige 2FA OBRIGATORIO, e o Better Auth trata como opt-in. Quem
     * transforma este campo em obrigacao e `auth/middleware.ts`: sessao com
     * `false` nao alcanca rota protegida nenhuma, exceto o proprio cadastro.
     */
    twoFactorEnabled: integer('two_factor_enabled', { mode: 'boolean' }).default(false),

    // --- campos nossos, declarados ao Better Auth como additionalFields ---
    role: text('role', { enum: ADMIN_ROLES }).notNull(),
    /**
     * Desligamento e carimbo, nao DELETE.
     *
     * Apagar a linha orfanaria toda a trilha de auditoria que esta pessoa
     * assinou — e essa trilha e append-only justamente para nao sumir. Um
     * operador desligado precisa continuar sendo o autor do que aprovou.
     */
    disabledAt: integer('disabled_at', { mode: 'timestamp_ms' }),
  },
  (t) => [
    // O `enum` do drizzle e tipagem so de TypeScript: nao emite CHECK nenhum no
    // DDL. Aqui um papel invalido e escalada de privilegio, entao a restricao
    // precisa existir no banco e nao apenas no compilador.
    check('admin_user_role_valid', sql`${t.role} IN ('editor', 'clinical_reviewer', 'admin')`),
  ],
);

// ---------------------------------------------------------------------------
// Sessao, credencial e verificacao — do Better Auth
// ---------------------------------------------------------------------------

/**
 * Sessao ativa. Expiracao <= 24 h (lgpd.md LGPD-RT07), configurada em
 * `auth/config.ts`; aqui so o armazenamento.
 *
 * `ip_address` e `user_agent` sao preenchidos pelo Better Auth e sao PII — mas
 * de sessao VIVA, apagada no logout e na expiracao. A trilha permanente
 * (`audit_entry`) guarda o IP apenas HASHEADO. Sao coisas diferentes de
 * proposito: a sessao precisa do IP para detectar roubo de cookie; a trilha, nao.
 */
export const session = sqliteTable(
  'session',
  {
    id: text('id').primaryKey(),
    expiresAt: integer('expires_at', { mode: 'timestamp_ms' }).notNull(),
    token: text('token').notNull().unique(),
    createdAt: integer('created_at', { mode: 'timestamp_ms' }).notNull(),
    updatedAt: integer('updated_at', { mode: 'timestamp_ms' }).notNull(),
    /** PII de sessao viva. */
    ipAddress: text('ip_address'),
    userAgent: text('user_agent'),
    userId: text('user_id')
      .notNull()
      .references(() => adminUser.id, { onDelete: 'cascade' }),
  },
  (t) => [index('session_user_idx').on(t.userId)],
);

/**
 * Credencial. **E aqui que mora o hash da senha** — nao em `admin_user`.
 *
 * `password` recebe Argon2id (lgpd.md LGPD-RT06) via o hasher de
 * `auth/password.ts`, que substitui o padrao da biblioteca.
 *
 * As colunas de OAuth (`access_token`, `refresh_token`, `id_token`, `scope`)
 * existem porque o core as exige e ficam sempre nulas: nao ha provedor social
 * configurado, e nao deve haver — login de operador municipal por conta do
 * Google poria a cadeia de conteudo clinico atras de um fornecedor externo.
 */
export const account = sqliteTable(
  'account',
  {
    id: text('id').primaryKey(),
    issuer: text('issuer').notNull(),
    accountId: text('account_id').notNull(),
    providerId: text('provider_id').notNull(),
    userId: text('user_id')
      .notNull()
      .references(() => adminUser.id, { onDelete: 'cascade' }),
    accessToken: text('access_token'),
    refreshToken: text('refresh_token'),
    idToken: text('id_token'),
    accessTokenExpiresAt: integer('access_token_expires_at', { mode: 'timestamp_ms' }),
    refreshTokenExpiresAt: integer('refresh_token_expires_at', { mode: 'timestamp_ms' }),
    scope: text('scope'),
    /** PII: hash de credencial (Argon2id). */
    password: text('password'),
    createdAt: integer('created_at', { mode: 'timestamp_ms' }).notNull(),
    updatedAt: integer('updated_at', { mode: 'timestamp_ms' }).notNull(),
  },
  (t) => [
    uniqueIndex('account_issuer_account_uidx').on(t.issuer, t.accountId),
    index('account_user_idx').on(t.userId),
  ],
);

/** Tokens de verificacao de curta duracao (troca de senha, e-mail). */
export const verification = sqliteTable(
  'verification',
  {
    id: text('id').primaryKey(),
    identifier: text('identifier').notNull(),
    value: text('value').notNull(),
    expiresAt: integer('expires_at', { mode: 'timestamp_ms' }).notNull(),
    createdAt: integer('created_at', { mode: 'timestamp_ms' }).notNull(),
    updatedAt: integer('updated_at', { mode: 'timestamp_ms' }).notNull(),
  },
  (t) => [index('verification_identifier_idx').on(t.identifier)],
);

/**
 * Segundo fator TOTP.
 *
 * `secret` e `backup_codes` chegam **ja cifrados** pelo plugin, com
 * `symmetricEncrypt` sob o `BETTER_AUTH_SECRET` — e por isso o item 16 nao
 * precisou de `admin_user.totp_secret_enc`: a coluna teria ficado vazia para
 * sempre, prometendo no nome uma criptografia que estava em outro lugar.
 *
 * `failed_verification_count` e `locked_until` sao do plugin e travam a
 * forca bruta **do CODIGO TOTP**. Nao cobrem forca bruta de SENHA — essa e a
 * `login_attempt` logo abaixo.
 */
export const twoFactor = sqliteTable(
  'two_factor',
  {
    id: text('id').primaryKey(),
    /** PII: segredo de credencial, cifrado em repouso pelo plugin. */
    secret: text('secret').notNull(),
    /** PII: codigos de recuperacao, cifrados em repouso pelo plugin. */
    backupCodes: text('backup_codes').notNull(),
    userId: text('user_id')
      .notNull()
      .references(() => adminUser.id, { onDelete: 'cascade' }),
    verified: integer('verified', { mode: 'boolean' }).default(true),
    failedVerificationCount: integer('failed_verification_count').default(0),
    lockedUntil: integer('locked_until', { mode: 'timestamp_ms' }),
  },
  (t) => [index('two_factor_user_idx').on(t.userId)],
);

// ---------------------------------------------------------------------------
// Trava progressiva de senha — tabela NOSSA (lgpd.md LGPD-RT07)
// ---------------------------------------------------------------------------

/**
 * Bloqueio progressivo por CONTA.
 *
 * O rate limit embutido do Better Auth e janela fixa por ENDPOINT: quem
 * distribui as tentativas entre varios IPs passa por baixo dele. A LGPD-RT07
 * pede bloqueio **progressivo**, e progressivo so faz sentido contra o alvo —
 * a conta —, nao contra a origem.
 *
 * `subject_key` e o e-mail HASHEADO com o mesmo sal do `ip_hash`. Guardar o
 * e-mail em claro aqui transformaria a tabela numa lista de quem tem conta no
 * sistema, legivel por qualquer um com acesso de leitura ao banco. PII
 * pseudonimizada.
 *
 * NAO e append-only, ao contrario da trilha: o valor dela esta no estado ATUAL,
 * e a linha e zerada a cada sucesso. O registro historico das tentativas e o
 * `audit_entry`, que e append-only por gatilho.
 *
 * Carimbos em TEXT ISO-8601: esta tabela e nossa, o Better Auth nao a toca.
 */
export const loginAttempt = sqliteTable(
  'login_attempt',
  {
    /** PII pseudonimizada: sha256(email + sal). */
    subjectKey: text('subject_key').primaryKey(),
    failures: integer('failures').notNull().default(0),
    lastFailureAt: text('last_failure_at'),
    lockedUntil: text('locked_until'),
  },
  (t) => [check('login_attempt_failures_positive', sql`${t.failures} >= 0`)],
);
