/**
 * O espelho de autoria nao pode divergir do schema do pack.
 *
 * `arquitetura.md 7` classifica "duplicacao de schema (autoria no CMS x pack)
 * divergir" como risco de probabilidade ALTA, e prescreve diff-check em CI. Este
 * arquivo E o diff-check: sem ele, escrever as 17 tabelas a mao seria a
 * duplicacao sem a mitigacao.
 *
 * A comparacao e nos DOIS sentidos, e os dois pegam defeitos diferentes:
 *
 *   coluna no pack sem par na autoria  -> o CMS nao consegue produzir a linha;
 *                                         o packer descobre no build, tarde
 *   coluna na autoria sem par no pack  -> o editor preenche um campo que nunca
 *                                         chega ao aparelho; ninguem descobre
 *
 * As unicas diferencas legitimas estao em `AUTHORING_ONLY_COLUMNS`. Uma tabela
 * sem contraparte precisa de motivo escrito nos mapas de excecao — nao existe
 * "passa porque sim".
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { contentSchema } from '@guia-ubs/contract';
import { getTableColumns, getTableName, is } from 'drizzle-orm';
import { SQLiteTable } from 'drizzle-orm/sqlite-core';

import * as authoringSchema from '../src/db/schema/content.js';
import {
  AUTHORING_ONLY_COLUMNS,
  AUTHORING_TABLES_WITHOUT_PACK_COUNTERPART,
  PACK_TABLES_WITHOUT_AUTHORING_COUNTERPART,
} from '../src/db/schema/index.js';

interface ColumnShape {
  dataType: string;
  notNull: boolean;
}

function tablesOf(module: object): Map<string, SQLiteTable> {
  const out = new Map<string, SQLiteTable>();
  for (const exported of Object.values(module)) {
    if (is(exported, SQLiteTable)) out.set(getTableName(exported), exported);
  }
  return out;
}

/** Colunas por NOME SQL — o nome da propriedade TS e irrelevante para o banco. */
function shapeOf(table: SQLiteTable): Map<string, ColumnShape> {
  const out = new Map<string, ColumnShape>();
  for (const column of Object.values(getTableColumns(table))) {
    out.set(column.name, { dataType: column.dataType, notNull: column.notNull });
  }
  return out;
}

const packTables = tablesOf(contentSchema);
const authoringTables = tablesOf(authoringSchema);

test('as tabelas do pack tem contraparte na autoria, ou excecao justificada', () => {
  for (const name of packTables.keys()) {
    if (name in PACK_TABLES_WITHOUT_AUTHORING_COUNTERPART) continue;
    assert.ok(
      authoringTables.has(name),
      `tabela "${name}" existe no pack e nao na autoria. O CMS nao consegue produzir ` +
        'essas linhas. Crie a tabela em src/db/schema/content.ts, ou registre o motivo ' +
        'em PACK_TABLES_WITHOUT_AUTHORING_COUNTERPART.',
    );
  }
});

test('as tabelas de conteudo da autoria tem contraparte no pack, ou excecao justificada', () => {
  for (const name of authoringTables.keys()) {
    if (name in AUTHORING_TABLES_WITHOUT_PACK_COUNTERPART) continue;
    assert.ok(
      packTables.has(name),
      `tabela "${name}" existe na autoria e nao no pack. Conteudo editado ali nunca ` +
        'chegaria ao aparelho. Crie a tabela em contract/src/content-schema.ts, ou ' +
        'registre o motivo em AUTHORING_TABLES_WITHOUT_PACK_COUNTERPART.',
    );
  }
});

test('toda excecao declarada aponta para uma tabela que existe', () => {
  // Excecao que sobrevive a remocao da tabela vira folclore: continua no arquivo,
  // ninguem lembra por que, e passa a acobertar a proxima divergencia real.
  for (const name of Object.keys(PACK_TABLES_WITHOUT_AUTHORING_COUNTERPART)) {
    assert.ok(packTables.has(name), `excecao para "${name}", que nao existe mais no pack`);
  }
  for (const name of Object.keys(AUTHORING_TABLES_WITHOUT_PACK_COUNTERPART)) {
    assert.ok(authoringTables.has(name), `excecao para "${name}", que nao existe mais na autoria`);
  }
});

test('nenhuma coluna do pack falta na autoria', () => {
  for (const [name, packTable] of packTables) {
    const authoringTable = authoringTables.get(name);
    if (!authoringTable) continue; // ja coberto pelo teste de tabelas

    const authoringShape = shapeOf(authoringTable);
    for (const column of shapeOf(packTable).keys()) {
      assert.ok(
        authoringShape.has(column),
        `${name}.${column} existe no pack e nao na autoria — o packer nao teria de ` +
          'onde tirar esse valor',
      );
    }
  }
});

test('a autoria so acrescenta colunas da lista permitida', () => {
  for (const [name, authoringTable] of authoringTables) {
    const packTable = packTables.get(name);
    if (!packTable) continue;

    const packShape = shapeOf(packTable);
    for (const column of shapeOf(authoringTable).keys()) {
      if (packShape.has(column)) continue;
      assert.ok(
        AUTHORING_ONLY_COLUMNS.includes(column),
        `${name}.${column} so existe na autoria e nao esta em AUTHORING_ONLY_COLUMNS. ` +
          'Ou o pack precisa da coluna, ou o editor esta preenchendo um campo que ' +
          'nunca chega ao aparelho.',
      );
    }
  }
});

test('as colunas compartilhadas tem o mesmo tipo e a mesma obrigatoriedade', () => {
  for (const [name, packTable] of packTables) {
    const authoringTable = authoringTables.get(name);
    if (!authoringTable) continue;

    const authoringShape = shapeOf(authoringTable);
    for (const [column, packShape] of shapeOf(packTable)) {
      const mirrored = authoringShape.get(column);
      if (!mirrored) continue;

      assert.equal(
        mirrored.dataType,
        packShape.dataType,
        `${name}.${column}: tipo ${mirrored.dataType} na autoria contra ` +
          `${packShape.dataType} no pack`,
      );
      // Obrigatoria na autoria e opcional no pack e aceitavel (a autoria pode ser
      // mais estrita). O contrario nao: o packer produziria NULL onde o pack exige
      // valor, e o `content.db` sairia invalido depois de assinado.
      assert.ok(
        !packShape.notNull || mirrored.notNull,
        `${name}.${column} e NOT NULL no pack e opcional na autoria — o packer ` +
          'poderia gerar um pack invalido a partir de conteudo aceito pelo CMS',
      );
    }
  }
});

test('o espelho cobre o conteudo inteiro do pack (nao um subconjunto)', () => {
  // Guarda contra o modo de falha mais silencioso: alguem espelhar so metade das
  // tabelas e todos os testes acima passarem por vacuidade.
  const esperadas = packTables.size - Object.keys(PACK_TABLES_WITHOUT_AUTHORING_COUNTERPART).length;
  const espelhadas = [...packTables.keys()].filter((name) => authoringTables.has(name)).length;
  assert.equal(espelhadas, esperadas, `${espelhadas} de ${esperadas} tabelas do pack espelhadas`);
  assert.ok(espelhadas >= 17, 'o pack tem 18 tabelas; so `pack_meta` fica de fora');
});
