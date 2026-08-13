/**
 * Gera os JSON Schemas versionados a partir da fonte unica em `src/`.
 *
 * Saida deterministica (chaves ordenadas, indentacao fixa): o CI roda este script
 * e falha se `git diff` acusar mudanca — e assim que uma alteracao de schema
 * esquecida quebra o build antes de chegar ao app (stack.md 3.3).
 *
 * Uso: npm run contract:generate
 */
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { getTableName, is } from 'drizzle-orm';
import { SQLiteTable } from 'drizzle-orm/sqlite-core';
import { createSelectSchema } from 'drizzle-zod';
import { z } from 'zod';

import * as content from '../src/content-schema.js';
import { manifestSchema } from '../src/manifest.js';
import { telemetryBatchSchema } from '../src/telemetry.js';
import { PACK_SCHEMA_VERSION } from '../src/index.js';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** snake_case -> PascalCase; nomeia os tipos que o codegen Dart vai produzir. */
function toPascalCase(snake: string): string {
  return snake
    .split('_')
    .map((part) => (part ? part[0]!.toUpperCase() + part.slice(1) : ''))
    .join('');
}

/** Ordena chaves recursivamente para que a saida seja byte-a-byte estavel. */
function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (value === null || typeof value !== 'object') return value;
  const out: Record<string, unknown> = {};
  for (const key of Object.keys(value as Record<string, unknown>).sort()) {
    out[key] = sortKeys((value as Record<string, unknown>)[key]);
  }
  return out;
}

function writeJson(fileName: string, payload: unknown): void {
  const target = join(ROOT, fileName);
  writeFileSync(target, `${JSON.stringify(sortKeys(payload), null, 2)}\n`, 'utf8');
  console.log(`  gerado  ${fileName}`);
}

// --- pack-schema.json: uma definicao por tabela do content.db ---------------
const definitions: Record<string, unknown> = {};
let tableCount = 0;

for (const exported of Object.values(content)) {
  if (!is(exported, SQLiteTable)) continue;
  const tableName = getTableName(exported);
  const rowSchema = createSelectSchema(exported);
  const jsonSchema = z.toJSONSchema(rowSchema, { target: 'draft-7' }) as Record<string, unknown>;
  delete jsonSchema.$schema; // redundante dentro de `definitions`
  definitions[toPascalCase(tableName)] = jsonSchema;
  tableCount += 1;
}

/** Falha ruidosa: schema vazio indica incompatibilidade silenciosa de versao do Zod. */
for (const [name, schema] of Object.entries(definitions)) {
  const properties = (schema as { properties?: Record<string, unknown> }).properties;
  if (!properties || Object.keys(properties).length === 0) {
    throw new Error(`Definicao "${name}" saiu sem propriedades — conversao para JSON Schema falhou`);
  }
}

writeJson('pack-schema.json', {
  $schema: 'http://json-schema.org/draft-07/schema#',
  $id: 'https://guia-ubs.example/contract/pack-schema.json',
  title: 'Guia UBS content pack',
  description:
    'Forma das linhas do content.db distribuido aos dispositivos. Gerado de src/content-schema.ts — nao editar a mao.',
  'x-packSchemaVersion': PACK_SCHEMA_VERSION,
  definitions,
});

// --- manifest-schema.json e telemetry-schema.json ---------------------------
writeJson('manifest-schema.json', {
  $id: 'https://guia-ubs.example/contract/manifest-schema.json',
  title: 'Guia UBS pack manifest',
  ...(z.toJSONSchema(manifestSchema, { target: 'draft-7' }) as object),
});

writeJson('telemetry-schema.json', {
  $id: 'https://guia-ubs.example/contract/telemetry-schema.json',
  title: 'Guia UBS telemetry batch (allowlist)',
  description:
    'Allowlist de metricas agregadas. Campo novo exige revisao do encarregado (lgpd.md RF14).',
  ...(z.toJSONSchema(telemetryBatchSchema, { target: 'draft-7' }) as object),
});

console.log(`\ncontrato v${PACK_SCHEMA_VERSION}: ${tableCount} tabelas do content.db`);
