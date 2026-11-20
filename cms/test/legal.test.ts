/**
 * Termo de uso do operador: publicacao versionada e aceite atomico com a trilha
 * (issue #10). Banco de `freshApp(undefined, { termo: false })`, sem termo nenhum.
 */
import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import {
  aceitouVigente,
  documentoVigente,
  hashDoTexto,
  normalizarTexto,
  publicarDocumento,
  registrarAceite,
} from '../src/services/legal.js';
import { freshApp, novoOperador, TEST_ENV, type Fixture } from './support/app.js';

let f: Fixture;
let operador: { id: string; email: string };
const TEXTO = '# Termo\n\nTexto ficticio do termo.\n';

before(async () => {
  f = await freshApp(undefined, { termo: false });
  operador = await novoOperador(f, 'editor');
});
after(async () => f.close());

async function linhas(tabela: string, where = '1=1', args: string[] = []) {
  return (await f.client.execute({ sql: `SELECT * FROM ${tabela} WHERE ${where}`, args })).rows;
}

test('hash e normalizacao', () => {
  assert.equal(
    hashDoTexto('abc'),
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
  );
  assert.equal(normalizarTexto('\uFEFFa\r\nb'), 'a\nb');
});

test('sem termo: vigente nulo e aceite recusado', async () => {
  assert.equal(await documentoVigente(f.client), null);
  assert.equal(await aceitouVigente(f.client, operador.id), false);
  assert.deepEqual(
    await registrarAceite(f.client, TEST_ENV.hashSalt, operador.id, { version: 'v1', hash: 'x' }),
    { ok: false, motivo: 'sem_documento' },
  );
});

test('publicar v1 e v2, recusar texto igual (mesmo com CRLF), trilha e aceite', async () => {
  const v1 = await publicarDocumento(f.client, TEST_ENV.hashSalt, { version: 'v1', contentMd: TEXTO }, operador.id);
  assert.equal(v1.hash, hashDoTexto(TEXTO));
  assert.equal((await linhas('audit_entry', "action = 'legal_publish'")).length, 1);

  await assert.rejects(
    publicarDocumento(f.client, TEST_ENV.hashSalt, { version: 'v1b', contentMd: TEXTO }, operador.id),
    /texto identico ao vigente/,
  );
  await assert.rejects(
    publicarDocumento(f.client, TEST_ENV.hashSalt, { version: 'v1c', contentMd: TEXTO.replace(/\n/g, '\r\n') }, operador.id),
    /texto identico ao vigente/,
  );
  await assert.rejects(
    publicarDocumento(f.client, TEST_ENV.hashSalt, { version: 'v1d', contentMd: '  \r\n' }, operador.id),
    /texto vazio/,
  );

  const visto = { version: 'v1', hash: v1.hash };
  const r = await registrarAceite(f.client, TEST_ENV.hashSalt, operador.id, visto);
  assert.equal(r.ok, true);
  const consent = await linhas('consent_record');
  assert.equal(consent.length, 1);
  assert.equal(consent[0]!.doc_hash, hashDoTexto(TEXTO));
  assert.equal(consent[0]!.method, 'cms_interface');
  const trilha = await linhas('audit_entry', "action = 'consent_accept'");
  assert.equal(trilha.length, 1);
  assert.equal(trilha[0]!.actor_id, operador.id);
  assert.equal(trilha[0]!.entity_id, consent[0]!.id);

  // repeticao: no-op nas duas tabelas
  assert.equal((await registrarAceite(f.client, TEST_ENV.hashSalt, operador.id, visto)).ok, true);
  assert.equal((await linhas('consent_record')).length, 1);
  assert.equal((await linhas('audit_entry', "action = 'consent_accept'")).length, 1);

  // hash errado
  const ruim = await registrarAceite(f.client, TEST_ENV.hashSalt, operador.id, { version: 'v1', hash: 'errado' });
  assert.equal(ruim.ok, false);
  assert.equal(!ruim.ok && ruim.motivo, 'desatualizado');
  assert.equal(!ruim.ok && 'documento' in ruim && ruim.documento.version, 'v1');
  assert.equal((await linhas('consent_record')).length, 1);

  assert.equal(await aceitouVigente(f.client, operador.id), true);
  const v2 = await publicarDocumento(f.client, TEST_ENV.hashSalt, { version: 'v2', contentMd: TEXTO + 'mais\n' }, operador.id);
  assert.equal((await documentoVigente(f.client))?.version, 'v2');
  assert.equal(v2.version, 'v2');
  assert.equal(await aceitouVigente(f.client, operador.id), false);
});
