/**
 * Os campos de formulario de cada entidade de conteudo, como DADO.
 *
 * ## O elo que quebra o build
 *
 * `nome` e tipado como `keyof EntradaDeConteudo[E]`. Renomear `icon_ref` para
 * `asset_ref` em `cms/src/db/schema/content.ts` faz o literal `'iconRef'` deixar
 * de satisfazer o tipo, e `tsc -p cms/web` reprova **no mesmo PR** — que e o que
 * a stack.md §3.3 exige, ainda que por um caminho diferente do que ela prescreve
 * (ver `cms/src/content/tipos.ts`).
 *
 * `keyof` pega renome e remocao. Nao pega ACRESCIMO: uma coluna `NOT NULL` sem
 * default significa que o editor deixa de conseguir criar a linha, e o
 * compilador fica mudo. Quem pega isso e `cms/test/web-conformance.test.ts`,
 * comparando nos dois sentidos.
 *
 * ## Sem DOM
 *
 * Importado por teste `node:test` do workspace do servidor. Nada de React aqui —
 * o widget que cada `tipo` vira mora na tela.
 */
import type { EntradaDeConteudo, NomeDeEntidade } from '@guia-ubs/cms/src/content/tipos.js';
import { COLOR_TOKENS, LANGS, VENUES } from '@guia-ubs/contract';

export type TipoDeCampo =
  | 'texto'
  | 'numero'
  | 'booleano'
  /** Token de cor do PACK, nao cor da interface. Ver o cabecalho de `estilo.css`. */
  | 'cor'
  | 'local'
  | 'idioma'
  /** Referencia a outra entidade: vira select da lista dela. */
  | 'referencia';

export interface Campo<E extends NomeDeEntidade> {
  nome: keyof EntradaDeConteudo[E] & string;
  rotulo: string;
  tipo: TipoDeCampo;
  /**
   * Entidade referenciada, quando `tipo === 'referencia'`.
   *
   * Serve para duas coisas: montar o select, e explicar o
   * `409 "violaria uma referencia"` ANTES de ele acontecer — o servidor diz o
   * que aconteceu, mas nao o que faltava.
   */
  referencia?: NomeDeEntidade;
  /** Ajuda curta, quando o nome da coluna nao basta. */
  dica?: string;
}

/** Valores fechados que a interface oferece como escolha, e nao como texto livre. */
export const OPCOES = {
  cor: COLOR_TOKENS,
  local: VENUES,
  idioma: LANGS,
} as const;

type MapaDeCampos = { [E in NomeDeEntidade]: readonly Campo<E>[] };

