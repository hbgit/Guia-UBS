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
