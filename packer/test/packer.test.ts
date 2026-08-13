/**
 * Testes do packer.
 *
 * Cobrem as duas propriedades que sustentam a seguranca do produto:
 * o avaliador de regras (INV-1) e a cadeia de assinatura (INV-3/INV-7).
 * Sao o espelho em TypeScript do que o gate Dart precisa reproduzir.
 */
import assert from 'node:assert/strict';
import {
  createHash,
  generateKeyPairSync,
  type KeyObject,
  verify as edVerify,
} from 'node:crypto';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

import { canonicalPayload, manifestSchema, PACK_SCHEMA_VERSION, type Manifest } from '@guia-ubs/contract';

import { buildPack, readRuleModel } from '../src/build-pack.js';
import { buildManifest } from '../src/release.js';
import { evaluate, ruleMatches, type Outcome, type Rule } from '../src/rules.js';
import { validateGolden, validateReferential } from '../src/validate.js';

const REPO_ROOT = join(import.meta.dirname, '..', '..');

const OUTCOMES = new Map<string, Outcome>([
  ['ROUTINE_UBS', { id: 'ROUTINE_UBS', severityLevel: 10 }],
  ['EMERGENCY', { id: 'EMERGENCY', severityLevel: 100 }],
]);

function rule(
  id: string,
  priority: number,
  outcomeId: string,
  terms: [number, string, boolean][],
): Rule {
  return {
    id,
    priority,
    outcomeId,
    terms: terms.map(([groupNo, tokenId, negated]) => ({ groupNo, tokenId, negated })),
  };
}

// --- Avaliador de regras ---------------------------------------------------

test('termos do mesmo grupo sao conjuncao (E)', () => {
  const r = rule('r', 10, 'EMERGENCY', [
    [0, 'chest', false],
    [0, 'pain', false],
  ]);
  assert.equal(ruleMatches(r, new Set(['chest', 'pain'])), true);
  assert.equal(ruleMatches(r, new Set(['chest'])), false);
  assert.equal(ruleMatches(r, new Set(['pain'])), false);
});

test('grupos distintos sao disjuncao (OU)', () => {
  const r = rule('r', 10, 'EMERGENCY', [
    [0, 'bleeding', false],
    [0, 'severe', false],
    [1, 'bleeding', false],
    [1, 'pregnant', false],
  ]);
  assert.equal(ruleMatches(r, new Set(['bleeding', 'severe'])), true);
  assert.equal(ruleMatches(r, new Set(['bleeding', 'pregnant'])), true);
  assert.equal(ruleMatches(r, new Set(['bleeding'])), false);
});

test('termo negado exige ausencia do token', () => {
  const r = rule('r', 100, 'ROUTINE_UBS', [
    [0, 'head', false],
    [0, 'pain', false],
    [0, 'sudden', true],
  ]);
  assert.equal(ruleMatches(r, new Set(['head', 'pain'])), true);
  assert.equal(ruleMatches(r, new Set(['head', 'pain', 'sudden'])), false);
});

test('regra sem termos nunca dispara', () => {
  assert.equal(ruleMatches(rule('vazia', 1, 'EMERGENCY', []), new Set(['qualquer'])), false);
});

test('maior severidade vence mesmo com prioridade pior — INV-1 estrutural', () => {
  // Erro de autoria: regra de rotina com a MENOR prioridade possivel.
  const rules = [
    rule('rotina.prioritaria', 1, 'ROUTINE_UBS', [[0, 'chest', false]]),
    rule('red.flag', 999, 'EMERGENCY', [
      [0, 'chest', false],
      [0, 'pain', false],
    ]),
  ];
  const verdict = evaluate(new Set(['chest', 'pain']), rules, OUTCOMES, 'ROUTINE_UBS');
  assert.equal(verdict.outcomeId, 'EMERGENCY', 'nenhuma prioridade pode rebaixar uma red flag');
});

test('prioridade desempata dentro do mesmo nivel de severidade', () => {
  const rules = [
    rule('a', 50, 'ROUTINE_UBS', [[0, 'fever', false]]),
    rule('b', 10, 'ROUTINE_UBS', [[0, 'fever', false]]),
  ];
  assert.equal(evaluate(new Set(['fever']), rules, OUTCOMES, 'ROUTINE_UBS').matchedRuleId, 'b');
});

