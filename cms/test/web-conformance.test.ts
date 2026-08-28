/**
 * O formulario de conteudo nao pode ficar para tras do schema.
 *
 * ## O que o compilador ja garante, e o que ele nao garante
 *
 * `Campo.nome` e `keyof EntradaDeConteudo[E]`, entao renome e remocao de coluna
 * reprovam em `tsc -p cms/web`. **Acrescimo nao.** Uma coluna `NOT NULL` sem
 * default significa que o editor deixa de conseguir criar a linha — o `POST`
 * passa a responder 400 para sempre — e o compilador fica mudo, porque nada no
 * tipo obriga o formulario a ser completo.
 *
 * Daí este arquivo, no espirito de `schema-conformance.test.ts`: comparacao nos
 * DOIS sentidos, com as excecoes justificadas por escrito.
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { getTableColumns } from 'drizzle-orm';

import { AUTHORING_FIELDS, CONTENT_ENTITIES } from '../src/content/registry.js';
import {
  CAMPOS,
  CAMPOS_DE_TRADUCAO,
  META,
  ORDEM_DE_CRIACAO,
  type MetadadoDeEntidade,
} from '../web/src/conteudo/campos.js';

/**
 * Entidades sem tela, com motivo escrito.
 *
 * Vazio de proposito: as dez tem tela. A constante fica porque a alternativa —
 * acrescentar a excecao no dia em que ela aparecer, sem lugar previsto para a
 * justificativa — e como as listas deste projeto envelhecem.
 */
const ENTIDADES_SEM_TELA: Readonly<Record<string, string>> = {};

function camposDe(nome: string): readonly { nome: string; referencia?: string }[] {
  return (CAMPOS as Record<string, readonly { nome: string; referencia?: string }[]>)[nome] ?? [];
}

test('toda entidade de conteudo tem campos, ou excecao justificada', () => {
  const faltando = CONTENT_ENTITIES.filter(
    (e) => camposDe(e.nome).length === 0 && !ENTIDADES_SEM_TELA[e.nome],
  ).map((e) => e.nome);
  assert.deepEqual(
    faltando,
    [],
    'entidade no registro sem campos na interface: conteudo que ninguem sabe que da para editar',
  );
});

test('nenhum campo aponta para entidade que nao existe', () => {
  // O sentido inverso: campo que sobrou de uma entidade removida vira um select
  // vazio, e o operador conclui que faltou cadastrar alguma coisa.
  const nomes = new Set<string>(CONTENT_ENTITIES.map((e) => e.nome));
  const orfas: string[] = [];
  for (const e of CONTENT_ENTITIES) {
    for (const c of camposDe(e.nome)) {
      if (c.referencia && !nomes.has(c.referencia)) orfas.push(`${e.nome}.${c.nome}`);
    }
  }
  assert.deepEqual(orfas, []);
});

test('TODA coluna obrigatoria sem default tem campo no formulario', () => {
  /**
   * O teste que o compilador nao consegue fazer.
   *
   * Coluna `NOT NULL` sem default e coluna que o `POST` exige. Sem campo, o
   * editor nao consegue mais criar a linha — e o sintoma e um 400 que a tela nao
   * explica, num formulario que parece completo.
   */
  const semCampo: string[] = [];
  for (const e of CONTENT_ENTITIES) {
    if (ENTIDADES_SEM_TELA[e.nome]) continue;
    const declarados = new Set(camposDe(e.nome).map((c) => c.nome));
    for (const [prop, coluna] of Object.entries(getTableColumns(e.tabela))) {
      if ((AUTHORING_FIELDS as readonly string[]).includes(prop)) continue;
      const temDefault = coluna.hasDefault || coluna.default !== undefined;
      if (coluna.notNull && !temDefault && !declarados.has(prop)) {
        semCampo.push(`${e.nome}.${prop}`);
      }
    }
  }
  assert.deepEqual(
    semCampo,
    [],
    'coluna obrigatoria sem campo: o formulario nao consegue mais criar a linha',
  );
});

test('nenhum campo nomeia coluna inexistente ou de autoria', () => {
  /**
   * `keyof` ja barra coluna inexistente no compilador; aqui a asserção cobre o
   * outro risco, que o tipo NAO barra: um campo de autoria.
   *
   * `version`, `updatedBy` e `updatedAt` voltam no GET e sao removidas na
   * escrita. Renderiza-las como editaveis faz o operador mudar um valor, salvar,
   * e ver a mudanca sumir — sem mensagem nenhuma.
   */
  const invalidos: string[] = [];
  for (const e of CONTENT_ENTITIES) {
    const colunas = new Set(Object.keys(getTableColumns(e.tabela)));
    for (const c of camposDe(e.nome)) {
      if (!colunas.has(c.nome)) invalidos.push(`${e.nome}.${c.nome} (coluna inexistente)`);
      if ((AUTHORING_FIELDS as readonly string[]).includes(c.nome)) {
        invalidos.push(`${e.nome}.${c.nome} (coluna de autoria)`);
      }
    }
  }
  assert.deepEqual(invalidos, []);
});

