/**
 * Monta o manifest, assina em Ed25519 e publica os artefatos.
 *
 * A chave privada e o SPOF mais critico do sistema (PRD risco R4): em producao
 * vive em cofre offline/HSM e so o CI assina, com aprovacao manual. Aqui ela e
 * lida de um caminho passado por parametro e nunca registrada em log.
 */
import { createHash, createHmac, createPrivateKey, sign as edSign } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

import { canonicalPayload, manifestSchema, type Manifest } from '@guia-ubs/contract';

export interface ManifestInput {
  schemaVersion: string;
  packVersion: number;
  municipality: string;
  packPath: string;
  assets: { ref: string; path: string; sha256: string; bytes: number }[];
  minAppBuild: number;
  keyId: string;
  privateKeyPath: string;
}

function sha256File(path: string): { sha256: string; bytes: number } {
  const content = readFileSync(path);
  return { sha256: createHash('sha256').update(content).digest('hex'), bytes: content.byteLength };
}

/**
 * `canonicalPayload` remove o campo `signature` antes de serializar, entao o
 * valor abaixo nunca entra nos bytes assinados — existe apenas para satisfazer
 * o tipo enquanto a assinatura real ainda nao foi calculada.
 */
const SIGNATURE_PLACEHOLDER = { alg: 'Ed25519', keyId: 'pending', value: 'pending' } as const;

/**
 * Nomeia o pack pelo hash do conteudo. E isso que permite `immutable` no cache
 * da borda: dois conteudos diferentes nunca compartilham URL (stack.md 4.2).
 */
export function buildManifest(input: ManifestInput): { manifest: Manifest; packUrl: string } {
  const pack = sha256File(input.packPath);
  const packUrl = `packs/pack-${pack.sha256.slice(0, 12)}.db`;

  const unsigned = {
    schemaVersion: input.schemaVersion,
    packVersion: input.packVersion,
    municipality: input.municipality,
    pack: { url: packUrl, sha256: pack.sha256, bytes: pack.bytes },
    assets: input.assets.map((a) => ({
      ref: a.ref,
      url: a.path,
      sha256: a.sha256,
      bytes: a.bytes,
    })),
    minAppBuild: input.minAppBuild,
    publishedAt: new Date().toISOString().slice(0, 10),
  };

  const privateKey = createPrivateKey(readFileSync(input.privateKeyPath, 'utf8'));
  const payload = canonicalPayload({ ...unsigned, signature: SIGNATURE_PLACEHOLDER } as Manifest);
  const signature = edSign(null, Buffer.from(payload, 'utf8'), privateKey).toString('base64');

  const manifest = manifestSchema.parse({
    ...unsigned,
    signature: { alg: 'Ed25519', keyId: input.keyId, value: signature },
  });

  return { manifest, packUrl };
}

export function writeManifest(outDir: string, manifest: Manifest): string {
  const path = join(outDir, 'manifest.json');
  writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
  return path;
}

// ---------------------------------------------------------------------------
// Publicacao S3 (MinIO) — SigV4 com node:crypto, sem SDK
// ---------------------------------------------------------------------------

export interface S3Target {
  endpoint: string;
  bucket: string;
  accessKey: string;
  secretKey: string;
  region?: string;
}

async function putObject(
  target: S3Target,
  key: string,
  body: Buffer,
  contentType: string,
): Promise<void> {
  const region = target.region ?? 'us-east-1';
  const url = new URL(`${target.endpoint.replace(/\/$/, '')}/${target.bucket}/${key}`);
  const amzDate = new Date().toISOString().replace(/[:-]|\.\d{3}/g, '');
  const dateStamp = amzDate.slice(0, 8);
  const payloadHash = createHash('sha256').update(body).digest('hex');

  const canonicalHeaders =
    `host:${url.host}\nx-amz-content-sha256:${payloadHash}\nx-amz-date:${amzDate}\n`;
  const signedHeaders = 'host;x-amz-content-sha256;x-amz-date';
  const canonicalRequest = [
    'PUT',
    url.pathname,
    '',
    canonicalHeaders,
    signedHeaders,
    payloadHash,
  ].join('\n');

  const scope = `${dateStamp}/${region}/s3/aws4_request`;
  const stringToSign = [
    'AWS4-HMAC-SHA256',
    amzDate,
    scope,
    createHash('sha256').update(canonicalRequest).digest('hex'),
  ].join('\n');

  const hmac = (k: Buffer | string, d: string) => createHmac('sha256', k).update(d, 'utf8').digest();
  const signingKey = hmac(
    hmac(hmac(hmac(`AWS4${target.secretKey}`, dateStamp), region), 's3'),
    'aws4_request',
  );
  const signature = createHmac('sha256', signingKey).update(stringToSign, 'utf8').digest('hex');

  const response = await fetch(url, {
    method: 'PUT',
    headers: {
      Authorization:
        `AWS4-HMAC-SHA256 Credential=${target.accessKey}/${scope}, ` +
        `SignedHeaders=${signedHeaders}, Signature=${signature}`,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
      'Content-Type': contentType,
    },
    body: new Uint8Array(body),
  });

  if (!response.ok) {
    throw new Error(`PUT ${key} falhou: ${response.status} ${await response.text()}`);
  }
}

const CONTENT_TYPES: Record<string, string> = {
  '.db': 'application/vnd.sqlite3',
  '.json': 'application/json',
  '.svg': 'image/svg+xml',
  '.opus': 'audio/opus',
};

function contentTypeFor(path: string): string {
  const ext = path.slice(path.lastIndexOf('.'));
  return CONTENT_TYPES[ext] ?? 'application/octet-stream';
}

/**
 * Publica pack, assets e manifest. O manifest vai POR ULTIMO, de proposito:
 * ate ele existir, nenhum dispositivo enxerga a nova versao, entao uma
 * publicacao interrompida na metade nunca aponta para artefato ausente.
 */
export async function publish(
  target: S3Target,
  prefix: string,
  files: { key: string; path: string }[],
  manifestPath: string,
): Promise<string[]> {
  const published: string[] = [];

  for (const file of files) {
    const key = `${prefix}/${file.key}`;
    await putObject(target, key, readFileSync(file.path), contentTypeFor(file.path));
    published.push(key);
  }

  const manifestKey = `${prefix}/manifest.json`;
  await putObject(target, manifestKey, readFileSync(manifestPath), 'application/json');
  published.push(manifestKey);

  return published;
}
