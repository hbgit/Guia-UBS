/**
 * Registra em `signing_key` a chave publica correspondente a privada que o job
 * vai usar.
 *
 * `conferirChaveRegistrada()` recusa assinar com chave fora desta tabela, porque
 * um pack assinado com chave desconhecida e rejeitado por TODA a frota em
 * silencio: o sync tenta, a assinatura nao confere, o pack e descartado, e nada
 * no servidor acusa.
 *
 * A guarda existia desde o item 19, mas nao havia como satisfaze-la: o passo era
 * obrigatorio e nao tinha ferramenta. Quem seguisse a implantacao so descobria
 * no ultimo comando, com uma excecao nao tratada do worker.
 *
 * So a PUBLICA e gravada, e ela e DERIVADA da privada — nunca informada a parte.
 * Aceitar a publica por parametro permitiria registrar uma que nao corresponde a
 * privada em uso, que e exatamente o incidente mudo que a guarda previne.
 *
 * Uso:
 *   npm run cms:register-key -- --key-path contract/keys/dev-k1.pem
 *   npm run cms:register-key -- --key-path … --key-id k2
 */
import { createPrivateKey, createPublicKey } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { isAbsolute, join } from 'node:path';
import { parseArgs } from 'node:util';

import { createDatabaseClient } from '../src/db/client.js';
import { loadEnv } from '../src/env.js';

const { values } = parseArgs({
  options: {
    'key-path': { type: 'string' },
    'key-id': { type: 'string' },
  },
});

const caminho = values['key-path'];
if (!caminho) {
  console.error('uso: --key-path <arquivo.pem> [--key-id k1]');
  process.exit(2);
}

/**
 * `npm run` executa com o cwd no workspace (`cms/`), nao na raiz — entao um
 * caminho relativo escrito como o manual o escreve nao resolveria. Mesma solucao
 * de `import-golden.ts`.
 */
const REPO_ROOT = join(import.meta.dirname, '..', '..');

const env = loadEnv();
// `PACK_SIGNING_KEY_ID` e variavel do PACKER, nao do CMS — nao esta em `Env`. O
// padrao repete o do worker para os dois lados concordarem sem ninguem informar.
const keyId = values['key-id'] ?? process.env.PACK_SIGNING_KEY_ID ?? 'k1';

/**
 * SPKI/DER em base64 — o mesmo formato que `chavePublicaDe()` no packer produz e
 * que a guarda compara. Formatos diferentes nos dois lados fariam a comparacao
 * falhar com a chave certa registrada.
 */
let publicKey: string;
try {
  const absoluto = isAbsolute(caminho) ? caminho : join(REPO_ROOT, caminho);
  const privada = createPrivateKey(readFileSync(absoluto, 'utf8'));
  publicKey = createPublicKey(privada).export({ type: 'spki', format: 'der' }).toString('base64');
} catch (erro) {
  console.error(`nao consegui ler a chave privada em ${caminho}: ${String(erro)}`);
  process.exit(1);
}

const client = createDatabaseClient(env.databaseUrl);

const existente = await client.execute({
  sql: 'SELECT public_key FROM signing_key WHERE key_id = ?',
  args: [keyId],
});

if (existente.rows.length > 0) {
  if (String(existente.rows[0]!.public_key) === publicKey) {
    console.log(`  ja registrada  ${keyId}  (mesma chave — nada a fazer)`);
    process.exit(0);
  }
  // Sobrescrever trocaria a chave que a frota reconhece sem que ninguem tenha
  // pedido rotacao. Rotacao e um procedimento (§5 do manual de operacao), nao um
  // efeito colateral de rodar o script duas vezes com o caminho errado.
  console.error(
    `  ja existe uma chave DIFERENTE com key_id="${keyId}".\n` +
      '  Para rotacionar, registre a nova com outro --key-id e aposente a antiga.',
  );
  process.exit(1);
}

await client.execute({
  sql: 'INSERT INTO signing_key (key_id, public_key, activated_at) VALUES (?, ?, ?)',
  args: [keyId, publicKey, new Date().toISOString()],
});

console.log(`  registrada  ${keyId}`);
console.log(`  publica     ${publicKey}`);
console.log('\n  O packer so assina com chave que esteja aqui.');
