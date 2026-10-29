#!/usr/bin/env node
/**
 * Ponto de entrada do packer. A logica mora em cli.ts para ser testavel sem
 * processo filho.
 */
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { executarCli } from './cli.js';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const OUT_DIR = join(REPO_ROOT, 'packer', 'out');

executarCli(process.argv.slice(2), { repoRoot: REPO_ROOT, outDir: OUT_DIR })
  .then((r) => {
    if (r.estado === 'bloqueado') process.exit(1);
  })
  .catch((error: unknown) => {
    console.error(`\nErro: ${(error as Error).message}`);
    process.exit(1);
  });
