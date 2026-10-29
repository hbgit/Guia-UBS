/**
 * Aplica migracoes e gatilhos no `sqld`.
 *
 * Antes, confere as pre-condicoes de migracoes que DESCARTAM dado. Hoje so a
 * 0009, que tira `golden_case.reviewed_by`: um revisor gravado ali sumiria em
 * silencio, e nao ha para onde copia-lo — a coluna era FK para operador do CMS,
 * nao atestado de profissional (P0-2, D6). Achou valor? Para, e quem implanta
 * fala com o dono antes de qualquer coisa (docs/operacao.md 2.3).
 *
 * Uso: npm run cms:migrate
 *      CMS_DATABASE_URL=http://127.0.0.1:8080 npm run cms:migrate
 */
import type { Client } from '@libsql/client';

import {
  createDatabaseClient,
  runMigrations,
  triggerStatementsFromDisk,
} from '../src/db/client.js';

/**
 * IDs de `golden_case` com `reviewed_by` preenchido. Vazio quando a coluna ja
 * nao existe — banco novo, ou a 0009 ja aplicada —, e e por isso que a coluna e
 * procurada antes: um SELECT direto falharia com "no such column".
 */
export async function preCondicao0009(client: Client): Promise<string[]> {
  const colunas = await client.execute('PRAGMA table_info(golden_case)');
  if (!colunas.rows.some((c) => c.name === 'reviewed_by')) return [];
  const r = await client.execute(
    'SELECT id FROM golden_case WHERE reviewed_by IS NOT NULL ORDER BY id',
  );
  return r.rows.map((linha) => String(linha.id));
}

if (import.meta.filename === process.argv[1]) {
  const client = createDatabaseClient();
  try {
    const revisados = await preCondicao0009(client);
    if (revisados.length > 0) {
      console.error(
        `  abortado  ${revisados.length} caso(s) golden com reviewed_by preenchido: ` +
          `${revisados.join(', ')}.\n` +
          '            A 0009 descarta essa coluna. Nada foi migrado — fale com o ' +
          'dono antes de seguir (docs/operacao.md 2.3).',
      );
      process.exitCode = 1;
    } else {
      await runMigrations(client);
      const count = triggerStatementsFromDisk().length / 2;
      console.log(`  migrado  tabelas em dia, ${count} gatilhos aplicados`);
    }
  } finally {
    client.close();
  }
}
