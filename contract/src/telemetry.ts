/**
 * ALLOWLIST de telemetria — lgpd.md RF14.
 *
 * Esta lista e o mecanismo tecnico que mantem a telemetria fora do conceito de
 * dado pessoal (LGPD art. 12). Qualquer campo novo exige revisao do encarregado
 * (DPO) antes de entrar aqui; o pipeline de ingestao rejeita chave desconhecida
 * e lote com coorte menor que K_ANONYMITY_MIN.
 *
 * PROIBIDOS por construcao: identificador de device/instalacao, timestamp fino,
 * sequencia de tokens de sintoma, texto livre, localizacao.
 */
import { z } from 'zod';

/** Coorte menor que isto nao e enviada nem aceita: risco de reidentificacao. */
export const K_ANONYMITY_MIN = 20;

/** Unico conjunto de metricas que o app pode emitir. */
export const METRIC_KEYS = [
  'triage_completed_total',
  'triage_outcome_routine_total',
  'triage_outcome_emergency_total',
  'triage_fallback_total',
  'inference_ms_p50',
  'inference_ms_p95',
  'sync_success_total',
  'sync_failure_total',
  'crash_total',
  'session_total',
] as const;

export type MetricKey = (typeof METRIC_KEYS)[number];

/**
 * Coorte agregada: municipio + versoes. Deliberadamente sem device id.
 * A granularidade temporal minima e o dia (`bucketDay`).
 */
export const cohortSchema = z.object({
  municipality: z.string().min(1),
  appVersion: z.string().min(1),
  packVersion: z.number().int().nonnegative(),
});

export const telemetryBatchSchema = z.object({
  cohort: cohortSchema,
  bucketDay: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'bucketDay deve ser YYYY-MM-DD'),
  /** Numero de dispositivos agregados no lote; abaixo do minimo, o lote e descartado. */
  kCount: z.number().int().min(K_ANONYMITY_MIN),
  /**
   * Parcial de proposito: um dispositivo sem crashes nao emite `crash_total`.
   * `partialRecord` (e nao `record`, exaustivo no Zod v4) mantem a allowlist
   * fechada para chaves desconhecidas sem exigir todas as metricas.
   */
  metrics: z.partialRecord(z.enum(METRIC_KEYS), z.number().nonnegative()),
});

export type TelemetryBatch = z.infer<typeof telemetryBatchSchema>;

/** Guarda de ingestao: k-anonimato e allowlist em um unico ponto de decisao. */
export function isAcceptableBatch(input: unknown): input is TelemetryBatch {
  return telemetryBatchSchema.safeParse(input).success;
}
