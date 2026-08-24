/**
 * Guardas de rota: sessao, 2FA obrigatoria, permissao — e a trilha do que passa
 * pelo `/api/auth/*`.
 */
import type { Client } from '@libsql/client';
import type { MiddlewareHandler } from 'hono';

import { createDb } from '../db/client.js';
import { recordAudit } from '../services/audit.js';
import type { Auth } from './config.js';
import { isLocked, clearFailures, readLockout, registerFailure } from './lockout.js';
import { can, isAdminRole, type Permission } from './permissions.js';
import { subjectKey } from './pseudonymize.js';

export interface OperadorSessao {
  id: string;
  email: string;
  name: string;
  role: string;
  twoFactorEnabled: boolean;
  disabledAt: Date | null;
}

export type AuthVariables = { operador: OperadorSessao };

/** Rotas do proprio fluxo de 2FA — a excecao nomeada de `require2fa`. */
const ROTAS_DE_CADASTRO_2FA = ['/api/auth/two-factor/enable', '/api/auth/two-factor/verify-totp'];

/**
 * Exige sessao valida e operador ativo.
 *
 * A checagem de `disabledAt` e redundante com o hook de `config.ts`, e e
 * deliberada: aquele impede ABRIR sessao, este impede USAR uma sessao aberta
 * antes do desligamento. Sem o segundo, desligar alguem so faria efeito quando o
 * cookie dela expirasse — ate 24 h depois.
 */
export function requireSession(auth: Auth): MiddlewareHandler<{ Variables: AuthVariables }> {
  return async (c, next) => {
    const sessao = await auth.api.getSession({ headers: c.req.raw.headers });
    if (!sessao?.user) return c.json({ error: 'nao autenticado' }, 401);

    const usuario = sessao.user as unknown as OperadorSessao;
    if (usuario.disabledAt) return c.json({ error: 'operador desligado' }, 403);

    c.set('operador', usuario);
    await next();
  };
}

/**
 * 2FA e OBRIGATORIA (lgpd.md LGPD-RF11), e o Better Auth a trata como opt-in.
 *
 * A obrigacao vira este middleware. A excecao e o proprio fluxo de cadastro do
 * TOTP — sem ela, ninguem consegue ativar o que e obrigatorio ter ativado, e o
 * sistema tranca todo mundo do lado de fora no primeiro login.
 */
export function require2fa(): MiddlewareHandler<{ Variables: AuthVariables }> {
  return async (c, next) => {
    const operador = c.get('operador');
    if (!operador.twoFactorEnabled) {
      return c.json(
        { error: 'segundo fator obrigatorio', next: '/api/auth/two-factor/enable' },
        403,
      );
    }
    await next();
  };
}

export function requirePermission(
  permission: Permission,
): MiddlewareHandler<{ Variables: AuthVariables }> {
  return async (c, next) => {
    const { role } = c.get('operador');
    if (!isAdminRole(role) || !can(role, permission)) {
      return c.json({ error: 'sem permissao' }, 403);
    }
    await next();
  };
}

/** Caminho -> verbo da trilha. Fora deste mapa, nada e registrado. */
const ACOES: Readonly<Record<string, string>> = {
  '/api/auth/sign-in/email': 'sign_in',
  '/api/auth/sign-out': 'sign_out',
  '/api/auth/two-factor/enable': 'two_factor_enable',
  '/api/auth/two-factor/disable': 'two_factor_disable',
  '/api/auth/two-factor/verify-totp': 'two_factor_verify',
  '/api/auth/change-password': 'change_password',
};

/** Primeiro IP do `X-Forwarded-For` — o Caddy da borda o preenche. */
function clientIp(c: { req: { header: (n: string) => string | undefined } }): string | null {
  const encaminhado = c.req.header('x-forwarded-for');
  return encaminhado?.split(',')[0]?.trim() ?? null;
}

/**
 * Le o e-mail do corpo SEM consumi-lo, so para derivar a chave da trava.
 *
 * O corpo e clonado porque o handler do Better Auth precisa le-lo depois. O
 * e-mail nao e guardado em lugar nenhum: vira `subjectKey` na linha seguinte.
 */
