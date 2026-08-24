/**
 * Percorre o registro de entidades e exige, de CADA uma, os tres invariantes que
 * a fabrica existe para tornar estruturais.
 *
 * Nao ha lista de entidades aqui: ela vem de `CONTENT_ENTITIES`. Entidade nova
 * sem os invariantes reprova sozinha — que e a diferenca entre um teste que
 * guarda e um teste que cobre o que alguem lembrou de cobrir.
 */
import assert from 'node:assert/strict';
import { after, before, describe, test } from 'node:test';

import { getTableColumns, getTableName } from 'drizzle-orm';

import { CONTENT_ENTITIES } from '../src/content/registry.js';
import { VERSIONED_TABLES } from '../src/db/schema/index.js';
import {
  auditRows,
  freshApp,
  pedido,
  seedConteudo,
  sessaoDe,
  type Fixture,
} from './support/app.js';

let f: Fixture;
let editor: string;
let revisor: string;

before(async () => {
  f = await freshApp();
  editor = (await sessaoDe(f, 'editor')).cookie;
  revisor = (await sessaoDe(f, 'clinical_reviewer')).cookie;
  await seedConteudo(f, editor);
});
after(async () => f.close());

// ---------------------------------------------------------------------------
// Propriedades estaticas do registro
// ---------------------------------------------------------------------------

test('o registro cobre todas as entidades de conteudo com CRUD proprio', () => {
  assert.equal(CONTENT_ENTITIES.length, 10, 'mudou o numero de entidades sem atualizar o teste');
  const nomes = new Set(CONTENT_ENTITIES.map((e) => e.nome));
  assert.equal(nomes.size, CONTENT_ENTITIES.length, 'ha nome de rota repetido');
});

test('toda entidade do registro e versionada', () => {
  // Sem `version` a fabrica nao consegue aplicar o travamento otimista, e a
  // rota nasceria sem 409 — silenciosamente.
  const versionadas = new Set(VERSIONED_TABLES.map((t) => getTableName(t)));
  for (const entidade of CONTENT_ENTITIES) {
    assert.ok(
      versionadas.has(getTableName(entidade.tabela)),
      `${entidade.nome} nao esta em VERSIONED_TABLES`,
    );
  }
});

test('a chave declarada existe de verdade na tabela', () => {
  // Nome errado no registro viraria coluna `undefined` e, no pior caso, um
  // `UPDATE` sem `WHERE`. A guarda de `optimistic-lock` lanca; este teste evita
  // que o lance aconteca em producao.
  for (const entidade of CONTENT_ENTITIES) {
    const colunas = new Set(Object.keys(getTableColumns(entidade.tabela)));
    for (const propriedade of entidade.chave) {
      assert.ok(colunas.has(propriedade), `${entidade.nome}: chave "${propriedade}" nao existe`);
    }
    assert.ok(entidade.chave.length > 0, `${entidade.nome} sem chave`);
  }
});

test('entidade municipal tem municipalityId como primeiro componente da chave', () => {
  // O escopo nao pode ser parametro opcional que alguem esquece de passar: ele
  // e o primeiro segmento do caminho.
  for (const entidade of CONTENT_ENTITIES.filter((e) => e.escopo === 'municipal')) {
    assert.equal(entidade.chave[0], 'municipalityId', `${entidade.nome}`);
  }
});

test('a traducao declarada corresponde, em numero, a chave da entidade', () => {
  for (const entidade of CONTENT_ENTITIES) {
    if (!entidade.traducao) continue;
    assert.equal(
      entidade.traducao.chaveEstrangeira.length,
      entidade.chave.length,
      `${entidade.nome}: a chave estrangeira da traducao nao acompanha a chave da entidade`,
    );
    const colunas = new Set(Object.keys(getTableColumns(entidade.traducao.tabela)));
    for (const c of entidade.traducao.chaveEstrangeira) {
      assert.ok(colunas.has(c), `${entidade.nome}: traducao sem a coluna "${c}"`);
    }
    assert.ok(colunas.has('lang'), `${entidade.nome}: traducao sem coluna lang`);
  }
});

test('so entidade sem dependente estrutural e apagavel', () => {
  // As nao-apagaveis sao alvo de FK de conteudo clinico. Oferecer um DELETE que
  // sempre falha ensina o editor a ignorar mensagem de erro.
  const naoApagaveis = CONTENT_ENTITIES.filter((e) => !e.apagavel).map((e) => e.nome);
  assert.deepEqual(naoApagaveis.sort(), [
    'assets',
    'cards',
    'municipalities',
    'routing-outcomes',
    'symptom-tokens',
    'venues',
  ]);
});

// ---------------------------------------------------------------------------
// Comportamento, entidade a entidade
// ---------------------------------------------------------------------------

