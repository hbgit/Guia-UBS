/**
 * O nosso schema Drizzle contra o que o Better Auth declara precisar — em
 * RUNTIME, nao contra um instantaneo copiado da documentacao.
 *
 * Este e o teste mais importante do item, e o motivo e o modo de falha que ele
 * evita: uma atualizacao da biblioteca acrescenta um campo, ninguem percebe,
 * `npm ci` traz a versao nova, e o defeito aparece como falha no PRIMEIRO LOGIN
 * em producao — no momento em que ninguem consegue entrar para corrigir.
 *
 * Mesmo padrao do teste pack x autoria do item 16: a lista e derivada, nunca
 * redigida ao lado.
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { getAuthTables } from '@better-auth/core/db';
import { twoFactor as twoFactorPlugin } from 'better-auth/plugins';
import { getTableColumns, getTableName } from 'drizzle-orm';
import type { SQLiteTable } from 'drizzle-orm/sqlite-core';

import {
  account,
  adminUser,
  session,
  twoFactor as twoFactorTable,
  verification,
} from '../src/db/schema/auth.js';

/** A MESMA configuracao de `auth/config.ts`, na parte que molda o schema. */
const OPCOES = {
  plugins: [twoFactorPlugin({ twoFactorTable: 'two_factor' })],
  user: {
    modelName: 'admin_user',
    additionalFields: {
      role: { type: 'string', required: true, input: false },
      disabledAt: { type: 'date', required: false, input: false },
    },
  },
} as never;

/** Modelo do Better Auth -> a tabela Drizzle que o representa aqui. */
const MAPA: Readonly<Record<string, SQLiteTable>> = {
  user: adminUser,
  session,
  account,
  verification,
  twoFactor: twoFactorTable,
};

const tabelasDaBiblioteca = getAuthTables(OPCOES) as Record<
  string,
  { modelName: string; fields: Record<string, { fieldName?: string; required?: boolean }> }
>;

test('todo modelo exigido pela biblioteca tem tabela nossa', () => {
  for (const modelo of Object.keys(tabelasDaBiblioteca)) {
    assert.ok(
      MAPA[modelo],
      `o Better Auth declara o modelo "${modelo}" e nao ha tabela para ele. ` +
        'Uma atualizacao acrescentou modelo: crie a tabela e a migracao.',
    );
  }
});

test('o nome da tabela bate com o modelName configurado', () => {
  for (const [modelo, definicao] of Object.entries(tabelasDaBiblioteca)) {
    const nossa = MAPA[modelo];
    if (!nossa) continue;
    assert.equal(
      getTableName(nossa),
      definicao.modelName,
      `o modelo "${modelo}" aponta para a tabela "${definicao.modelName}"`,
    );
  }
});

test('toda coluna exigida existe, com o mesmo nome SQL', () => {
  for (const [modelo, definicao] of Object.entries(tabelasDaBiblioteca)) {
    const nossa = MAPA[modelo];
    if (!nossa) continue;

    // Pelo nome da PROPRIEDADE Drizzle, nao pelo da coluna SQL: o adapter faz
    // `schema[fieldName]` sobre o objeto de tabela, e objeto de tabela e
    // indexado por propriedade. `emailVerified` (propriedade) -> `email_verified`
    // (coluna) e o par correto, e confundir os dois e o erro que este teste
    // existe para pegar.
    const nossas = new Set(Object.keys(getTableColumns(nossa)));
    for (const [chave, campo] of Object.entries(definicao.fields)) {
      const coluna = campo.fieldName ?? chave;
      assert.ok(
        nossas.has(coluna),
        `${definicao.modelName}.${coluna} e exigida pelo Better Auth e nao existe no ` +
          'schema. O adapter falharia na primeira leitura desse modelo.',
      );
    }
  }
});

test('coluna exigida como obrigatoria nao pode ser opcional aqui', () => {
  // O contrario e aceitavel: podemos ser mais estritos que a biblioteca. Este
  // sentido nao — a biblioteca escreveria um valor que o banco recusa, ou leria
  // NULL onde espera valor.
  for (const [modelo, definicao] of Object.entries(tabelasDaBiblioteca)) {
    const nossa = MAPA[modelo];
    if (!nossa) continue;

    const porNome = new Map(Object.values(getTableColumns(nossa)).map((c) => [c.name, c]));
    for (const [chave, campo] of Object.entries(definicao.fields)) {
      if (!campo.required) continue;
      const coluna = porNome.get(campo.fieldName ?? chave);
      if (!coluna) continue;
      assert.ok(
        coluna.notNull || coluna.hasDefault,
        `${definicao.modelName}.${coluna.name} e obrigatoria para o Better Auth e ` +
          'aqui aceita NULL sem default',
      );
    }
  }
});

test('as colunas SQL seguem o snake_case do resto do banco', () => {
  // A propriedade Drizzle e camelCase porque o adapter a usa; a COLUNA e
  // snake_case porque o banco inteiro e. Sao dois nomes de proposito, e este
  // teste impede que o primeiro vaze para o segundo.
  for (const tabela of Object.values(MAPA)) {
    for (const coluna of Object.values(getTableColumns(tabela))) {
      assert.match(
        coluna.name,
        /^[a-z][a-z0-9_]*$/,
        `${getTableName(tabela)}.${coluna.name} nao esta em snake_case`,
      );
    }
  }
});

test('o mapa nao tem entrada para modelo que a biblioteca nao declara mais', () => {
  // Entrada orfa vira folclore: continua no arquivo, ninguem lembra por que, e
  // passa a acobertar a proxima divergencia real.
  for (const modelo of Object.keys(MAPA)) {
    assert.ok(
      tabelasDaBiblioteca[modelo],
      `"${modelo}" esta no mapa e o Better Auth nao o declara mais`,
    );
  }
});