test('sem regra correspondente assume o desfecho padrao — nunca silencio', () => {
  const verdict = evaluate(new Set(['desconhecido']), [], OUTCOMES, 'ROUTINE_UBS');
  assert.equal(verdict.outcomeId, 'ROUTINE_UBS');
  assert.equal(verdict.matchedRuleId, null);
});

test('desfecho padrao inexistente falha ruidosamente', () => {
  assert.throws(() => evaluate(new Set(), [], OUTCOMES, 'NAO_EXISTE'), /nao existe no pacote/);
});

// --- Cadeia de assinatura --------------------------------------------------

/**
 * Constroi pack e manifest do zero, com um par de chaves efemero.
 *
 * Autocontido de proposito: o teste nao pode depender de `packer/out/` nem da
 * chave de desenvolvimento, senao um CI limpo falharia — e a chave de producao
 * jamais entra num runner de teste.
 */
function loadArtifacts(): { manifest: Manifest; publicKey: KeyObject; packPath: string } {
  const outDir = mkdtempSync(join(tmpdir(), 'guia-ubs-pack-'));
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  const keyPath = join(outDir, 'ephemeral.pem');
  writeFileSync(keyPath, privateKey.export({ type: 'pkcs8', format: 'pem' }) as string);

  const built = buildPack({
    repoRoot: REPO_ROOT,
    outDir,
    packVersion: 7,
    schemaVersion: PACK_SCHEMA_VERSION,
    municipality: '0000000',
    defaultOutcomeId: 'ROUTINE_UBS',
    sourceCommit: 'test',
  });

  const { manifest } = buildManifest({
    schemaVersion: PACK_SCHEMA_VERSION,
    packVersion: 7,
    municipality: '0000000',
    packPath: built.dbPath,
    assets: built.assets,
    minAppBuild: 1,
    keyId: 'test',
    privateKeyPath: keyPath,
  });

  return { manifest: manifestSchema.parse(manifest), publicKey, packPath: built.dbPath };
}

function signatureIsValid(manifest: Manifest, publicKey: KeyObject): boolean {
  return edVerify(
    null,
    Buffer.from(canonicalPayload(manifest), 'utf8'),
    publicKey,
    Buffer.from(manifest.signature.value, 'base64'),
  );
}

test('assinatura do manifest publicado verifica com a chave publica embarcada', () => {
  const { manifest, publicKey } = loadArtifacts();
  assert.equal(signatureIsValid(manifest, publicKey), true);
});

test('adulterar o hash do pack invalida a assinatura', () => {
  const { manifest, publicKey } = loadArtifacts();
  const tampered: Manifest = { ...manifest, pack: { ...manifest.pack, sha256: 'f'.repeat(64) } };
  assert.equal(signatureIsValid(tampered, publicKey), false);
});

test('adulterar a versao invalida a assinatura (barra forja de downgrade)', () => {
  const { manifest, publicKey } = loadArtifacts();
  const tampered: Manifest = { ...manifest, packVersion: manifest.packVersion + 100 };
  assert.equal(signatureIsValid(tampered, publicKey), false);
});

test('adulterar o hash de um asset invalida a assinatura', () => {
  const { manifest, publicKey } = loadArtifacts();
  const [first, ...rest] = manifest.assets;
  assert.ok(first, 'manifest precisa ter ao menos um asset');
  const tampered: Manifest = {
    ...manifest,
    assets: [{ ...first, sha256: '0'.repeat(64) }, ...rest],
  };
  assert.equal(signatureIsValid(tampered, publicKey), false);
});

test('o arquivo do pack no disco confere com o hash assinado', () => {
  const { manifest, packPath } = loadArtifacts();
  const actual = createHash('sha256').update(readFileSync(packPath)).digest('hex');
  assert.equal(actual, manifest.pack.sha256);
});

test('a suite golden do pacote semente passa integralmente', () => {
  const outDir = mkdtempSync(join(tmpdir(), 'guia-ubs-golden-'));
  const built = buildPack({
    repoRoot: REPO_ROOT,
    outDir,
    packVersion: 1,
    schemaVersion: PACK_SCHEMA_VERSION,
    municipality: '0000000',
    defaultOutcomeId: 'ROUTINE_UBS',
    sourceCommit: 'test',
  });
  assert.deepEqual(validateReferential(built.dbPath), [], 'sem problema referencial');
  const report = validateGolden(REPO_ROOT, readRuleModel(built.dbPath));
  assert.equal(report.falseNegatives, 0, 'nenhum falso negativo clinico');
  assert.equal(report.passed, report.total, `golden ${report.passed}/${report.total}`);
});
