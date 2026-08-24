/**
 * Telemetria agregada (arquitetura.md 4.3-D).
 *
 * O que NAO existe aqui e o ponto da tabela: nenhuma coluna de identificador de
 * aparelho, de instalacao ou de sessao. O lote chega ja agregado por coorte
 * (municipio + versao do app + versao do pack) e por dia — nunca por timestamp
 * fino, que sozinho reidentifica em populacao pequena.
 *
 * O validador de `k_count >= 20` (lgpd.md LGPD-RF14) ja existe em
 * `contract/src/telemetry.ts` e e compartilhado com o app. O item 19 o liga a
 * ingestao; aqui so nasce a tabela.
 *
 * Vale registrar o que este item deliberadamente NAO faz: a tabela nao e
 * append-only. Diferente de auditoria e aceite, cujo valor esta em serem
 * irrefutaveis, o lote de telemetria e dado operacional com prazo de retencao
 * (LGPD-RF07) — bloquear DELETE aqui criaria conflito com a obrigacao de
 * expurgo sem proteger nada que precise de protecao.
 */
import { K_ANONYMITY_MIN } from '@guia-ubs/contract';
import { sql } from 'drizzle-orm';
import { check, integer, sqliteTable, text, unique } from 'drizzle-orm/sqlite-core';

export const telemetryBatch = sqliteTable(
  'telemetry_batch',
  {
    id: text('id').primaryKey(),
    /** Municipio + versao do app + versao do pack, ja concatenados. */
    cohortKey: text('cohort_key').notNull(),
    bucketDay: text('bucket_day').notNull(),
    /** Contadores da allowlist (`contract/telemetry-schema.json`), nada alem. */
    metricsJson: text('metrics_json').notNull(),
    kCount: integer('k_count').notNull(),
    receivedAt: text('received_at').notNull(),
  },
  (t) => [
    /**
     * O piso de k-anonimato tambem no DDL, e nao so no validador de aplicacao.
     * O validador protege a porta de entrada; esta restricao protege contra
     * qualquer outra escrita — importacao manual, script de migracao, correcao
     * "rapida" no shell.
     */
    check('telemetry_batch_k_anonymity', sql`${t.kCount} >= ${sql.raw(String(K_ANONYMITY_MIN))}`),
    unique('telemetry_batch_cohort_day').on(t.cohortKey, t.bucketDay),
  ],
);
