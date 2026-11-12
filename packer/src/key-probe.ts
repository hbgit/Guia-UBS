#!/usr/bin/env node
/**
 * `npm run pack:key` — le a chave privada de `PACK_SIGNING_KEY_PATH` UMA vez e
 * imprime a PUBLICA em hex (32 bytes, o formato de `PACK_SIGNING_KEY_K1`).
 *
 * Serve ao mantenedor A (Revisao do ADR-001; docs/operacao.md 2.7b) para
 * conferir, antes do build, que o pipe do cofre chega ao packer e que a chave e
 * a registrada:
 *
 *   PACK_SIGNING_KEY_PATH=<(comando-do-cofre) npm run pack:key
 *
 * `<(...)`, e nao `3< <(...)`: o `npm run` nao repassa o fd 3 ao filho.
 * Nada e escrito em disco; a privada nunca e impressa.
 */
import { createPublicKey } from 'node:crypto';

import { carregarChavePrivada } from './release.js';

const caminho = process.env.PACK_SIGNING_KEY_PATH;
if (!caminho) {
  console.error('PACK_SIGNING_KEY_PATH nao definida');
  process.exit(64);
}
try {
  const der = createPublicKey(carregarChavePrivada(caminho)).export({ type: 'spki', format: 'der' });
  console.log((der as Buffer).subarray(-32).toString('hex'));
} catch (e) {
  console.error(`nao consegui ler a chave em ${caminho}: ${(e as Error).message}`);
  process.exit(1);
}