for (const entidade of CONTENT_ENTITIES) {
  describe(`${entidade.nome}`, () => {
    const raiz = `/api/content/${entidade.nome}`;
    const consulta = entidade.escopo === 'municipal' ? '?municipalityId=mun-1' : '';

    test('leitura exige permissao de conteudo', async () => {
      const r = await pedido(f, editor, 'GET', `${raiz}${consulta}`);
      assert.equal(r.status, 200, await r.text());
    });

    test('escrita e recusada a quem so revisa', async () => {
      // Segregacao clinica da LGPD-RF11: quem aprova nao escreve.
      const r = await pedido(f, revisor, 'POST', raiz, {});
      assert.equal(r.status, 403);
    });

    test('PATCH sem If-Match e recusado com 428', async () => {
      const alvo = entidade.chave.map(() => 'inexistente').join('/');
      const r = await pedido(f, editor, 'PATCH', `${raiz}/${alvo}`, { nada: 1 });
      assert.equal(r.status, 428, 'a pre-condicao precisa ser exigida ANTES de olhar o corpo');
    });

    test('rota de remocao existe apenas quando o registro permite', async () => {
      const alvo = entidade.chave.map(() => 'inexistente').join('/');
      const r = await pedido(f, editor, 'DELETE', `${raiz}/${alvo}`);
      if (entidade.apagavel) {
        assert.equal(r.status, 404, 'apagavel: linha ausente responde 404');
      } else {
        assert.equal(r.status, 404, 'nao apagavel: a rota nem e registrada');
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Um ciclo completo, com trilha
// ---------------------------------------------------------------------------

test('criar, ler, editar e ver na trilha — o ciclo inteiro', async () => {
  const criado = await pedido(f, editor, 'POST', '/api/content/symptom-tokens', {
    id: 'chest',
    kind: 'body_part',
    iconRef: 'icon.exemplo',
    sortOrder: 0,
    deprecated: 0,
  });
  assert.equal(criado.status, 201, await criado.text());
  assert.equal(criado.headers.get('etag'), '"1"', 'a criacao devolve a versao como ETag');

  const lido = await pedido(f, editor, 'GET', '/api/content/symptom-tokens/chest');
  assert.equal(lido.status, 200);
  assert.equal(lido.headers.get('etag'), '"1"');

  const editado = await pedido(
    f, editor, 'PATCH', '/api/content/symptom-tokens/chest', { sortOrder: 5 }, 1,
  );
  assert.equal(editado.status, 200, await editado.text());
  assert.equal(editado.headers.get('etag'), '"2"', 'a versao sobe de exatamente 1');

  const linhas = await auditRows(f);
  const acoes = linhas.map((l) => l.action);
  assert.ok(acoes.includes('content_create'), 'criacao sem entrada na trilha');
  assert.ok(acoes.includes('content_update'), 'edicao sem entrada na trilha');

  const atualizacao = linhas.find((l) => l.action === 'content_update')!;
  assert.equal(atualizacao.entity_id, 'chest');
  // A trilha guarda o antes E o depois: sem o antes, "o que mudou?" fica sem
  // resposta numa auditoria.
  assert.ok(atualizacao.before_json, 'sem estado anterior na trilha');
  assert.deepEqual(JSON.parse(atualizacao.after_json!), { sortOrder: 5 });
});

test('a traducao aninhada grava e sobrescreve pela mesma rota', async () => {
  const posta = await pedido(
    f, editor, 'PUT', '/api/content/symptom-tokens/chest/traducoes/pt', { label: 'Peito' },
  );
  assert.equal(posta.status, 200, await posta.text());

  const reposta = await pedido(
    f, editor, 'PUT', '/api/content/symptom-tokens/chest/traducoes/pt', { label: 'Torax' },
  );
  assert.equal(reposta.status, 200, 'reenviar a traducao precisa atualizar, nao falhar');

  const linhas = await f.client.execute(
    "SELECT label, version FROM token_translation WHERE token_id = 'chest' AND lang = 'pt'",
  );
  assert.equal(linhas.rows[0]!.label, 'Torax');
  assert.equal(Number(linhas.rows[0]!.version), 2, 'o upsert precisa incrementar a versao');
});

test('referencia inexistente vira 409, nao 500', async () => {
  // A FK recusando e a protecao funcionando. 500 faria parecer defeito do
  // servidor e ensinaria o editor a insistir.
  const r = await pedido(f, editor, 'POST', '/api/content/symptom-tokens', {
    id: 'orfao',
    kind: 'symptom',
    iconRef: 'icon.que.nao.existe',
    sortOrder: 0,
    deprecated: 0,
  });
  assert.equal(r.status, 409, await r.text());
});

test('cor fora da semantica e recusada JA na validacao de entrada', async () => {
  // Duas defesas, e esta e a primeira: o Zod derivado do `enum` do Drizzle
  // recusa antes de tocar o banco, e devolve QUAL campo esta errado. O CHECK do
  // DDL continua atras, para escrita que nao passe por aqui — e ele e afirmado
  // em `invariants.test.ts`, no nivel do SQL.
  //
  // A ordem importa: um 422 generico do banco mandaria o editor adivinhar o
  // campo; um 400 com o caminho do campo diz onde corrigir.
  const r = await pedido(f, editor, 'POST', '/api/content/cards', {
    id: 'card.lilas',
    kind: 'info',
    iconRef: 'icon.exemplo',
    colorToken: 'lilas',
    sortOrder: 0,
  });
  assert.equal(r.status, 400, 'lilas e procedencia, nunca cor de conteudo clinico');
  const corpo = (await r.json()) as { detalhes?: { path: string[] }[] };
  assert.ok(
    corpo.detalhes?.some((d) => d.path.includes('colorToken')),
    'a recusa precisa nomear o campo',
  );
});
