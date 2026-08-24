/**
 * Criacao e gestao de operadores.
 *
 * ## Por que nao passa pelo endpoint de cadastro do Better Auth
 *
 * `disableSignUp: true` fecha `/sign-up/email` — e fecha tambem para chamadas de
 * servidor, porque a checagem mora no handler. Isso e o desejado: um endpoint
 * publico de cadastro num sistema que publica orientacao clinica e uma porta
 * para a rede inteira.
 *
 * A criacao entao e nossa, e escreve as duas linhas que o Better Auth escreveria:
 * o operador e a credencial. Os valores de `providerId`, `accountId` e `issuer`
 * NAO sao inventados aqui — `createLocalAccountIssuer` e a propria funcao da
 * biblioteca.
 *
 * A guarda contra divergencia nao e a inspecao do formato: e um teste que CRIA
 * um operador por esta funcao e depois FAZ LOGIN com ele. Se a forma da
 * credencial mudar numa atualizacao, o login para de funcionar e o teste
 * reprova — que e o unico sinal que importa.
 */
import { randomUUID } from 'node:crypto';

import { createLocalAccountIssuer } from '@better-auth/core/db';
import type { Client } from '@libsql/client';
import { eq } from 'drizzle-orm';

import { hashPassword } from '../auth/password.js';
import type { AdminRole } from '../auth/permissions.js';
import { createDb } from '../db/client.js';
import { account, adminUser } from '../db/schema/auth.js';
import { recordAudit } from './audit.js';

export interface NovoOperador {
  email: string;
  name: string;
  role: AdminRole;
  password: string;
}

export interface OperadorCriado {
  id: string;
  email: string;
  name: string;
  role: AdminRole;
}

export async function createOperator(
  client: Client,
  salt: string,
  dados: NovoOperador,
  atorId: string | null,
): Promise<OperadorCriado> {
  const db = createDb(client);
  const id = randomUUID();
  const agora = new Date();
  const email = dados.email.trim().toLowerCase();

  await db.insert(adminUser).values({
    id,
    name: dados.name,
    email,
    emailVerified: true,
    createdAt: agora,
    updatedAt: agora,
    twoFactorEnabled: false,
    role: dados.role,
  });

  await db.insert(account).values({
    id: randomUUID(),
    issuer: createLocalAccountIssuer('credential'),
    accountId: id,
    providerId: 'credential',
    userId: id,
    password: await hashPassword(dados.password),
    createdAt: agora,
    updatedAt: agora,
  });

  // A trilha registra a criacao SEM a senha e SEM o hash dela: quem audita
  // precisa saber que a conta nasceu, nao conseguir atacar a credencial.
  await recordAudit(client, salt, {
    actorId: atorId,
    action: 'user_create',
    entityType: 'admin_user',
    entityId: id,
    after: { email, role: dados.role },
  });

  return { id, email, name: dados.name, role: dados.role };
}

/**
 * Desliga ou religa um operador.
 *
 * Desligar e carimbar `disabled_at`, nunca DELETE: apagar a linha orfanaria toda
 * a trilha que essa pessoa assinou — e a trilha e append-only justamente para
 * nao sumir.
 */
export async function setOperatorDisabled(
  client: Client,
  salt: string,
  operadorId: string,
  desligado: boolean,
  atorId: string,
): Promise<void> {
  const db = createDb(client);
  const antes = await db.query.adminUser.findFirst({
    where: (t, { eq: igual }) => igual(t.id, operadorId),
  });
  if (!antes) throw new Error('operador nao encontrado');

  const disabledAt = desligado ? new Date() : null;
  await db
    .update(adminUser)
    .set({ disabledAt, updatedAt: new Date() })
    .where(eq(adminUser.id, operadorId));

  await recordAudit(client, salt, {
    actorId: atorId,
    action: desligado ? 'user_disable' : 'user_enable',
    entityType: 'admin_user',
    entityId: operadorId,
    before: { disabledAt: antes.disabledAt },
    after: { disabledAt },
  });
}

/** Troca de papel — a acao mais sensivel da gestao de pessoas, e por isso auditada com antes e depois. */
export async function setOperatorRole(
  client: Client,
  salt: string,
  operadorId: string,
  role: AdminRole,
  atorId: string,
): Promise<void> {
  const db = createDb(client);
  const antes = await db.query.adminUser.findFirst({
    where: (t, { eq: igual }) => igual(t.id, operadorId),
  });
  if (!antes) throw new Error('operador nao encontrado');

  await db.update(adminUser).set({ role, updatedAt: new Date() }).where(eq(adminUser.id, operadorId));

  await recordAudit(client, salt, {
    actorId: atorId,
    action: 'user_role_change',
    entityType: 'admin_user',
    entityId: operadorId,
    before: { role: antes.role },
    after: { role },
  });
}
