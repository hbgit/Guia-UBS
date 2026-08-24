/**
 * Aplica migracoes e gatilhos no `sqld`.
 *
 * Uso: npm run cms:migrate
 *      CMS_DATABASE_URL=http://127.0.0.1:8080 npm run cms:migrate
 */
import {
  createDatabaseClient,
  runMigrations,
  triggerStatementsFromDisk,
} from '../src/db/client.js';

const client = createDatabaseClient();
try {
  await runMigrations(client);
  const count = triggerStatementsFromDisk().length / 2;
  console.log(`  migrado  tabelas em dia, ${count} gatilhos aplicados`);
} finally {
  client.close();
}
