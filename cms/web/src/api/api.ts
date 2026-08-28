/**
 * O unico lugar da SPA que fala HTTP.
 *
 * ## Duas regras que nao sao estilo
 *
 * **1. Todo caminho e RELATIVO** (`/api/...`), nunca URL absoluta. E o que torna
 * a requisicao same-origin em producao (SPA e API no mesmo :8787) E atraves do
 * proxy do Vite em desenvolvimento — que e o que faz o navegador mandar um
 * `Origin` que o Better Auth confia. Uma base absoluta configuravel reintroduz,
 * pela porta dos fundos, o 403 de CSRF que o `vite.config.ts` existe para evitar.
 *
 * **2. `Origin` NUNCA e definido aqui.** E nome de cabecalho proibido: o `fetch`
 * o descarta em silencio, e o navegador o preenche sozinho. Codigo que "define o
 * Origin" nao faz nada e ensina que faz.
 *
 * ## O que este modulo nao faz
 *
 * Nao navega. Um embrulho de rede que chama `navigate()` amarra a camada de
 * transporte ao roteador e torna impossivel testar uma sem o outro. Em vez disso
 * ele avisa (`aoPerderSessao`, `aoExigirSegundoFator`) e quem instala o aviso e
 * o `App`.
 *
 * Nao guarda nada. Sessao mora no cookie `httpOnly` — inalcancavel por script, de
 * proposito. Nao ha `localStorage` nesta SPA.
 */
import { ErroApi, type Falha, type Lido, type ProblemaDeRegra } from './erros.js';

// ---------------------------------------------------------------------------
// Avisos de sessao
// ---------------------------------------------------------------------------

let aoPerder: (() => void) | undefined;
let aoExigir2fa: ((next: string) => void) | undefined;

/** Instalado uma vez pelo `App`: leva para `/entrar`. */
export function aoPerderSessao(fn: () => void): void {
  aoPerder = fn;
}

/** Instalado uma vez pelo `App`: leva para o cadastro do segundo fator. */
export function aoExigirSegundoFator(fn: (next: string) => void): void {
  aoExigir2fa = fn;
}

// ---------------------------------------------------------------------------
// Traducao de resposta em falha
// ---------------------------------------------------------------------------

interface CorpoDeErro {
  error?: string;
  next?: string;
  versaoAtual?: number;
  atual?: string;
  permitidas?: readonly { para: string; por: readonly string[]; motivo: string }[];
  problemas?: readonly ProblemaDeRegra[];
  detalhes?: unknown;
}

function classificar(status: number, corpo: CorpoDeErro): Falha {
  const mensagem = corpo.error ?? 'erro';

  if (status === 401) return { tipo: 'nao_autenticado' };

  if (status === 403) {
    // A ordem importa: o 403 de segundo fator e o unico que traz `next`, e e o
    // unico com caminho de saida. Casar por mensagem antes dele faria uma
    // mudanca de texto no servidor virar um usuario trancado do lado de fora.
    if (corpo.next) return { tipo: 'segundo_fator', next: corpo.next };
    if (mensagem === 'operador desligado') return { tipo: 'desligado' };
    if (mensagem === 'sem permissao') return { tipo: 'sem_permissao' };
    return { tipo: 'proibido', mensagem };
  }

  if (status === 404) return { tipo: 'nao_encontrado' };
  if (status === 428) return { tipo: 'precondicao' };

  if (status === 409) {
    if (typeof corpo.versaoAtual === 'number') {
      return { tipo: 'conflito_versao', versaoAtual: corpo.versaoAtual };
    }
    if (corpo.atual !== undefined || corpo.permitidas !== undefined || corpo.next !== undefined) {
      return {
        tipo: 'conflito_estado',
        mensagem,
        ...(corpo.atual !== undefined && { atual: corpo.atual }),
        ...(corpo.permitidas !== undefined && { permitidas: corpo.permitidas }),
        ...(corpo.next !== undefined && { next: corpo.next }),
      };
    }
    return { tipo: 'integridade', mensagem };
  }

  if (status === 422) {
    if (corpo.problemas) return { tipo: 'regra_invalida', problemas: corpo.problemas };
    return { tipo: 'integridade', mensagem };
  }

  if (status === 400) {
    return {
      tipo: 'invalido',
      mensagem,
      ...(corpo.detalhes !== undefined && { detalhes: corpo.detalhes }),
    };
  }

  if (status === 429) return { tipo: 'muitas_tentativas', mensagem };

  return { tipo: 'servidor' };
}

// ---------------------------------------------------------------------------
// Requisicao
// ---------------------------------------------------------------------------

interface Opcoes {
  metodo?: string;
  corpo?: unknown;
  /** So `gravar` preenche, e so a partir de um `Lido`. */
  ifMatch?: number;
}

async function bruto(caminho: string, opcoes: Opcoes = {}): Promise<Response> {
  if (!caminho.startsWith('/')) {
    // Falhar aqui e melhor que descobrir por um 403 de CSRF sem explicacao.
    throw new Error(`caminho precisa ser relativo, comecando com "/": ${caminho}`);
  }

  const cabecalhos: Record<string, string> = {};
  if (opcoes.corpo !== undefined) cabecalhos['content-type'] = 'application/json';
  if (opcoes.ifMatch !== undefined) cabecalhos['if-match'] = `"${opcoes.ifMatch}"`;

  try {
    return await fetch(caminho, {
      method: opcoes.metodo ?? 'GET',
      headers: cabecalhos,
      // O cookie de sessao e `httpOnly` e `sameSite: lax`; sem isto ele nao viaja.
      credentials: 'same-origin',
      ...(opcoes.corpo !== undefined && { body: JSON.stringify(opcoes.corpo) }),
    });
  } catch {
    // Rede fora do ar nao e status HTTP nenhum, e precisa entrar na mesma uniao
    // — senao cada chamador inventa o seu proprio tratamento.
    throw new ErroApi({ tipo: 'servidor' }, 0);
  }
}

