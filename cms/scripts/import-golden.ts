/**
 * Importa os casos golden do YAML para a tabela `golden_case`.
 *
 * Roda UMA vez, na implantacao. Dali em diante a tabela e a fonte do caminho do
 * CMS — que e o motivo de ela existir: o revisor clinico acrescenta caso pela
 * interface, sem abrir PR no repositorio.
 *
 * O YAML continua sendo a fonte do caminho `seed/`, que o CI roda em toda PR.
 * Sao duas FONTES para dois CAMINHOS, nao duas copias da mesma coisa — nao ha
 * sincronizacao para envelhecer, e este script nao a cria: ele so semeia.
 *
 * Idempotente: reimportar nao duplica nem sobrescreve caso ja existente. Um caso
 * editado no CMS nao pode ser revertido por reimportacao, senao o trabalho do
 * revisor sumiria numa reimplantacao.
 *
 * Uso: npm run cms:import-golden -- --autor <id do operador>
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parseArgs } from 'node:util';

import { parse as parseYaml } from 'yaml';

import { createDatabaseClient } from '../src/db/client.js';
import { loadEnv } from '../src/env.js';

interface CasoYaml {
  id: string;
  tokens: string[];
  expect: string;
  note?: string;
  reviewed_by?: string | null;
}

const { values } = parseArgs({ options: { autor: { type: 'string' } } });
if (!values.autor) {
  console.error('uso: --autor <id do operador que responde pela importacao>');
  process.exit(2);
}

const REPO_ROOT = join(import.meta.dirname, '..', '..');
const arquivo = join(REPO_ROOT, 'seed', 'golden', 'clinical_cases.yaml');
const casos = (parseYaml(readFileSync(arquivo, 'utf8')) as { cases?: CasoYaml[] }).cases ?? [];

const env = loadEnv();
const client = createDatabaseClient(env.databaseUrl);

let inseridos = 0;
let existentes = 0;
let semRevisor = 0;

try {
  for (const caso of casos) {
    if (!caso.reviewed_by) semRevisor += 1;
    const r = await client.execute({
      sql: `INSERT INTO golden_case
              (id, tokens_json, expected_outcome_id, clinical_source, added_by, reviewed_by, active)
            VALUES (?, ?, ?, ?, ?, NULL, 1)
            ON CONFLICT(id) DO NOTHING
            RETURNING id`,
      args: [
        caso.id,
        JSON.stringify(caso.tokens),
        caso.expect,
        caso.note ?? 'importado de seed/golden/clinical_cases.yaml',
        values.autor,
      ],
    });
    if (r.rows.length === 1) inseridos += 1;
    else existentes += 1;
  }

  console.log(`  importados  ${inseridos}`);
  console.log(`  ja existiam ${existentes} (nao sobrescritos)`);
  if (semRevisor > 0) {
    // O packer ja avisa disso a cada build; repetir aqui poe o numero na frente
    // de quem esta implantando, que e quem pode agir.
    console.log(`\n  aviso ${semRevisor} caso(s) sem revisor clinico nomeado.`);
    console.log('        Bloqueia o piloto, nao o build (arquitetura.md 5.12).');
  }
} finally {
  client.close();
}
