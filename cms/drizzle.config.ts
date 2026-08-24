import { defineConfig } from 'drizzle-kit';

/**
 * Migracoes do banco master do CMS.
 *
 * `dialect: 'sqlite'` mesmo o alvo sendo `sqld` (libSQL): libSQL e um fork do
 * SQLite e o DDL emitido e identico. O dialeto `turso` do drizzle-kit exige
 * credenciais ja no `generate`, o que poria a URL do banco de producao como
 * pre-requisito de um comando que so escreve arquivo. Quem fala libSQL de
 * verdade e o runtime (`src/db/client.ts`, via `drizzle-orm/libsql`).
 *
 * Os GATILHOS nao saem daqui — o drizzle-kit so emite CREATE TABLE. Ver
 * `src/db/triggers.ts`.
 */
export default defineConfig({
  dialect: 'sqlite',
  schema: './src/db/schema',
  out: './src/db/migrations',
});
