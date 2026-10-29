/**
 * `infra/scripts/publish-model.sh` recusa o arquivo errado ANTES de tocar o
 * storage (P1-1, #3).
 *
 * O SHA-256 publicado precisa ser o mesmo que o app ja confere
 * (`app/lib/sync/model_catalog.dart`): um objeto com outro conteudo seria
 * rejeitado por toda a frota, depois de cada aparelho baixar 806 MB.
 */
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

const RAIZ = join(import.meta.dirname, '..', '..');
const SCRIPT = join(RAIZ, 'infra', 'scripts', 'publish-model.sh');
const SHA_DO_CATALOGO = /sha256: '([0-9a-f]{64})'/.exec(
  readFileSync(join(RAIZ, 'app', 'lib', 'sync', 'model_catalog.dart'), 'utf8'),
)![1]!;

test('arquivo com SHA divergente reprova sem chamar docker', () => {
  const dir = mkdtempSync(join(tmpdir(), 'gubs-pub-'));
  const falso = join(dir, 'falso.gguf');
  writeFileSync(falso, 'nao e o modelo....');
  // Um `docker` falso que deixa rastro: o script nao pode chegar ate ele.
  const marcador = join(dir, 'docker-chamado');
  const docker = join(dir, 'docker');
  writeFileSync(docker, `#!/bin/sh\ntouch '${marcador}'\nexit 99\n`);
  chmodSync(docker, 0o755);

  for (const extra of [['--check-only'], []]) {
    const r = spawnSync('bash', [SCRIPT, falso, ...extra], {
      encoding: 'utf8',
      env: { ...process.env, DOCKER: docker },
    });
    assert.equal(r.status, 1, r.stdout + r.stderr);
    assert.match(r.stderr, /SHA-256 nao confere/);
    assert.ok(r.stderr.includes(SHA_DO_CATALOGO), 'a mensagem precisa citar o esperado');
    assert.ok(!existsSync(marcador), 'tocou o storage com o arquivo errado');
  }
});

test('arquivo inexistente reprova com uso claro', () => {
  const r = spawnSync('bash', [SCRIPT, '/nao/existe.gguf'], { encoding: 'utf8' });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /nao existe/);
});

/**
 * Um `docker` falso que responde ao `mc` conforme o roteiro do teste e anota
 * cada `set-json` (a escrita da politica). Responde pelo script `sh -c`, que e
 * o ultimo argumento.
 */
function dockerFalso(dir: string, roteiro: { getJson: string[] }): string {
  const docker = join(dir, 'docker');
  const respostas = join(dir, 'get-json');
  writeFileSync(respostas, roteiro.getJson.join('\n') + '\n');
  writeFileSync(
    docker,
    `#!/bin/bash
script="\${@: -1}"
log='${join(dir, 'log')}'
case "$script" in
  *get-json*)
    n=$(( $(grep -c get-json "$log" 2>/dev/null || echo 0) + 1 ))
    echo "get-json" >> "$log"
    linha=$(sed -n "\${n}p" '${respostas}')
    if [ "$linha" = FALHA ]; then echo "mc: <ERROR> Unable to get-json" >&2; exit 1; fi
    echo "$linha" ;;
  *set-json*|*"set private"*) echo "set-json" >> "$log" ;;
esac
exit 0
`,
  );
  chmodSync(docker, 0o755);
  writeFileSync(join(dir, 'env'), 'S3_BUCKET=content-packs\n');
  return docker;
}

const POLITICA_DOS_PACKS = JSON.stringify({
  Version: '2012-10-17',
  Statement: [
    {
      Action: ['s3:GetObject'],
      Effect: 'Allow',
      Principal: { AWS: ['*'] },
      Resource: ['arn:aws:s3:::content-packs/0000000*'],
    },
  ],
});

function politica(dir: string, docker: string) {
  return spawnSync('bash', [SCRIPT, '--policy-only'], {
    encoding: 'utf8',
    env: { ...process.env, DOCKER: docker, INFRA_ENV_FILE: join(dir, 'env') },
  });
}

function escritas(dir: string): number {
  const log = join(dir, 'log');
  return existsSync(log)
    ? readFileSync(log, 'utf8').split('\n').filter((l) => l === 'set-json').length
    : 0;
}

test('falha ao LER a politica atual aborta sem escrever nada', () => {
  // Antes: `get-json ... || true` tratava a falha como "bucket sem politica",
  // e o `set-json` gravava SO o statement de models/ — apagando o acesso
  // anonimo aos packs da frota inteira, sem rollback (revisao final, I3).
  const dir = mkdtempSync(join(tmpdir(), 'gubs-pol-'));
  const r = politica(dir, dockerFalso(dir, { getJson: ['FALHA'] }));

  assert.equal(r.status, 1, r.stdout + r.stderr);
  assert.match(r.stderr, /politica atual/);
  assert.equal(escritas(dir), 0, 'escreveu politica sem saber a anterior');
});

test('falha ao conferir DEPOIS de escrever reaplica a politica anterior', () => {
  // Antes: com `set -e`, o script morria entre o set-json e o verify, com a
  // politica nova aplicada e nao conferida (revisao final, I4).
  const dir = mkdtempSync(join(tmpdir(), 'gubs-pol-'));
  const r = politica(
    dir,
    dockerFalso(dir, { getJson: [POLITICA_DOS_PACKS, 'FALHA'] }),
  );

  assert.notEqual(r.status, 0, r.stdout + r.stderr);
  assert.equal(escritas(dir), 2, 'a escrita nova e o rollback');
});

test('bucket sem politica ({}) segue normalmente', () => {
  const dir = mkdtempSync(join(tmpdir(), 'gubs-pol-'));
  const depois = JSON.stringify({
    Version: '2012-10-17',
    Statement: [
      {
        Action: ['s3:GetObject'],
        Effect: 'Allow',
        Principal: { AWS: ['*'] },
        Resource: ['arn:aws:s3:::content-packs/models/*'],
      },
    ],
  });
  const r = politica(dir, dockerFalso(dir, { getJson: ['{}', depois] }));

  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.equal(escritas(dir), 1);
});
