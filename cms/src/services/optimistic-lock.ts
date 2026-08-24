/**
 * Travamento otimista: a UNICA forma de escrever conteudo (PRD 7).
 *
 * O gatilho do item 16 ja recusa `UPDATE` que nao incremente `version`. Ele nao
 * basta sozinho: um `UPDATE ... SET version = version + 1` SEM a versao esperada
 * no `WHERE` passa pelo gatilho e sobrescreve a edicao de outra pessoa em
 * silencio. O gatilho garante que a versao ande; esta funcao garante que ela
 * ande a partir do ponto que o cliente leu.
 *
 * A versao esperada chega pelo cabecalho `If-Match`, como ETag — nao pelo corpo.
 * Aceita-la no corpo convidaria um cliente a reenviar o valor que acabou de ler,
 * que e precisamente o conflito que se quer detectar.
 */
import type { Client } from '@libsql/client';
import { and, eq, getTableColumns, getTableName, sql, type SQL } from 'drizzle-orm';
import type { SQLiteColumn, SQLiteTable } from 'drizzle-orm/sqlite-core';

import { createDb } from '../db/client.js';

/**
 * Coluna pelo nome da PROPRIEDADE Drizzle, com falha ruidosa.
 *
 * Uma fabrica generica indexa colunas por string; sem esta guarda, um nome
 * errado no registro viraria `undefined` e o Drizzle montaria SQL sem a
 * condicao — um `UPDATE` sem `WHERE`, que e o pior desfecho possivel aqui.
 */
function coluna(tabela: SQLiteTable, propriedade: string): SQLiteColumn {
  const encontrada = (getTableColumns(tabela) as Record<string, SQLiteColumn | undefined>)[
    propriedade
  ];
  if (!encontrada) {
    throw new Error(`${getTableName(tabela)} nao tem a propriedade "${propriedade}"`);
  }
  return encontrada;
}

export type ResultadoEscrita =
  | { estado: 'atualizado'; versao: number }
  /** A linha existe, mas em outra versao: alguem escreveu antes. */
  | { estado: 'conflito'; versaoAtual: number }
  | { estado: 'ausente' };

/** Chave primaria como par propriedade -> valor. */
export type Chave = Readonly<Record<string, string>>;

function condicaoDaChave(tabela: SQLiteTable, chave: Chave): SQL {
  const partes = Object.entries(chave).map(([propriedade, valor]) =>
    eq(coluna(tabela, propriedade), valor),
  );
  if (partes.length === 0) {
    throw new Error('chave vazia — seria um WHERE ausente');
  }
  return and(...partes)!;
}

/**
 * Atualiza uma linha exigindo a versao que o cliente leu.
 *
 * Devolve `conflito` COM a versao atual: o editor precisa dela para oferecer o
 * merge, e um 409 que nao diz contra o que se perdeu obriga a pessoa a recarregar
 * a tela para descobrir.
 */
export async function atualizarComVersao({
  client,
  tabela,
  chave,
  versaoEsperada,
  valores,
  atorId,
}: {
  client: Client;
  tabela: SQLiteTable;
  chave: Chave;
  versaoEsperada: number;
  valores: Record<string, unknown>;
  atorId: string;
}): Promise<ResultadoEscrita> {
  const db = createDb(client);
  const versao = coluna(tabela, 'version');
  const condicao = condicaoDaChave(tabela, chave);

  const atualizadas = await db
    .update(tabela)
    .set({
      ...valores,
      version: sql`${versao} + 1`,
      updatedBy: atorId,
      updatedAt: new Date().toISOString(),
    })
    .where(and(condicao, eq(versao, versaoEsperada)))
    .returning({ version: versao });

  if (atualizadas.length === 1) {
    return { estado: 'atualizado', versao: Number(atualizadas[0]!.version) };
  }

  // Zero linhas tem duas causas distintas, e o cliente precisa distingui-las:
  // a linha sumiu (404) ou alguem escreveu antes (409).
  const atual = await db.select({ version: versao }).from(tabela).where(condicao).limit(1);

  if (atual.length === 0) return { estado: 'ausente' };
  return { estado: 'conflito', versaoAtual: Number(atual[0]!.version) };
}

/** Le a versao corrente — usada para montar o `ETag` das respostas de leitura. */
export async function versaoAtual(
  client: Client,
  tabela: SQLiteTable,
  chave: Chave,
): Promise<number | null> {
  const db = createDb(client);
  const linhas = await db
    .select({ version: coluna(tabela, 'version') })
    .from(tabela)
    .where(condicaoDaChave(tabela, chave))
    .limit(1);
  return linhas.length === 0 ? null : Number(linhas[0]!.version);
}

export { coluna, condicaoDaChave };
