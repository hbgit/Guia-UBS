/**
 * As telas da interface, como DADO.
 *
 * Mesmo padrao de `TRANSICOES` e `CONTENT_ENTITIES` no servidor, e pelo mesmo
 * motivo: uma lista que um teste consegue percorrer. `cms/test/doc-operacao.test.ts`
 * exige que toda tela daqui apareca em `docs/operacao.md` — tela nova sem linha
 * no manual e tela que ninguem sabe que existe.
 *
 * ## Este arquivo nao pode importar React nem tocar o DOM
 *
 * Ele e importado por um teste `node:test` em `cms/test/`, e `tsc -p cms` roda
 * com `types: ["node"]` e sem lib de DOM. Um `import` de componente aqui quebra o
 * typecheck do workspace do servidor — o que e chato, mas e a consequencia certa:
 * a lista de telas e dado, e o mapeamento tela -> componente mora no `App`.
 */
import type { Permission } from '@guia-ubs/cms/src/auth/permissions.js';

export interface Rota {
  /** Caminho no react-router. */
  caminho: string;
  /** Nome da tela, para a barra e para o manual. */
  rotulo: string;
  /**
   * Permissao que a tela PARECE exigir.
   *
   * Governa apenas o que a barra oferece. Nao autoriza nada: quem autoriza e o
   * `requirePermission` de cada rota do servidor, e uma tela aberta a mao sem
   * permissao recebe `403 sem permissao` e mostra o painel embutido.
   *
   * `null` = nao depende de permissao (fluxo de entrada, painel).
   */
  exige: Permission | null;
  /** `dispensa` = fluxo de entrada, antes de haver sessao. */
  sessao: 'exige' | 'dispensa';
  /** Aparece na barra de navegacao? Telas de fluxo (codigo, cadastro) nao. */
  naBarra: boolean;
}

/**
 * Fase A. As telas de `/releases`, `/regras` e `/conteudo` entram nas fases B, C
 * e D — e cada uma so entra aqui quando existir de verdade, porque este arquivo
 * e conferido contra o manual e contra o roteador.
 */
export const ROTAS_DA_SPA: readonly Rota[] = [
  {
    caminho: '/entrar',
    rotulo: 'Entrar',
    exige: null,
    sessao: 'dispensa',
    naBarra: false,
  },
  {
    caminho: '/entrar/codigo',
    rotulo: 'Codigo do segundo fator',
    exige: null,
    sessao: 'dispensa',
    naBarra: false,
  },
  {
    caminho: '/entrar/cadastrar-2fa',
    rotulo: 'Cadastrar segundo fator',
    exige: null,
    // Dispensa sessao COMPLETA de proposito: o Better Auth deixa esta rota
    // acessivel com o cookie de 2FA pendente, e e a unica excecao nomeada a
    // obrigatoriedade do segundo fator. Sem ela ninguem conseguiria ativar o que
    // e obrigatorio ter ativado.
    sessao: 'dispensa',
    naBarra: false,
  },
  {
    caminho: '/',
    rotulo: 'Painel',
    exige: null,
    sessao: 'exige',
    naBarra: true,
  },
  {
    caminho: '/releases',
    rotulo: 'Releases',
    // Leitura, e nao escrita: o revisor clinico precisa CHEGAR a tela para
    // aprovar, e ele nao tem `content:write`.
    exige: 'content:read',
    sessao: 'exige',
    naBarra: true,
  },
  {
    caminho: '/releases/nova',
    rotulo: 'Nova release',
    exige: 'content:write',
    sessao: 'exige',
    naBarra: false,
  },
  {
    caminho: '/releases/:id',
    rotulo: 'Detalhe da release',
    exige: 'content:read',
    sessao: 'exige',
    naBarra: false,
  },
  {
    caminho: '/regras',
    rotulo: 'Regras',
    // Leitura: o revisor clinico simula sem poder escrever, e `/api/rules/simular`
    // exige so `content:read` justamente para isso.
    exige: 'content:read',
    sessao: 'exige',
    naBarra: true,
  },
  { caminho: '/regras/nova', rotulo: 'Nova regra', exige: 'content:write', sessao: 'exige', naBarra: false },
  { caminho: '/regras/:id', rotulo: 'Editor de regra', exige: 'content:read', sessao: 'exige', naBarra: false },
  {
    caminho: '/conteudo',
    rotulo: 'Conteudo',
    exige: 'content:read',
    sessao: 'exige',
    naBarra: true,
  },
  {
    caminho: '/conteudo/:entidade',
    rotulo: 'Lista de conteudo',
    exige: 'content:read',
    sessao: 'exige',
    naBarra: false,
  },
  {
    caminho: '/conteudo/:entidade/nova',
    rotulo: 'Novo item de conteudo',
    exige: 'content:write',
    sessao: 'exige',
    naBarra: false,
  },
  {
    caminho: '/conteudo/:entidade/editar',
    rotulo: 'Editar conteudo',
    exige: 'content:read',
    sessao: 'exige',
    naBarra: false,
  },
];

/**
 * Este caminho faz parte do fluxo de entrada?
 *
 * Existe por causa de um defeito concreto: quem recarrega a pagina em
 * `/entrar/cadastrar-2fa` esta com o cookie de 2FA PENDENTE, e a sondagem de
 * `/api/me` responde 401. Tratar isso como "sessao perdida" e navegar para
 * `/entrar` EXPULSA a pessoa da unica tela onde ela poderia ativar o segundo
 * fator que e obrigatorio ter ativado — e ela nunca sai desse laco.
 */
export function dispensaSessao(caminho: string): boolean {
  return ROTAS_DA_SPA.some((r) => r.caminho === caminho && r.sessao === 'dispensa');
}

export function temPermissao(permissoes: readonly Permission[], exige: Permission | null): boolean {
  return exige === null || permissoes.includes(exige);
}

/**
 * O que a barra oferece para estas permissoes.
 *
 * Esconde entrada de navegacao e botao de ACAO sem permissao; nunca esconde uma
 * tela de LEITURA que o operador pode legitimamente abrir. Uma barra que some
 * inteira e indistinguivel de uma interface quebrada — que e exatamente o que o
 * `admin` veria, ja que ele nao tem `content:write` nem `approval:decide`.
 */
export function navegacaoPara(permissoes: readonly Permission[]): readonly Rota[] {
  return ROTAS_DA_SPA.filter((r) => r.naBarra && temPermissao(permissoes, r.exige));
}
