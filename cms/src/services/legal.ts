/**
 * Termo de uso do operador do CMS: publicacao versionada e aceite (issue #10,
 * lgpd.md LGPD-RT04/RT05).
 *
 * O aceite referencia versao E hash. O hash e calculado AQUI, sobre o texto
 * normalizado: o cliente so ecoa o que viu, nunca dita o que foi aceito.
 * Dominio e trilha entram na MESMA transacao — aceite sem trilha nao existe.
 */
import { createHash, randomUUID } from 'node:crypto';

import type { Client } from '@libsql/client';

import { comandoDeAuditoria } from './audit.js';

export const TIPO_DO_TERMO_DO_OPERADOR = 'tos' as const;
export const METODO_DE_ACEITE = 'cms_interface' as const;

const AGORA = `strftime('%Y-%m-%dT%H:%M:%fZ','now')`;

export interface DocumentoVigente {
  type: 'tos';
  version: string;
  contentMd: string;
  hash: string;
  effectiveFrom: string;
}

export function normalizarTexto(texto: string): string {
  return texto.replace(/^﻿/, '').replace(/\r\n/g, '\n');
}

/** Puro: quem chama normaliza antes. */
export function hashDoTexto(contentMd: string): string {
  return createHash('sha256').update(contentMd, 'utf8').digest('hex');
}

export async function documentoVigente(client: Client): Promise<DocumentoVigente | null> {
  const r = await client.execute({
    sql: `SELECT version, content_md, content_hash, effective_from FROM legal_document
          WHERE type = ? ORDER BY effective_from DESC, rowid DESC LIMIT 1`,
    args: [TIPO_DO_TERMO_DO_OPERADOR],
  });
  const l = r.rows[0];
  if (!l) return null;
  return {
    type: TIPO_DO_TERMO_DO_OPERADOR,
    version: String(l.version),
    contentMd: String(l.content_md),
    hash: String(l.content_hash),
    effectiveFrom: String(l.effective_from),
  };
}

export async function publicarDocumento(
  client: Client,
  salt: string,
  entrada: { version: string; contentMd: string },
  autorId: string | null,
): Promise<DocumentoVigente> {
  const contentMd = normalizarTexto(entrada.contentMd);
  if (contentMd.trim() === '') throw new Error('publicarDocumento: texto vazio.');
  const hash = hashDoTexto(contentMd);
  const vigente = await documentoVigente(client);
  if (vigente?.hash === hash) {
    throw new Error('publicarDocumento: texto identico ao vigente; nao se forca re-aceite.');
  }
  const id = randomUUID();
  await client.batch(
    [
      {
        sql: `INSERT INTO legal_document (id, type, version, content_md, content_hash, effective_from)
              VALUES (?, ?, ?, ?, ?, ${AGORA})`,
        args: [id, TIPO_DO_TERMO_DO_OPERADOR, entrada.version, contentMd, hash],
      },
      comandoDeAuditoria(salt, {
        actorId: autorId,
        action: 'legal_publish',
        entityType: 'legal_document',
        entityId: id,
        after: { type: TIPO_DO_TERMO_DO_OPERADOR, version: entrada.version, hash },
      }),
    ],
    'write',
  );
  return (await documentoVigente(client))!;
}

export async function aceitouVigente(client: Client, subjectRef: string): Promise<boolean> {
  const v = await documentoVigente(client);
  if (!v) return false;
  const r = await client.execute({
    sql: `SELECT 1 FROM consent_record
          WHERE subject_ref = ? AND doc_type = ? AND doc_version = ? AND doc_hash = ? LIMIT 1`,
    args: [subjectRef, TIPO_DO_TERMO_DO_OPERADOR, v.version, v.hash],
  });
  return r.rows.length > 0;
}

export type ResultadoAceite =
  | { ok: true; documento: DocumentoVigente }
  | { ok: false; motivo: 'sem_documento' }
  | { ok: false; motivo: 'desatualizado'; documento: DocumentoVigente };

export async function registrarAceite(
  client: Client,
  salt: string,
  subjectRef: string,
  visto: { version: string; hash: string },
): Promise<ResultadoAceite> {
  const documento = await documentoVigente(client);
  if (!documento) return { ok: false, motivo: 'sem_documento' };
  if (visto.version !== documento.version || visto.hash !== documento.hash) {
    return { ok: false, motivo: 'desatualizado', documento };
  }
  const id = randomUUID();
  const chave = [subjectRef, TIPO_DO_TERMO_DO_OPERADOR, documento.version, documento.hash];
  // Sem indice unico de proposito: nao pode impedir re-aceite apos revogacao
  // (LGPD-RF05). A idempotencia e o NOT EXISTS; a trilha so entra se esta linha entrou.
  await client.batch(
    [
      {
        sql: `INSERT INTO consent_record (id, subject_ref, doc_type, doc_version, doc_hash, method, accepted_at)
              SELECT ?, ?, ?, ?, ?, ?, ${AGORA}
              WHERE NOT EXISTS (SELECT 1 FROM consent_record
                WHERE subject_ref = ? AND doc_type = ? AND doc_version = ? AND doc_hash = ?)`,
        args: [id, ...chave, METODO_DE_ACEITE, ...chave],
      },
      comandoDeAuditoria(
        salt,
        {
          actorId: subjectRef,
          action: 'consent_accept',
          entityType: 'consent_record',
          entityId: id,
          after: {
            docType: TIPO_DO_TERMO_DO_OPERADOR,
            docVersion: documento.version,
            docHash: documento.hash,
          },
        },
        { sql: 'EXISTS (SELECT 1 FROM consent_record WHERE id = ?)', args: [id] },
      ),
    ],
    'write',
  );
  return { ok: true, documento };
}