export const CAMPOS: MapaDeCampos = {
  municipalities: [
    { nome: 'id', rotulo: 'Identificador', tipo: 'texto' },
    { nome: 'code', rotulo: 'Codigo IBGE', tipo: 'texto', dica: '7 digitos' },
    { nome: 'name', rotulo: 'Nome', tipo: 'texto' },
    { nome: 'active', rotulo: 'Ativo', tipo: 'booleano' },
  ],
  assets: [
    {
      nome: 'ref',
      rotulo: 'Referencia',
      tipo: 'texto',
      // Vira o nome do arquivo publicado, entao nao aceita barra nem ponto-ponto:
      // `path` alimenta a chave no S3, a url do manifest e um `join()` no
      // caminho `seed/`. O servidor recusa o que nao casar.
      dica: 'minusculas, numeros e pontos: icon.head',
    },
    { nome: 'kind', rotulo: 'Tipo', tipo: 'texto', dica: 'icon, image ou audio' },
    {
      nome: 'path',
      rotulo: 'Caminho publicado',
      tipo: 'texto',
      dica: 'derivado de ref e do tipo; o servidor recusa qualquer outro formato',
    },
    // `sha256`, `bytes` e o proprio binario NAO sao campos: saem do envio do
    // arquivo, na secao propria. Quem conhece o hash de um arquivo e quem recebeu
    // os bytes — nao quem preenche o formulario. `storageKey` saiu do schema no
    // item 25, e o compilador pegaria se tivesse ficado aqui.
  ],
  'symptom-tokens': [
    { nome: 'id', rotulo: 'Identificador', tipo: 'texto' },
    { nome: 'kind', rotulo: 'Tipo', tipo: 'texto' },
    { nome: 'iconRef', rotulo: 'Icone', tipo: 'referencia', referencia: 'assets' },
    { nome: 'sortOrder', rotulo: 'Ordem', tipo: 'numero' },
    {
      nome: 'deprecated',
      rotulo: 'Descontinuado',
      tipo: 'booleano',
      // Nao ha DELETE para token: as regras que o citam continuam validas, e o
      // packer bloqueia a publicacao ate elas serem reescritas.
      dica: 'e assim que um token sai de circulacao — nao ha exclusao',
    },
  ],
  'routing-outcomes': [
    { nome: 'id', rotulo: 'Identificador', tipo: 'texto' },
    {
      nome: 'severityLevel',
      rotulo: 'Nivel de severidade',
      tipo: 'numero',
      // A escala pertence ao PACK, nao ao binario: o pacote semente usa 10 e 100,
      // e outro municipio pode publicar outra escala. O desfecho padrao e sempre
      // o de MENOR severidade, derivado — nao ha coluna para ele.
      dica: 'a escala e do pack; a menor severidade vira o desfecho padrao',
    },
    { nome: 'cardId', rotulo: 'Cartao', tipo: 'referencia', referencia: 'cards' },
    { nome: 'venueId', rotulo: 'Local', tipo: 'referencia', referencia: 'venues' },
  ],
  venues: [
    { nome: 'id', rotulo: 'Identificador', tipo: 'local' },
    { nome: 'iconRef', rotulo: 'Icone', tipo: 'referencia', referencia: 'assets' },
    {
      nome: 'colorToken',
      rotulo: 'Token de cor',
      tipo: 'cor',
      dica: 'verde = UBS/rotina, vermelho = emergencia, azul = informacao — no APLICATIVO',
    },
    { nome: 'sortOrder', rotulo: 'Ordem', tipo: 'numero' },
  ],
  cards: [
    { nome: 'id', rotulo: 'Identificador', tipo: 'texto' },
    { nome: 'kind', rotulo: 'Tipo', tipo: 'texto' },
    { nome: 'iconRef', rotulo: 'Icone', tipo: 'referencia', referencia: 'assets' },
    {
      nome: 'colorToken',
      rotulo: 'Token de cor',
      tipo: 'cor',
      dica: 'verde = UBS/rotina, vermelho = emergencia, azul = informacao — no APLICATIVO',
    },
    { nome: 'sortOrder', rotulo: 'Ordem', tipo: 'numero' },
  ],
  services: [
    {
      nome: 'municipalityId',
      rotulo: 'Municipio',
      tipo: 'referencia',
      referencia: 'municipalities',
    },
    { nome: 'id', rotulo: 'Identificador', tipo: 'texto' },
    { nome: 'venueId', rotulo: 'Local', tipo: 'referencia', referencia: 'venues' },
    { nome: 'iconRef', rotulo: 'Icone', tipo: 'referencia', referencia: 'assets' },
    { nome: 'sortOrder', rotulo: 'Ordem', tipo: 'numero' },
  ],
  documents: [
    {
      nome: 'municipalityId',
      rotulo: 'Municipio',
      tipo: 'referencia',
      referencia: 'municipalities',
    },
    { nome: 'id', rotulo: 'Identificador', tipo: 'texto' },
    { nome: 'iconRef', rotulo: 'Icone', tipo: 'referencia', referencia: 'assets' },
    { nome: 'imageRef', rotulo: 'Imagem', tipo: 'referencia', referencia: 'assets' },
  ],
  'service-documents': [
    {
      nome: 'municipalityId',
      rotulo: 'Municipio',
      tipo: 'referencia',
      referencia: 'municipalities',
    },
    { nome: 'serviceId', rotulo: 'Servico', tipo: 'referencia', referencia: 'services' },
    { nome: 'documentId', rotulo: 'Documento', tipo: 'referencia', referencia: 'documents' },
    { nome: 'required', rotulo: 'Obrigatorio', tipo: 'booleano' },
  ],
  'flow-steps': [
    {
      nome: 'municipalityId',
      rotulo: 'Municipio',
      tipo: 'referencia',
      referencia: 'municipalities',
    },
    { nome: 'id', rotulo: 'Identificador', tipo: 'texto' },
    { nome: 'venueId', rotulo: 'Local', tipo: 'referencia', referencia: 'venues' },
    { nome: 'stepOrder', rotulo: 'Ordem do passo', tipo: 'numero' },
    { nome: 'iconRef', rotulo: 'Icone', tipo: 'referencia', referencia: 'assets' },
  ],
};

