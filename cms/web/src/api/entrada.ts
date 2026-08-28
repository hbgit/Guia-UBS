/**
 * A ramificacao da entrada, isolada da tela para poder ser testada sozinha.
 *
 * ## Por que o ramo e decidido pelo STATUS de `/api/me`
 *
 * O `sign-in` do Better Auth devolve um corpo com dicas (`twoFactorRedirect`),
 * mas nada neste repositorio afirma o formato dele — enquanto os TRES status de
 * `/api/me` tem teste (`auth-flow.test.ts`). Usar o que ja esta garantido custa
 * uma requisicao a mais e nao quebra numa atualizacao da biblioteca.
 *
 * ```
 * POST /api/auth/sign-in/email
 *   ├─ 429 → mensagem LITERAL do servidor. Sem contador, sem relogio (LGPD-RT07)
 *   ├─ 4xx → "e-mail ou senha invalidos" (generica, LGPD-RT01)
 *   └─ 200 → GET /api/me
 *        ├─ 200  → sessao completa                        → painel
 *        ├─ 401  → o cookie e o de 2FA PENDENTE (600 s)   → pedir o codigo
 *        └─ 403  → primeira entrada, falta cadastrar      → cadastrar o 2o fator
 * ```
 *
 * O 401 do meio e o passo que engana: parece "nao autenticado" e e, na verdade,
 * "autenticado pela metade". Ver `sondar` em `api.ts`.
 */
import { sondar, tentar } from './api.js';
import type { Operador } from './erros.js';

export type EstadoDaEntrada =
  | { estado: 'completa'; operador: Operador }
  | { estado: 'pendente_codigo' }
  | { estado: 'precisa_cadastrar'; next: string }
  /** Trava progressiva por conta. `mensagem` vai LITERAL para a tela. */
  | { estado: 'travada'; mensagem: string }
  | { estado: 'recusada' };

/**
 * Mensagem generica, sempre a mesma.
 *
 * Distinguir "e-mail nao existe" de "senha errada" transformaria a tela num
 * verificador de contas alheias. O servidor ja nao distingue; a tela tambem nao.
 */
export const CREDENCIAL_INVALIDA = 'E-mail ou senha invalidos.';

/** Le a mensagem de 429 venha ela da nossa trava (`error`) ou do Better Auth (`message`). */
async function mensagemDeTrava(r: Response): Promise<string> {
  try {
    const corpo = (await r.json()) as { error?: string; message?: string };
    return corpo.error ?? corpo.message ?? 'Muitas tentativas; tente mais tarde.';
  } catch {
    return 'Muitas tentativas; tente mais tarde.';
  }
}

/** Onde a sessao atual esta no fluxo. Usada depois do `sign-in` e do `verify-totp`. */
export async function estadoDaSessao(): Promise<EstadoDaEntrada> {
  const r = await sondar('/api/me');

  if (r.ok) return { estado: 'completa', operador: (await r.json()) as Operador };

  if (r.status === 403) {
    const corpo = (await r.json().catch(() => ({}))) as { next?: string };
    // O `next` vem do servidor. Fixar o caminho aqui criaria uma segunda copia
    // de uma decisao que ja e do middleware.
    return { estado: 'precisa_cadastrar', next: corpo.next ?? '/api/auth/two-factor/enable' };
  }

  // 401: cookie de 2FA pendente. Nao e sessao perdida.
  return { estado: 'pendente_codigo' };
}

export async function entrar(email: string, senha: string): Promise<EstadoDaEntrada> {
  const r = await tentar('/api/auth/sign-in/email', { email, password: senha });

  if (r.status === 429) return { estado: 'travada', mensagem: await mensagemDeTrava(r) };
  if (!r.ok) return { estado: 'recusada' };

  return estadoDaSessao();
}

export async function conferirCodigo(codigo: string): Promise<EstadoDaEntrada> {
  const r = await tentar('/api/auth/two-factor/verify-totp', { code: codigo });

  if (r.status === 429) return { estado: 'travada', mensagem: await mensagemDeTrava(r) };
  if (!r.ok) return { estado: 'recusada' };

  return estadoDaSessao();
}
