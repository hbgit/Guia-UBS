/**
 * @guia-ubs/contract — fonte unica dos contratos entre plano de controle e app.
 *
 * Consumidores: `packer` (constroi e assina o pack), `cms` (autoria e publicacao)
 * e, via codegen, o app Flutter (`app/lib/generated/`).
 */
export * as contentSchema from './content-schema.js';
export { LANGS, COLOR_TOKENS, VENUES } from './content-schema.js';
export {
  manifestSchema,
  artifactRefSchema,
  signatureSchema,
  canonicalPayload,
  type Manifest,
} from './manifest.js';
export {
  telemetryBatchSchema,
  cohortSchema,
  isAcceptableBatch,
  K_ANONYMITY_MIN,
  METRIC_KEYS,
  type MetricKey,
  type TelemetryBatch,
} from './telemetry.js';

/** Versao do contrato do pack. Major muda ⇒ apps antigos rejeitam o pack (INV-6). */
export const PACK_SCHEMA_VERSION = '1.0';