async function emailDoCorpo(request: Request): Promise<string | null> {
  try {
    const corpo = (await request.clone().json()) as { email?: unknown };
    return typeof corpo.email === 'string' && corpo.email.length > 0 ? corpo.email : null;
  } catch {
    return null;
  }
}

/**
 * Quem agiu, para as rotas de autenticacao.
 *
 * Estas rotas NAO passam por `requireSession`, entao `c.get('operador')` esta
 * vazio ali — e o primeiro roteiro contra o `sqld` real mostrou o efeito disso:
 * `sign_in` e `two_factor_enable` bem-sucedidos entravam na trilha com ator
 * nulo. "Quem ativou o segundo fator?" ficaria sem resposta, que e exatamente a
 * pergunta que uma auditoria de acesso faz.
 *
 * Dois caminhos, porque a informacao chega de formas diferentes:
 *
 *   - Requisicao que JA traz sessao (ativar 2FA, sair, trocar senha): a sessao
 *     responde.
 *   - Login: a sessao so nasce na RESPOSTA, entao o ator vem de uma busca pelo
 *     e-mail que o corpo trouxe. Login recusado nao resolve ator de proposito —
 *     atribuir a tentativa a conta visada afirmaria que a pessoa agiu, quando
 *     pode ter sido um ataque contra ela.
 */
async function resolveAtor({
  auth,
  client,
  request,
  email,
  falhou,
}: {
  auth: Auth;
  client: Client;
  request: Request;
  email: string | null;
  falhou: boolean;
}): Promise<string | null> {
  if (falhou) return null;

  const sessao = await auth.api.getSession({ headers: request.headers }).catch(() => null);
  if (sessao?.user?.id) return sessao.user.id;

  if (!email) return null;
  const db = createDb(client);
  const operador = await db.query.adminUser.findFirst({
    where: (t, { eq }) => eq(t.email, email.trim().toLowerCase()),
    columns: { id: true },
  });
  return operador?.id ?? null;
}

/**
 * Trava progressiva + trilha, em volta do `/api/auth/*`.
 *
 * Envolver o handler em vez de usar os hooks internos do Better Auth e
 * deliberado: assim login com sucesso, login recusado, logout e ativacao de 2FA
 * sao tratados do mesmo jeito, por caminho e status, sem depender de quais
 * hooks esta versao da biblioteca expoe.
 *
 * **O corpo nunca e registrado** — ele carrega senha e codigo TOTP. O que entra
 * na trilha e caminho, resultado, ator e entidade.
 */
export function auditAndThrottleAuth(
  auth: Auth,
  client: Client,
  salt: string,
): MiddlewareHandler<{ Variables: AuthVariables }> {
  return async (c, next) => {
    const caminho = new URL(c.req.url).pathname;
    const acao = ACOES[caminho];
    const ehLogin = caminho === '/api/auth/sign-in/email';

    // O e-mail vive apenas nesta variavel, pelo tempo da requisicao: serve para
    // a chave da trava e para resolver QUEM entrou. Nao e gravado em lugar
    // nenhum — o que vai para o banco e sempre o hash.
    const email = ehLogin ? await emailDoCorpo(c.req.raw) : null;
    const chave = email ? subjectKey(email, salt) : null;

    if (chave) {
      const estado = await readLockout(client, chave);
      if (isLocked(estado)) {
        await recordAudit(client, salt, {
          actorId: null,
          action: 'sign_in_locked',
          entityType: 'login_attempt',
          entityId: chave,
          ip: clientIp(c),
        });
        // A resposta nao diz por quanto tempo nem quantas faltam: seria um
        // oraculo sobre o estado de uma conta para quem nao a possui.
        return c.json({ error: 'muitas tentativas; tente mais tarde' }, 429);
      }
    }

    await next();

    const falhou = c.res.status >= 400;
    if (chave) {
      if (falhou) await registerFailure(client, chave);
      else await clearFailures(client, chave);
    }

    if (!acao) return;
    await recordAudit(client, salt, {
      actorId: await resolveAtor({ auth, client, request: c.req.raw, email, falhou }),
      action: falhou ? `${acao}_failed` : acao,
      entityType: ehLogin ? 'login_attempt' : 'session',
      entityId: chave ?? 'sessao',
      after: { status: c.res.status },
      ip: clientIp(c),
    });
  };
}
