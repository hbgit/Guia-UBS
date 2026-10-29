/**
 * Politica de leitura anonima do prefixo `models/` (P1-1, #3).
 *
 * As fixtures sao as politicas MEDIDAS em 2026-10-29 num MinIO com a imagem do
 * compose: o `mc anonymous set download <bucket>/<prefixo>` mescla, mas libera
 * listagem (`s3:ListBucket`) e grava o recurso sem barra (`models*`), que vaza
 * qualquer chave comecando com `models`. Por isso a politica do modelo e
 * escrita a mao, e a dos packs — configurada fora do repositorio (#46) — nao
 * pode sumir no caminho.
 */
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

import {
  type Policy,
  mergeModelsPolicy,
  missingPermissions,
  modelsStatement,
} from '../src/models-policy.js';

const RAIZ = join(import.meta.dirname, '..', '..');

/** O que o `mc anonymous set download local/content-packs/0000000` grava. */
const PACKS_DO_MC: Policy = {
  Version: '2012-10-17',
  Statement: [
    {
      Action: ['s3:GetBucketLocation'],
      Effect: 'Allow',
      Principal: { AWS: ['*'] },
      Resource: ['arn:aws:s3:::content-packs'],
    },
    {
      Action: ['s3:ListBucket'],
      Condition: { StringEquals: { 's3:prefix': ['0000000'] } },
      Effect: 'Allow',
      Principal: { AWS: ['*'] },
      Resource: ['arn:aws:s3:::content-packs'],
    },
    {
      Action: ['s3:GetObject'],
      Effect: 'Allow',
      Principal: { AWS: ['*'] },
      Resource: ['arn:aws:s3:::content-packs/0000000*'],
    },
  ],
};

test('acrescenta so GetObject em content-packs/models/*', () => {
  const s = modelsStatement('content-packs');
  assert.deepEqual(s.Action, ['s3:GetObject']);
  // Com barra: `models*` liberaria `models-x/...` (medido).
  assert.deepEqual(s.Resource, ['arn:aws:s3:::content-packs/models/*']);

  const nova = mergeModelsPolicy(null, 'content-packs');
  const acoes = nova.Statement.flatMap((st) => [st.Action].flat());
  assert.ok(!acoes.includes('s3:ListBucket'), 'listagem anonima de models/');
});

test('preserva todo statement anterior', () => {
  const nova = mergeModelsPolicy(PACKS_DO_MC, 'content-packs');
  for (const st of PACKS_DO_MC.Statement) {
    assert.ok(
      nova.Statement.some((n) => JSON.stringify(n) === JSON.stringify(st)),
      `sumiu: ${JSON.stringify(st)}`,
    );
  }
  assert.deepEqual(missingPermissions(PACKS_DO_MC, nova), []);
});

test('e idempotente', () => {
  const uma = mergeModelsPolicy(PACKS_DO_MC, 'content-packs');
  assert.deepEqual(mergeModelsPolicy(uma, 'content-packs'), uma);
});

test('verificacao reprova se uma permissao anterior sumir', () => {
  const sem = { ...PACKS_DO_MC, Statement: PACKS_DO_MC.Statement.slice(0, 2) };
  const faltando = missingPermissions(PACKS_DO_MC, sem);
  assert.equal(faltando.length, 1);
  assert.match(faltando[0]!, /content-packs\/0000000\*/);
});

test('verificacao tolera o MinIO fundindo e reordenando statements', () => {
  // O MinIO grava ListBucket de dois prefixos num statement so (medido).
  const fundida: Policy = {
    Version: '2012-10-17',
    Statement: [
      {
        Action: ['s3:GetObject'],
        Effect: 'Allow',
        Principal: { AWS: ['*'] },
        Resource: ['arn:aws:s3:::content-packs/models/*', 'arn:aws:s3:::content-packs/0000000*'],
      },
      ...PACKS_DO_MC.Statement.slice(0, 2),
    ],
  };
  assert.deepEqual(missingPermissions(PACKS_DO_MC, fundida), []);
});

test('politica vazia vira so o statement de models', () => {
  assert.deepEqual(mergeModelsPolicy(null, 'content-packs').Statement, [
    modelsStatement('content-packs'),
  ]);
});

test('a CLI le e escreve JSON, e --verify sai 1 quando algo some', () => {
  const dir = mkdtempSync(join(tmpdir(), 'gubs-pol-'));
  const antes = join(dir, 'antes.json');
  const depois = join(dir, 'depois.json');
  writeFileSync(antes, JSON.stringify(PACKS_DO_MC));
  writeFileSync(depois, JSON.stringify({ ...PACKS_DO_MC, Statement: [] }));
  const cli = (...args: string[]) =>
    spawnSync('node', ['--import', 'tsx', join(RAIZ, 'packer/src/models-policy.ts'), ...args], {
      encoding: 'utf8',
    });

  const merge = cli('merge', antes, '--bucket', 'content-packs');
  assert.equal(merge.status, 0, merge.stderr);
  assert.deepEqual(missingPermissions(PACKS_DO_MC, JSON.parse(merge.stdout) as Policy), []);

  // `mc anonymous get-json` num bucket sem politica nao devolve JSON.
  writeFileSync(antes + '.vazio', '');
  assert.equal(cli('merge', antes + '.vazio', '--bucket', 'content-packs').status, 0);

  const verify = cli('verify', antes, depois);
  assert.equal(verify.status, 1);
  assert.match(verify.stderr, /0000000/);
});