async function corpoDeErro(r: Response): Promise<CorpoDeErro> {
  try {
    return (await r.json()) as CorpoDeErro;
  } catch {
    return {};
  }
}

/**
 * Levanta `ErroApi` e dispara os avisos de sessao.
 *
 * Os dois avisos sao efeito colateral de proposito: 401 e o 403 de segundo fator
 * podem acontecer em QUALQUER chamada, e exigir que cada tela lembre de trata-los
 * garante que uma vai esquecer — e o sintoma seria uma tela em branco depois da
 * sessao expirar.
 */
async function conferir(r: Response): Promise<Response> {
  if (r.ok) return r;
  const falha = classificar(r.status, await corpoDeErro(r));
  if (falha.tipo === 'nao_autenticado') aoPerder?.();
  if (falha.tipo === 'segundo_fator') aoExigir2fa?.(falha.next);
  throw new ErroApi(falha, r.status);
}

function versaoDoEtag(r: Response): number {
  // `W/"3"` e `"3"` — o servidor emite a segunda forma; aceitar as duas custa
  // uma expressao e evita um NaN silencioso se isso mudar.
  const bruta = r.headers.get('etag')?.replace(/^W\//, '').replace(/"/g, '') ?? '';
  const n = Number.parseInt(bruta, 10);
  return Number.isInteger(n) && n > 0 ? n : 0;
}

// ---------------------------------------------------------------------------
// Superficie publica
// ---------------------------------------------------------------------------

/** GET simples, sem versao. Para colecoes e para `/api/me`. */
export async function buscar<T>(caminho: string): Promise<T> {
  const r = await conferir(await bruto(caminho));
  return (await r.json()) as T;
}

/**
 * GET de uma LINHA, capturando o `ETag`.
 *
 * E o unico produtor de `Lido`, e e isso que torna o 428 inalcancavel: ver
 * `gravar`.
 */
export async function ler<T>(caminho: string): Promise<Lido<T>> {
  const r = await conferir(await bruto(caminho));
  return { dados: (await r.json()) as T, versao: versaoDoEtag(r) };
}

/** POST de criacao. Devolve o corpo da resposta como veio. */
export async function criar<T>(caminho: string, corpo: unknown): Promise<T> {
  const r = await conferir(await bruto(caminho, { metodo: 'POST', corpo }));
  return (await r.json()) as T;
}

/**
 * PATCH com travamento otimista. Devolve a versao NOVA.
 *
 * O `Lido` e o PRIMEIRO parametro posicional, e nao um `ifMatch` opcional no
 * fim. `Lido.versao` e `number`, nao `number | null`, e o unico jeito de obter um
 * `Lido` e chamando `ler`. Portanto um PATCH construido a partir de qualquer
 * outra coisa **nao compila**, e o 428 fica inalcancavel pela SPA por construcao
 * — que e o objetivo. Um cabecalho opcional seria um cabecalho que alguem
 * esquece, e o sintoma e um 428 que o operador nao tem como interpretar.
 */
export async function gravar(
  lido: Lido<unknown>,
  caminho: string,
  corpo: unknown,
): Promise<number> {
  const r = await conferir(await bruto(caminho, { metodo: 'PATCH', corpo, ifMatch: lido.versao }));
  const nova = versaoDoEtag(r);
  if (nova > 0) return nova;
  // O corpo do PATCH e `{ok, versao}` — nao a linha. Cair aqui significa que o
  // `ETag` sumiu da resposta, e adivinhar `lido.versao + 1` esconderia isso.
  const corpoResposta = (await r.json()) as { versao?: number };
  return corpoResposta.versao ?? lido.versao + 1;
}

/** DELETE. Responde 204 sem corpo. */
export async function remover(caminho: string): Promise<void> {
  await conferir(await bruto(caminho, { metodo: 'DELETE' }));
}

/**
 * POST que aciona alguma coisa e nao cria linha: `/submeter`, `/api/approvals`,
 * `/api/rules/simular`, o fluxo do Better Auth.
 */
export async function acionar<T>(caminho: string, corpo?: unknown): Promise<T> {
  const r = await conferir(await bruto(caminho, { metodo: 'POST', corpo }));
  if (r.status === 204) return undefined as T;
  return (await r.json()) as T;
}

/**
 * Como `acionar`, mas devolve a Response inteira SEM levantar em 4xx.
 *
 * Existe para o fluxo de entrada, que precisa distinguir 200, 429 e 4xx generico
 * ANTES de haver sessao — e onde um 401 nao deve disparar o aviso de "sessao
 * perdida", porque nunca houve sessao. Fora da entrada, use `acionar`.
 */
export async function tentar(caminho: string, corpo?: unknown): Promise<Response> {
  return bruto(caminho, { metodo: 'POST', corpo });
}

/**
 * GET que devolve a Response crua, sem levantar e sem disparar os avisos.
 *
 * Existe por um motivo so, e ele e sutil: durante a entrada, um `401` em
 * `/api/me` NAO significa "sessao perdida" — significa que o cookie que o
 * `sign-in` devolveu e o de 2FA pendente, e o passo seguinte e pedir o codigo.
 * Passar por `buscar` dispararia `aoPerderSessao` e jogaria a pessoa de volta
 * para `/entrar`, num laco que so termina quando alguem desiste.
 */
export async function sondar(caminho: string): Promise<Response> {
  return bruto(caminho);
}

export { ErroApi };
export type { Falha, Lido, ProblemaDeRegra };
