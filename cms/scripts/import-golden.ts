/**
 * Importa os casos golden do YAML para a tabela `golden_case` (P0-2).
 *
 * Mesma regra do packer e das rotas: caso sem revisao clinica valida e RECUSADO,
 * e a importacao e tudo-ou-nada — um recusado ou conflito e nada escrito. A
 * revisao so e ACRESCIDA: revisor que o YAML nao traz permanece, e data nunca e
 * trocada. Os atestados citados precisam ter sido registrados antes no CMS
 * (POST /api/golden-cases/atestados) com o ID de `seed/golden/atestados.yaml`.
 *
 * O YAML continua sendo a fonte do caminho `seed/`, que o CI roda em toda PR;
 * a tabela e a fonte do caminho do CMS. Reimportar e idempotente.
 *
 * Uso: npm run cms:import-golden -- --autor <id do operador>
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parseArgs } from 'node:util';

import { parse as parseYaml } from 'yaml';

import { createDatabaseClient } from '../src/db/client.js';
import { loadEnv } from '../src/env.js';
import { importarGolden, type CasoGoldenYaml } from '../src/services/golden-import.js';

const { values } = parseArgs({ options: { autor: { type: 'string' } } });
if (!values.autor) {
  console.error('uso: --autor <id do operador que responde pela importacao>');
  process.exit(2);
}

const REPO_ROOT = join(import.meta.dirname, '..', '..');
const lerYaml = (nome: string) =>
  parseYaml(readFileSync(join(REPO_ROOT, 'seed', 'golden', nome), 'utf8')) as Record<
    string,
    unknown
  > | null;
const casos = ((lerYaml('clinical_cases.yaml')?.cases as CasoGoldenYaml[] | undefined) ?? []);
const registro = (lerYaml('atestados.yaml')?.atestados as unknown[] | undefined) ?? [];

const env = loadEnv();
const client = createDatabaseClient(env.databaseUrl);

try {
  const r = await importarGolden(
    client,
    env.hashSalt,
    { casos, registro },
    { autor: values.autor, agora: new Date() },
  );
  console.log(`  inseridos              ${r.inseridos.length}`);
  console.log(`  revisores acrescentados ${r.revisoresAcrescentados.length}`);
  console.log(`  mantidos               ${r.mantidos.length}`);
  for (const c of r.conflitos) console.log(`  conflito  ${c.id}: ${c.motivo}`);
  for (const x of r.recusados) {
    console.log(`  recusado  ${x.id}`);
    for (const p of x.problemas) console.log(`            - ${p}`);
  }
  if (r.recusados.length > 0 || r.conflitos.length > 0) {
    console.error('\nNada foi escrito: a importacao e tudo-ou-nada.');
    process.exitCode = 1;
  }
} finally {
  client.close();
}