test('a ordem de criacao cobre todas as entidades, sem repetir', () => {
  // A ordem e o que a tela usa para dizer o que FALTA antes de a pessoa tentar —
  // porque o `409 "violaria uma referencia"` nao diz.
  assert.deepEqual(
    [...ORDEM_DE_CRIACAO].sort(),
    CONTENT_ENTITIES.map((e) => e.nome).sort(),
  );
  assert.equal(new Set(ORDEM_DE_CRIACAO).size, ORDEM_DE_CRIACAO.length);
});

test('a ordem de criacao respeita as referencias declaradas', () => {
  /**
   * Uma entidade so pode vir depois de tudo a que ela se refere. Se a ordem
   * mentir, a tela sugere um caminho que termina em `409` — que e exatamente o
   * problema que ela existe para evitar.
   */
  const posicao = new Map(ORDEM_DE_CRIACAO.map((n, i) => [n as string, i]));
  const invertidas: string[] = [];
  for (const e of CONTENT_ENTITIES) {
    for (const c of camposDe(e.nome)) {
      if (!c.referencia || c.referencia === e.nome) continue;
      const daEntidade = posicao.get(e.nome) ?? -1;
      const daReferencia = posicao.get(c.referencia) ?? -1;
      if (daReferencia > daEntidade) {
        invertidas.push(`${e.nome} vem antes de ${c.referencia}, mas depende dela`);
      }
    }
  }
  assert.deepEqual(invertidas, []);
});

test('o metadado repetido na interface bate com o registro do servidor', () => {
  /**
   * `META` repete `chave`, `escopo`, `apagavel` e a existencia de traducao,
   * porque `registry.ts` importa tabelas do Drizzle e arrastaria o ORM inteiro
   * para o bundle do navegador.
   *
   * Repetir so e aceitavel porque nao e confiado: aqui a copia e comparada com a
   * fonte, campo a campo. Sem isto, uma chave composta acrescentada no servidor
   * produziria uma URL errada no cliente — e o sintoma seria `404` numa linha que
   * existe.
   */
  const divergentes: string[] = [];
  for (const e of CONTENT_ENTITIES) {
    const meta = (META as Record<string, MetadadoDeEntidade | undefined>)[e.nome];
    if (!meta) {
      divergentes.push(`${e.nome}: ausente em META`);
      continue;
    }
    if (meta.chave.join(',') !== e.chave.join(',')) {
      divergentes.push(`${e.nome}.chave: ${meta.chave.join(',')} != ${e.chave.join(',')}`);
    }
    if (meta.escopo !== e.escopo) divergentes.push(`${e.nome}.escopo`);
    if (meta.apagavel !== e.apagavel) divergentes.push(`${e.nome}.apagavel`);
    if (meta.temTraducao !== (e.traducao !== undefined)) divergentes.push(`${e.nome}.temTraducao`);
  }
  assert.deepEqual(divergentes, [], 'a copia na interface divergiu do registro');
});

test('os campos de traducao batem com as colunas da tabela de traducao', () => {
  /**
   * Nos dois sentidos, e cada um tem consequencia propria:
   *
   * - campo A MAIS: o servidor recusa a gravacao, e o editor nao entende por que.
   * - campo A MENOS: a traducao fica incompleta, e o **packer bloqueia a
   *   publicacao** de pack com traducao faltando — o defeito so aparece na hora
   *   de publicar, longe de quem o causou.
   */
  const divergentes: string[] = [];
  for (const e of CONTENT_ENTITIES) {
    const declarados = CAMPOS_DE_TRADUCAO[e.nome as keyof typeof CAMPOS_DE_TRADUCAO];
    if (!e.traducao) {
      if (declarados) divergentes.push(`${e.nome}: tem campos de traducao e nao tem traducao`);
      continue;
    }
    if (!declarados) {
      divergentes.push(`${e.nome}: tem traducao e nenhum campo declarado`);
      continue;
    }
    // A chave estrangeira e `lang` viajam no CAMINHO; autoria e do servidor.
    const naoEditaveis = new Set<string>([
      ...e.traducao.chaveEstrangeira,
      'lang',
      ...AUTHORING_FIELDS,
    ]);
    const reais = Object.keys(getTableColumns(e.traducao.tabela)).filter(
      (c) => !naoEditaveis.has(c),
    );
    if ([...declarados].sort().join(',') !== reais.sort().join(',')) {
      divergentes.push(`${e.nome}: [${[...declarados].sort()}] != [${reais.sort()}]`);
    }
  }
  assert.deepEqual(divergentes, []);
});
