/**
 * Testes do contrato. Cobrem as guardas que protegem invariantes do sistema —
 * nao a serializacao trivial do Zod.
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { canonicalPayload, manifestSchema, type Manifest } from '../src/manifest.js';
import { desfechoPadrao } from '../src/rules.js';
import { isAcceptableBatch, K_ANONYMITY_MIN } from '../src/telemetry.js';

const HASH_A = 'a'.repeat(64);
const HASH_B = 'b'.repeat(64);

function validManifest(overrides: Partial<Manifest> = {}): Manifest {
  return {
    schemaVersion: '1.0',
    packVersion: 42,
    municipality: '0000000',
    pack: { url: 'packs/pack-abc.db', sha256: HASH_A, bytes: 1024 },
    assets: [{ ref: 'icon.head', url: 'assets/head.svg', sha256: HASH_B, bytes: 256 }],
    minAppBuild: 100,
    publishedAt: '2026-08-13',
    signature: { alg: 'Ed25519', keyId: 'k1', value: 'ZmFrZQ==' },
    ...overrides,
  } as Manifest;
}

test('manifest valido e aceito', () => {
  assert.equal(manifestSchema.safeParse(validManifest()).success, true);
});

test('manifest com packVersion zero e rejeitado (versao e monotonica e positiva)', () => {
  const result = manifestSchema.safeParse(validManifest({ packVersion: 0 }));
  assert.equal(result.success, false);
});

test('manifest com sha256 malformado e rejeitado', () => {
  const result = manifestSchema.safeParse(
    validManifest({ pack: { url: 'p.db', sha256: 'curto', bytes: 10 } }),
  );
  assert.equal(result.success, false);
});

test('assinatura fora de Ed25519 e rejeitada', () => {
  const result = manifestSchema.safeParse(
    validManifest({ signature: { alg: 'RS256', keyId: 'k1', value: 'x' } as never }),
  );
  assert.equal(result.success, false);
});

test('payload canonico ignora a assinatura e ordena chaves', () => {
  const a = canonicalPayload(validManifest());
  const b = canonicalPayload(
    validManifest({ signature: { alg: 'Ed25519', keyId: 'k2', value: 'b3V0cm8=' } }),
  );
  assert.equal(a, b, 'trocar a assinatura nao pode alterar o payload assinado');
  assert.ok(!a.includes('signature'));
  assert.ok(a.indexOf('"assets"') < a.indexOf('"municipality"'), 'chaves devem sair ordenadas');
});

test('payload canonico e estavel independente da ordem de insercao', () => {
  const base = validManifest();
  const shuffled = {
    signature: base.signature,
    publishedAt: base.publishedAt,
    pack: base.pack,
    schemaVersion: base.schemaVersion,
    minAppBuild: base.minAppBuild,
    municipality: base.municipality,
    assets: base.assets,
    packVersion: base.packVersion,
  } as Manifest;
  assert.equal(canonicalPayload(base), canonicalPayload(shuffled));
});

test('lote de telemetria abaixo do k-anonimato e rejeitado (lgpd RF14)', () => {
  const batch = {
    cohort: { municipality: '0000000', appVersion: '1.0.0', packVersion: 42 },
    bucketDay: '2026-08-13',
    kCount: K_ANONYMITY_MIN - 1,
    metrics: { triage_completed_total: 5 },
  };
  assert.equal(isAcceptableBatch(batch), false);
});

test('lote com metrica fora da allowlist e rejeitado', () => {
  const batch = {
    cohort: { municipality: '0000000', appVersion: '1.0.0', packVersion: 42 },
    bucketDay: '2026-08-13',
    kCount: K_ANONYMITY_MIN,
    metrics: { device_id_seen: 1 },
  };
  assert.equal(isAcceptableBatch(batch), false);
});

test('lote agregado valido e aceito', () => {
  const batch = {
    cohort: { municipality: '0000000', appVersion: '1.0.0', packVersion: 42 },
    bucketDay: '2026-08-13',
    kCount: K_ANONYMITY_MIN,
    metrics: { triage_completed_total: 120, triage_fallback_total: 3 },
  };
  assert.equal(isAcceptableBatch(batch), true);
});

// --- Desfecho padrao -------------------------------------------------------

test('desfecho padrao e o de MENOR severidade, seja qual for o nome', () => {
  // A escala e os nomes pertencem ao pack. Um municipio que chame o desfecho de
  // rotina de outro jeito nao pode quebrar o packer.
  const desfechos = new Map([
    ['URGENTE', { id: 'URGENTE', severityLevel: 100 }],
    ['ORIENTACAO_DOMICILIAR', { id: 'ORIENTACAO_DOMICILIAR', severityLevel: 1 }],
    ['POSTO', { id: 'POSTO', severityLevel: 10 }],
  ]);
  assert.equal(desfechoPadrao(desfechos), 'ORIENTACAO_DOMICILIAR');
});

test('desfecho padrao desempata por id, nao por ordem de insercao', () => {
  // O resultado entra em `pack_meta` e, por ela, no hash do pack. Depender da
  // ordem em que o SELECT devolveu as linhas tornaria o build nao reproduzivel.
  const a = new Map([
    ['B', { id: 'B', severityLevel: 10 }],
    ['A', { id: 'A', severityLevel: 10 }],
  ]);
  const b = new Map([
    ['A', { id: 'A', severityLevel: 10 }],
    ['B', { id: 'B', severityLevel: 10 }],
  ]);
  assert.equal(desfechoPadrao(a), 'A');
  assert.equal(desfechoPadrao(b), 'A');
});

test('sem desfecho cadastrado nao ha padrao possivel', () => {
  assert.throws(() => desfechoPadrao(new Map()), /nenhum desfecho/);
});
