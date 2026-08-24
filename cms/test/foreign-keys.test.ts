/**
 * As chaves estrangeiras valem no caminho de RUNTIME.
 *
 * `migrations.test.ts` afirmava isso lendo `PRAGMA foreign_keys` — mas lia a
 * pragma que o proprio fixture tinha acabado de ligar. Um teste assim
 * tranquiliza sem guardar: continuaria verde com o produto desprotegido.
 *
 * Aqui a afirmacao e sobre COMPORTAMENTO, e contra o mesmo cliente libSQL que o
 * servidor usa. O que depende disso nao e pouco: sem FK, apagar um
 * `symptom_token` deixa regras clinicas orfas em silencio, e o defeito so
 * apareceria no gate do packer — depois de a regra ja ter sido aprovada.
 */
import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { assertForeignKeysEnforced } from '../src/db/client.js';
import { freshApp, pedido, seedConteudo, sessaoDe, type Fixture } from './support/app.js';

let f: Fixture;
let editor: string;

before(async () => {
  f = await freshApp();
  editor = (await sessaoDe(f, 'editor')).cookie;
  await seedConteudo(f, editor);
});
after(async () => f.close());

test('a guarda de boot aceita um banco com FK ligada', async () => {
  await assertForeignKeysEnforced(f.client);
});

test('INSERT com referencia inexistente e recusado pelo banco', async () => {
  await assert.rejects(
    () =>
      f.client.execute(
        `INSERT INTO symptom_token (id, kind, icon_ref, sort_order, deprecated,
                                    version, updated_by, updated_at)
         VALUES ('orfao', 'symptom', 'icone.que.nao.existe', 0, 0, 1, 'x', 'y')`,
      ),
    /FOREIGN KEY constraint failed/,
  );
});

test('DELETE de linha referenciada por regra clinica e recusado', async () => {
  // E a garantia que o item 18 inteiro assume: o registro marca `symptom-tokens`
  // como nao apagavel, mas a defesa de verdade e esta.
  await pedido(f, editor, 'POST', '/api/content/symptom-tokens', {
    id: 'chest', kind: 'body_part', iconRef: 'icon.exemplo', sortOrder: 0, deprecated: 0,
  });
  await pedido(f, editor, 'POST', '/api/content/cards', {
    id: 'c1', kind: 'result', iconRef: 'icon.exemplo', colorToken: 'green', sortOrder: 0,
  });
  await pedido(f, editor, 'POST', '/api/content/venues', {
    id: 'UBS', iconRef: 'icon.exemplo', colorToken: 'green', sortOrder: 0,
  });
  await pedido(f, editor, 'POST', '/api/content/routing-outcomes', {
    id: 'ROUTINE_UBS', severityLevel: 10, cardId: 'c1', venueId: 'UBS',
  });
  await pedido(f, editor, 'POST', '/api/rules', {
    id: 'r1', priority: 1, outcomeId: 'ROUTINE_UBS',
    terms: [{ groupNo: 0, tokenId: 'chest', negated: false }],
  });

  await assert.rejects(
    () => f.client.execute("DELETE FROM symptom_token WHERE id = 'chest'"),
    /FOREIGN KEY constraint failed/,
    'apagar um token usado por regra deixaria a regra orfa em silencio',
  );
});

test('nao ha rota que apague token — a recusa nem chega ao banco', async () => {
  const r = await pedido(f, editor, 'DELETE', '/api/content/symptom-tokens/chest');
  assert.equal(r.status, 404, 'a rota de remocao nao deve existir para esta entidade');
  const ainda = await f.client.execute("SELECT COUNT(*) AS n FROM symptom_token WHERE id = 'chest'");
  assert.equal(Number(ainda.rows[0]!.n), 1);
});

test('a guarda de boot RECUSA um banco com FK desligada', async () => {
  // Sem esta metade, a guarda poderia estar sempre devolvendo `ok` e ninguem
  // saberia. `PRAGMA foreign_keys = OFF` e aceito em conexao de arquivo.
  await f.client.execute('PRAGMA foreign_keys = OFF');
  await assert.rejects(() => assertForeignKeysEnforced(f.client), /foreign_keys DESLIGADA/);
  await f.client.execute('PRAGMA foreign_keys = ON');
});
