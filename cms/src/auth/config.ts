/**
 * Better Auth: mapeamento, sessao, 2FA e as recusas que a LGPD exige.
 *
 * O modelo `user` da biblioteca aponta para a tabela `admin_user`, e nao para
 * uma tabela `user` propria. Assim `audit_entry.actor_id`,
 * `approval.approver_id` e todo `updated_by` continuam apontando para uma linha
 * so — "quem e o autor disto?" nao pode ter duas respostas possiveis.
 */
import type { Client } from '@libsql/client';
import { betterAuth } from 'better-auth';
import { drizzleAdapter } from 'better-auth/adapters/drizzle';
import { twoFactor as twoFactorPlugin } from 'better-auth/plugins';

import { createDb } from '../db/client.js';
import { hashPassword, verifyPassword } from './password.js';
import type { Env } from '../env.js';
import {
  account,
  adminUser,
  session,
  twoFactor as twoFactorTable,
  verification,
} from '../db/schema/auth.js';

/** Sessao <= 24 h (lgpd.md LGPD-RT07). Nao e ajuste de conforto: e o requisito. */
export const SESSION_MAX_AGE_SECONDS = 60 * 60 * 24;

/**
 * Senha minima de 12 caracteres para operador.
 *
 * O padrao da biblioteca sao 8. Quem tem essa conta publica orientacao clinica
 * para uma rede inteira de postos; 8 caracteres com Argon2id ainda cai em ataque
 * de dicionario dirigido.
 */
export const MIN_PASSWORD_LENGTH = 12;

export type Auth = ReturnType<typeof createAuth>;

export interface AuthOptions {
  client: Client;
  env: Env;
  /**
   * Rate limit por endpoint. **Ligado por padrao.**
   *
   * Existe como parametro porque uma suite de testes faz dezenas de logins em
   * segundos e bateria no teto de 5/60s, transformando cada teste seguinte num
   * falso vermelho. Desligar e privilegio do teste, e `auth-flow.test.ts` afirma
   * que o padrao e ligado — senao a excecao viraria o comportamento normal sem
   * ninguem decidir isso.
   *
   * Desligar aqui NAO desliga a trava progressiva por conta (`lockout.ts`), que
   * e a protecao que a LGPD-RT07 exige e continua valendo nos testes.
   */
  rateLimit?: boolean;
}

export function createAuth({ client, env, rateLimit = true }: AuthOptions) {
  const db = createDb(client);

  return betterAuth({
    appName: 'Guia UBS',
    secret: env.authSecret,
    baseURL: env.authBaseUrl,

    database: drizzleAdapter(db, {
      provider: 'sqlite',
      // Chaveado pelo NOME DE MODELO do Better Auth, nao pelo nome do export.
      schema: {
        admin_user: adminUser,
        session,
        account,
        verification,
        two_factor: twoFactorTable,
      },
    }),

    user: {
      modelName: 'admin_user',
      additionalFields: {
        role: { type: 'string', required: true, input: false },
        disabledAt: { type: 'date', required: false, input: false },
      },
    },

    emailAndPassword: {
      enabled: true,
      /**
       * **Sem autocadastro.** Operador e criado por um admin, pela rota
       * auditada de `routes/users.ts`. Um endpoint publico de cadastro num
       * sistema que publica orientacao clinica e uma porta para a rede inteira;
       * e a LGPD-RF11 fala em contas nominais concedidas, nao solicitadas.
       */
      disableSignUp: true,
      minPasswordLength: MIN_PASSWORD_LENGTH,
      /** Argon2id (LGPD-RT06) no lugar do scrypt padrao — ver `password.ts`. */
      password: { hash: hashPassword, verify: verifyPassword },
    },

    session: {
      expiresIn: SESSION_MAX_AGE_SECONDS,
      /** Renova o carimbo no maximo de hora em hora, para nao escrever a cada request. */
      updateAge: 60 * 60,
    },

    /**
     * TOTP com segredo e codigos de recuperacao CIFRADOS em repouso pelo proprio
     * plugin, sob o `BETTER_AUTH_SECRET`.
     */
    plugins: [
      twoFactorPlugin({
        issuer: 'Guia UBS',
        /**
         * Sem isto o modelo se chamaria `twoFactor` e o adapter procuraria
         * `schema.twoFactor` — que nao existe, porque a tabela segue o
         * snake_case do resto do banco. Quebraria no primeiro uso da 2FA, nao
         * no boot.
         */
        twoFactorTable: 'two_factor',
      }),
    ],

    /**
     * Rate limit por endpoint — camada COMPLEMENTAR, nao a principal.
     *
     * Ele e janela fixa por caminho: quem distribui as tentativas entre varios
     * IPs passa por baixo. O bloqueio progressivo por CONTA que a LGPD-RT07 pede
     * esta em `lockout.ts`.
     */
    rateLimit: {
      enabled: rateLimit,
      window: 60,
      max: 60,
      customRules: {
        '/sign-in/email': { window: 60, max: 5 },
        '/two-factor/verify-totp': { window: 60, max: 5 },
      },
    },

    databaseHooks: {
      session: {
        create: {
          /**
           * Operador desligado nao abre sessao.
           *
           * `disabled_at` e carimbo em vez de DELETE justamente para nao orfanar
           * a trilha de auditoria — mas carimbo sem enforcement e so um campo.
           * A recusa mora aqui, no ponto por onde TODA sessao passa, e nao em
           * cada rota.
           */
          before: async (dados) => {
            const usuario = await db.query.adminUser.findFirst({
              where: (t, { eq }) => eq(t.id, dados.userId),
            });
            if (usuario?.disabledAt) {
              throw new Error('operador desligado');
            }
            return { data: dados };
          },
        },
      },
    },
  });
}
