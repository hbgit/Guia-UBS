/**
 * Acesso ao banco master (`sqld`, libSQL) e aplicacao das migracoes.
 *
 * Duas superficies deliberadamente separadas:
 *
 *   `migrationStatements()`  — o SQL, como texto, para aplicar num banco VAZIO.
 *                              E o que os testes usam contra `node:sqlite`, o
 *                              que mantem `npm test` sem docker.
 *   `runMigrations(client)`  — o caminho de producao: o migrador do drizzle, que
 *                              consulta o journal e aplica so o que falta, e
 *                              depois os gatilhos.
 *
 * A diferenca importa: reaplicar `CREATE TABLE` num banco que ja tem as tabelas
 * falha. Banco novo aceita o texto direto; banco existente precisa do journal.
 * Os GATILHOS sao os mesmos nos dois caminhos, porque sao idempotentes por
 * construcao (ver `triggers.ts`).
 */
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { createClient, type Client } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate } from 'drizzle-orm/libsql/migrator';

import * as schema from './schema/index.js';
import { STATEMENT_BREAK } from './triggers.js';

const DB_DIR = dirname(fileURLToPath(import.meta.url));
const MIGRATIONS_DIR = join(DB_DIR, 'migrations');
const TRIGGERS_SQL = join(DB_DIR, 'triggers.sql');

/** URL do `sqld`. O default e a porta que `infra/compose.yaml` publica em loopback. */
export const DEFAULT_DATABASE_URL = 'http://127.0.0.1:8080';

/**
 * Tira do trecho o que nao e comando: o cabecalho de comentario do arquivo e o
 * `;` final.
 *
 * Ambos importam. O cabecalho gerado gruda no primeiro comando quando se parte
 * pelo marcador — e um `CREATE TRIGGER` precedido de seis linhas de comentario
 * ainda executa, entao o defeito nao apareceria no banco: apareceria na
 * comparacao entre disco e gerador, que e justamente a guarda contra gatilho
 * desatualizado. So corta comentario do INICIO; um `--` dentro do corpo de um
 * gatilho continua fazendo parte dele.
 */
function normalize(statement: string): string {
  const lines = statement.split('\n');
  let start = 0;
  while (start < lines.length) {
    const line = lines[start]!.trim();
    if (line.length > 0 && !line.startsWith('--')) break;
    start += 1;
  }
  return lines
    .slice(start)
    .join('\n')
    .trim()
    .replace(/;$/, '')
    .trim();
}

/** Parte um arquivo `.sql` no marcador do drizzle-kit e descarta o que nao e comando. */
export function splitStatements(sql: string): string[] {
  return sql
    .split(STATEMENT_BREAK)
    .map(normalize)
    .filter((statement) => statement.length > 0);
}

/** Gatilhos, como texto. Separado das tabelas porque e aplicado nos dois caminhos. */
export function triggerStatementsFromDisk(): string[] {
  return splitStatements(readFileSync(TRIGGERS_SQL, 'utf8'));
}

/**
 * Tabelas e gatilhos, na ordem, para aplicar num banco VAZIO.
 *
 * Le os arquivos de migracao em ordem lexicografica — que e a ordem cronologica,
 * porque o drizzle-kit prefixa com indice zero-padded.
 */
export function migrationStatements(): string[] {
  const files = readdirSync(MIGRATIONS_DIR)
    .filter((file) => file.endsWith('.sql'))
    .sort();

  if (files.length === 0) {
    throw new Error('src/db/migrations vazio — rode `npm run cms:generate`');
  }

  const tables = files.flatMap((file) =>
    splitStatements(readFileSync(join(MIGRATIONS_DIR, file), 'utf8')),
  );

  return [...tables, ...triggerStatementsFromDisk()];
}

export function createDatabaseClient(
  url = process.env.CMS_DATABASE_URL ?? DEFAULT_DATABASE_URL,
): Client {
  return createClient({ url, authToken: process.env.CMS_DATABASE_AUTH_TOKEN });
}

export function createDb(client: Client) {
  return drizzle(client, { schema });
}

/**
 * Recusa subir se o banco nao estiver aplicando chave estrangeira.
 *
 * Medido no `sqld` v0.24 e no libSQL em memoria: os dois ligam por padrao. Mas
 * "a versao de hoje liga por padrao" e fato de versao, nao garantia nossa — e o
 * que depende dele nao e pouco. Com FK desligada, apagar um `symptom_token`
 * deixa regras clinicas orfas EM SILENCIO, e o defeito so apareceria no gate do
 * packer, depois de a regra ja ter sido aprovada por um revisor.
 *
 * Falhar no boot e o mesmo padrao de `loadEnv()`: perder uma garantia inteira
 * sem ninguem perceber e pior do que nao subir.
 */
export async function assertForeignKeysEnforced(client: Client): Promise<void> {
  const resultado = await client.execute('PRAGMA foreign_keys');
  const ligado = Number(resultado.rows[0]?.foreign_keys ?? 0) === 1;
  if (!ligado) {
    throw new Error(
      'O banco esta com PRAGMA foreign_keys DESLIGADA. Toda garantia referencial ' +
        'do CMS depende dela: sem FK, apagar um token deixa regras clinicas orfas ' +
        'em silencio. Verifique a configuracao do sqld antes de subir.',
    );
  }
}

/**
 * Caminho de producao: migracoes pendentes e, em seguida, TODOS os gatilhos.
 *
 * Os gatilhos sao reaplicados a cada execucao de proposito. Um gatilho que
 * sumiu — por restauracao de backup antiga, por `DROP` manual durante um
 * expurgo interrompido — volta na proxima migracao, em vez de ficar ausente e
 * silencioso ate alguem conseguir apagar uma trilha de auditoria.
 */
export async function runMigrations(client: Client): Promise<void> {
  await migrate(createDb(client), { migrationsFolder: MIGRATIONS_DIR });
  for (const statement of triggerStatementsFromDisk()) {
    await client.execute(statement);
  }
}
