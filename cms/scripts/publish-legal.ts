/**
 * Publica uma versao do Termo de Uso do operador (#10).
 *
 * O texto vem de um arquivo FORA do repositorio: enquanto o controlador LGPD
 * (F-11) nao esta definido, vale um termo interno provisorio (versao 0.x).
 * Versao nova forca todos os operadores a aceitar de novo no proximo acesso.
 *
 * Uso: npm run cms:publish-legal -- --autor <id> --versao 0.1.0 --arquivo termo.md
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { parseArgs } from 'node:util';

import { createDatabaseClient } from '../src/db/client.js';
import { mensagemDoErro } from '../src/db/errors.js';
import { loadEnv } from '../src/env.js';
import { publicarDocumento } from '../src/services/legal.js';

const { values } = parseArgs({
  options: { autor: { type: 'string' }, versao: { type: 'string' }, arquivo: { type: 'string' } },
});
// LGPD-RT04: versao semantica.
if (!values.autor || !values.versao || !values.arquivo || !/^\d+\.\d+\.\d+$/.test(values.versao)) {
  console.error('uso: --autor <id de um admin ativo> --versao <x.y.z> --arquivo <caminho.md>');
  process.exit(2);
}

const contentMd = readFileSync(
  // npm workspaces roda o script com cwd=cms/; INIT_CWD e o diretorio do shell.
  resolve(process.env.INIT_CWD ?? process.cwd(), values.arquivo),
  'utf8',
);
const env = loadEnv();
const client = createDatabaseClient(env.databaseUrl);
try {
  const v = await publicarDocumento(
    client,
    env.hashSalt,
    { version: values.versao, contentMd },
    values.autor,
  );
  console.log(`  versao  ${v.version}`);
  console.log(`  hash    ${v.hash}`);
  console.log('\n  Todos os operadores serao levados a aceitar de novo no proximo acesso.');
} catch (erro) {
  const m = mensagemDoErro(erro);
  const motivo = /UNIQUE|PRIMARY KEY/i.test(m)
    ? 'versao ja publicada'
    : /autor/i.test(m)
      ? 'autor inexistente, desligado ou sem papel admin'
      : /identico|vigente/i.test(m)
        ? 'texto identico ao vigente'
        : /vazio/i.test(m)
          ? 'texto vazio'
          : m;
  console.error(`nao foi possivel publicar: ${motivo}`);
  process.exitCode = 1;
} finally {
  client.close();
}