/**
 * A ordem em que as entidades podem ser criadas.
 *
 * Nao e preferencia: as chaves estrangeiras a impoem. Fora de ordem, o servidor
 * responde `409 "violaria uma referencia"` — que diz o que aconteceu, **mas nao
 * o que faltava** (`operacao.md` §4.1). A tela usa esta ordem para mostrar o que
 * falta ANTES de a pessoa tentar.
 *
 *   asset ──┬─→ symptom_token ─────────────┐
 *           ├─→ card ──┐                   ├─→ routing_rule (editor de regras)
 *           └─→ venue ─┴─→ routing_outcome ┘
 *   municipality ─→ service, document, service_document, flow_step
 */
export const ORDEM_DE_CRIACAO: readonly NomeDeEntidade[] = [
  'municipalities',
  'assets',
  'venues',
  'cards',
  'symptom-tokens',
  'routing-outcomes',
  'services',
  'documents',
  'service-documents',
  'flow-steps',
];

/**
 * Chave, escopo e exclusao de cada entidade — repetidos do registro do servidor.
 *
 * ## Por que repetir, se `CONTENT_ENTITIES` ja tem isso
 *
 * `registry.ts` importa as TABELAS do Drizzle, que sao objetos de runtime.
 * Importa-lo aqui arrastaria o `drizzle-orm` inteiro para o bundle do navegador,
 * para usar tres campos de metadado. Os tipos vem de `tipos.ts` porque `import
 * type` some na compilacao; estes valores nao somem.
 *
 * A repeticao e segura porque NAO e confiada: `cms/test/web-conformance.test.ts`
 * compara este mapa contra `CONTENT_ENTITIES` campo a campo. Divergencia reprova
 * — que e a diferenca entre repetir e duplicar.
 */
export interface MetadadoDeEntidade {
  /** Propriedades da chave primaria, NA ORDEM em que entram no caminho. */
  chave: readonly string[];
  escopo: 'global' | 'municipal';
  /** `false` quando e alvo de regra clinica ou de FK estrutural. */
  apagavel: boolean;
  /** Idiomas traduziveis, quando a entidade tem traducao aninhada. */
  temTraducao: boolean;
}

export const META: Readonly<Record<NomeDeEntidade, MetadadoDeEntidade>> = {
  municipalities: { chave: ['id'], escopo: 'global', apagavel: false, temTraducao: false },
  assets: { chave: ['ref'], escopo: 'global', apagavel: false, temTraducao: false },
  'symptom-tokens': { chave: ['id'], escopo: 'global', apagavel: false, temTraducao: true },
  'routing-outcomes': { chave: ['id'], escopo: 'global', apagavel: false, temTraducao: false },
  venues: { chave: ['id'], escopo: 'global', apagavel: false, temTraducao: true },
  cards: { chave: ['id'], escopo: 'global', apagavel: false, temTraducao: true },
  services: {
    chave: ['municipalityId', 'id'],
    escopo: 'municipal',
    apagavel: true,
    temTraducao: true,
  },
  documents: {
    chave: ['municipalityId', 'id'],
    escopo: 'municipal',
    apagavel: true,
    temTraducao: true,
  },
  'service-documents': {
    chave: ['municipalityId', 'serviceId', 'documentId'],
    escopo: 'municipal',
    apagavel: true,
    temTraducao: false,
  },
  'flow-steps': {
    chave: ['municipalityId', 'id'],
    escopo: 'municipal',
    apagavel: true,
    temTraducao: true,
  },
};

/** `/api/content/<nome>/<v1>/<v2>` — a chave entra na ordem declarada. */
export function caminhoDaLinha(nome: NomeDeEntidade, valores: Record<string, unknown>): string {
  const partes = META[nome].chave.map((k) => encodeURIComponent(String(valores[k] ?? '')));
  return `/api/content/${nome}/${partes.join('/')}`;
}

/**
 * Os campos EDITAVEIS de cada traducao.
 *
 * Nao inclui a chave estrangeira nem `lang` — esses vao no caminho da URL — nem
 * as colunas de autoria. Conferido contra as tabelas `*_translation` por
 * `cms/test/web-conformance.test.ts`, nos dois sentidos: campo a mais e campo
 * que o servidor recusa; campo a menos e traducao que o editor nao consegue
 * preencher, e o packer BLOQUEIA a publicacao de pack com traducao faltando.
 */
export const CAMPOS_DE_TRADUCAO: Readonly<Partial<Record<NomeDeEntidade, readonly string[]>>> = {
  'symptom-tokens': ['label', 'audioRef'],
  venues: ['label', 'audioRef'],
  cards: ['title', 'body', 'audioRef'],
  services: ['label', 'audioRef'],
  documents: ['label', 'hint', 'audioRef'],
  'flow-steps': ['title', 'body', 'audioRef'],
};
