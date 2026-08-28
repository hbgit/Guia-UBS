/**
 * As formas de falha da API, como uniao discriminada.
 *
 * O servidor ja distingue os casos com cuidado — 428 e nao 400 quando falta
 * `If-Match`, 409 carregando `versaoAtual`, 422 com TODOS os problemas de uma
 * vez, 200 com `transicionou: false` quando o quorum nao fechou. Traduzir tudo
 * isso para "deu erro" no cliente jogaria fora a informacao que alguem tomou o
 * trabalho de colocar la.
 *
 * Cada variante e tratada onde significa alguma coisa; o mapa esta em `api.ts`.
 */
import type { Permission } from '@guia-ubs/cms/src/auth/permissions.js';

/**
 * Um problema de validacao clinica de regra — o tipo DO SERVIDOR, reexportado.
 *
 * A primeira versao declarava uma copia com `codigo: string`, o que parecia
 * inofensivo e desfazia a cadeia inteira: um codigo novo em `rule-validation.ts`
 * passaria pelo compilador sem tocar em `COMO_RESOLVER`, e a tela mostraria um
 * problema sem explicacao. Agora o `Record` daquele mapa fica incompleto e
 * `tsc -p cms/web` reprova no mesmo PR.
 */
export type { ProblemaDeRegra } from '@guia-ubs/cms/src/services/rule-validation.js';
import type { ProblemaDeRegra } from '@guia-ubs/cms/src/services/rule-validation.js';

export type Falha =
  /** 401 — sessao ausente ou expirada. */
  | { tipo: 'nao_autenticado' }
  /**
   * 403 com `next` — falta cadastrar o segundo fator. O `next` vem do servidor
   * (`/api/auth/two-factor/enable`) e e o unico caminho de saida.
   */
  | { tipo: 'segundo_fator'; next: string }
  /** 403 — a conta foi desligada. Efeito imediato, inclusive em sessao aberta. */
  | { tipo: 'desligado' }
  /** 403 — o papel nao tem a permissao exigida pela rota. */
  | { tipo: 'sem_permissao' }
  /**
   * 403 de outra natureza: auto-aprovacao barrada pelo gatilho, `Origin` ausente.
   * A mensagem do servidor e renderizada LITERAL — ela ja e escrita para humanos.
   */
  | { tipo: 'proibido'; mensagem: string }
  /** 404. */
  | { tipo: 'nao_encontrado' }
  /**
   * 428 — faltou `If-Match`. Inalcancavel pela SPA por construcao (ver `gravar`
   * em `api.ts`); existe na uniao para que um caminho novo que a alcance apareca
   * como caso nao tratado no `switch`, e nao como "erro desconhecido".
   */
  | { tipo: 'precondicao' }
  /** 409 do travamento otimista. Carrega contra o que se perdeu. */
  | { tipo: 'conflito_versao'; versaoAtual: number }
  /**
   * 409 de estado: transicao de FSM invalida, ou regra `approved` que nao se
   * edita. `permitidas` e `next` vem do servidor e dizem o que fazer em vez.
   */
  | {
      tipo: 'conflito_estado';
      mensagem: string;
      atual?: string;
      permitidas?: readonly { para: string; por: readonly string[]; motivo: string }[];
      next?: string;
    }
  /** 409/422 vindos do banco: FK, unicidade. */
  | { tipo: 'integridade'; mensagem: string }
  /** 400 — corpo invalido. `detalhes` sao as issues do zod. */
  | { tipo: 'invalido'; mensagem: string; detalhes?: unknown }
  /** 422 — regra clinicamente invalida, com todos os problemas juntos. */
  | { tipo: 'regra_invalida'; problemas: readonly ProblemaDeRegra[] }
  /**
   * 429 — trava progressiva por conta.
   *
   * A mensagem e do servidor e vai LITERAL para a tela. A LGPD-RT07 e explicita:
   * a resposta nao revela quantas tentativas faltam nem quanto tempo resta —
   * seria um oraculo sobre conta alheia. Portanto nao ha campo de contador aqui,
   * e nao deve haver: o tipo e o lugar certo para tornar isso impossivel.
   */
  | { tipo: 'muitas_tentativas'; mensagem: string }
  /** 5xx ou falha de rede. O servidor ja recusa dizer mais (LGPD-RT01). */
  | { tipo: 'servidor' };

export class ErroApi extends Error {
  constructor(
    readonly falha: Falha,
    readonly status: number,
  ) {
    super(`api: ${falha.tipo} (${status})`);
    this.name = 'ErroApi';
  }
}

/** Uma leitura, com a versao que veio no `ETag`. Ver `gravar` em `api.ts`. */
export interface Lido<T> {
  readonly dados: T;
  readonly versao: number;
}

/** O que `GET /api/me` devolve. */
export interface Operador {
  id: string;
  email: string;
  name: string;
  role: string;
  /**
   * Resolvida pelo servidor a partir de `ROLE_PERMISSIONS`.
   *
   * DESENHA a interface; nunca autoriza. Toda rota tem o seu proprio
   * `requirePermission`, e e ele quem decide.
   */
  permissions: readonly Permission[];
}
