/**
 * O contrato de escrita de conteudo, derivado do schema Drizzle.
 *
 * ## Por que este arquivo existe, e nao `hono/client`
 *
 * A [stack.md](../../../spec/stack.md) §3.3 exige que "mudanca no schema do
 * banco quebre o build do frontend" e prescreve `hono/client` como o meio. O
 * meio nao e viavel aqui, por quatro motivos independentes:
 *
 *   1. O tipo de rotas do Hono so cresce por ENCADEAMENTO, e `app.ts` usa
 *      declaracoes soltas — `createApp` devolve `Hono<{Variables}>`, schema `{}`.
 *   2. O CRUD e montado num LACO sobre `CONTENT_ENTITIES` (`routes/content.ts`),
 *      e caminho derivado de variavel e `string`, nao literal: cerca de 48 das
 *      ~65 rotas sao estruturalmente nao-inferiveis.
 *   3. `hc()` precisa do app como VALOR, e `createApp` e fabrica que recebe um
 *      `Client` vivo.
 *   4. Reconstruir a inferencia exigiria abandonar o laco do registro — que e a
 *      decisao estrutural que impede a decima setima copia do CRUD de esquecer a
 *      trilha.
 *
 * Entao o requisito e honrado pelo OUTRO lado da mesma cadeia: os tipos saem do
 * schema, e o formulario e escrito contra eles. Renomear uma coluna quebra
 * `tsc -p cms/web` no mesmo PR. A §5.13 registra isso por extenso, para que o
 * proximo leitor nao implemente contra a spec.
 *
 * ## So tipos
 *
 * Zero runtime: todo import daqui e `import type`, entao o Vite nao resolve nada
 * disto no navegador e nenhuma dependencia de servidor entra no bundle.
 */
import type { InferInsertModel } from 'drizzle-orm';

import type {
  asset,
  card,
  document,
  flowStep,
  municipality,
  routingOutcome,
  service,
  serviceDocument,
  symptomToken,
  venue,
} from '../db/schema/content.js';
import type { AUTHORING_FIELDS } from './registry.js';

/**
 * O que o cliente pode enviar: o modelo de insercao MENOS as colunas de autoria.
 *
 * `version`, `updatedBy` e `updatedAt` voltam no GET mas sao removidas na
 * escrita (`crud.ts` as omite do schema zod). Um formulario construido a partir
 * do modelo de LEITURA renderizaria as tres como editaveis, o operador as
 * mudaria, o servidor as ignoraria em silencio — e a edicao "nao salvaria" sem
 * nenhuma mensagem.
 */
type SemAutoria<T> = Omit<T, (typeof AUTHORING_FIELDS)[number]>;

/**
 * Chaveado pelo `nome` do registro — o mesmo segmento de `/api/content/<nome>`.
 *
 * Entidade nova em `CONTENT_ENTITIES` sem entrada aqui e apanhada por
 * `cms/test/web-conformance.test.ts`, que percorre os dois nos dois sentidos.
 */
export interface EntradaDeConteudo {
  municipalities: SemAutoria<InferInsertModel<typeof municipality>>;
  assets: SemAutoria<InferInsertModel<typeof asset>>;
  'symptom-tokens': SemAutoria<InferInsertModel<typeof symptomToken>>;
  'routing-outcomes': SemAutoria<InferInsertModel<typeof routingOutcome>>;
  venues: SemAutoria<InferInsertModel<typeof venue>>;
  cards: SemAutoria<InferInsertModel<typeof card>>;
  services: SemAutoria<InferInsertModel<typeof service>>;
  documents: SemAutoria<InferInsertModel<typeof document>>;
  'service-documents': SemAutoria<InferInsertModel<typeof serviceDocument>>;
  'flow-steps': SemAutoria<InferInsertModel<typeof flowStep>>;
}

export type NomeDeEntidade = keyof EntradaDeConteudo;
