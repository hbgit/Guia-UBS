/**
 * Escreve `src/db/triggers.sql` a partir de `src/db/triggers.ts`.
 *
 * Saida deterministica: a ordem sai das constantes de `schema/index.ts`, nao de
 * leitura de diretorio. O CI roda este script e falha se `git diff` acusar
 * mudanca — mesmo contrato que `contract:check` ja tem para os JSON Schemas.
 *
 * Uso: npm run cms:triggers
 */
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { buildTriggerSql, triggerStatements } from '../src/db/triggers.js';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const TARGET = join(ROOT, 'src', 'db', 'triggers.sql');

writeFileSync(TARGET, buildTriggerSql(), 'utf8');

// Um DROP e um CREATE por gatilho.
const count = triggerStatements().length / 2;
console.log(`  gerado  src/db/triggers.sql — ${count} gatilhos`);
