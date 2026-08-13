/**
 * Contrato do `manifest.json` — unico objeto mutavel servido pelo servidor de conteudo.
 *
 * O device valida NESTA ORDEM (espec.md 4.2 / FSM-B):
 *   1. assinatura Ed25519 do manifest canonico
 *   2. packVersion > versao ativa            (anti-downgrade, INV-7)
 *   3. schemaVersion major suportado         (INV-6)
 *   4. sha256 de cada artefato baixado       (INV-3)
 *   5. so entao o swap atomico
 */
import { z } from 'zod';

/** SHA-256 em hexadecimal minusculo. */
const sha256 = z.string().regex(/^[0-9a-f]{64}$/, 'sha256 deve ser hex de 64 caracteres');

/** major.minor — o app compara apenas o major para decidir compatibilidade. */
const schemaVersion = z.string().regex(/^\d+\.\d+$/, 'schemaVersion deve ser "major.minor"');

export const artifactRefSchema = z.object({
  ref: z.string().min(1),
  url: z.string().min(1),
  sha256,
  bytes: z.number().int().positive(),
});

export const signatureSchema = z.object({
  alg: z.literal('Ed25519'),
  /** Identifica qual chave publica embarcada valida a assinatura (rotacao dual-key). */
  keyId: z.string().min(1),
  value: z.string().min(1),
});

export const manifestSchema = z.object({
  schemaVersion,
  /** Monotonico por municipio: nunca decresce, mesmo com assinatura valida. */
  packVersion: z.number().int().positive(),
  municipality: z.string().min(1),
  pack: z.object({
    url: z.string().min(1),
    sha256,
    bytes: z.number().int().positive(),
  }),
  assets: z.array(artifactRefSchema),
  /** Build minimo do app capaz de ler este pack. */
  minAppBuild: z.number().int().nonnegative(),
  publishedAt: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'publishedAt deve ser YYYY-MM-DD'),
  signature: signatureSchema,
});

export type Manifest = z.infer<typeof manifestSchema>;

/**
 * Serializacao canonica assinada/verificada: JSON com chaves ordenadas,
 * sem espacos e sem o campo `signature`. Emissor e verificador precisam
 * produzir byte-a-byte o mesmo resultado.
 */
export function canonicalPayload(manifest: Manifest): string {
  const { signature: _signature, ...rest } = manifest;
  return stableStringify(rest);
}

function stableStringify(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`;
  const entries = Object.entries(value as Record<string, unknown>)
    .filter(([, v]) => v !== undefined)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([k, v]) => `${JSON.stringify(k)}:${stableStringify(v)}`);
  return `{${entries.join(',')}}`;
}
