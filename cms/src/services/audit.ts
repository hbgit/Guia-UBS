/**
 * Escritor unico da trilha de auditoria (lgpd.md LGPD-RT03).
 *
 * "Unico" e a razao de o modulo existir. `audit_entry` e append-only por gatilho
 * — ninguem consegue apagar depois —, mas nada impede varios lugares de
 * ESCREVEREM em formatos diferentes, e uma trilha com tres dialetos e uma trilha
 * que ninguem consegue ler numa auditoria.
 *
 * ## O que NUNCA entra
 *
 * **O corpo da requisicao.** Ele carrega senha, codigo TOTP e codigo de
 * recuperacao. O que entra e caminho, resultado, ator e entidade — o suficiente
 * para reconstruir quem fez o que, e insuficiente para reproduzir a credencial.
 *
 * **O IP em claro.** Vai `sha256(sal + ip)`. Ver `auth/pseudonymize.ts` para por
 * que o sal nao e detalhe.
 *
 * **O e-mail de quem falhou o login.** A entidade e o identificador ja hasheado:
 * uma trilha que registra "tentativa de login em maria@..." e uma lista de quem
 * tem conta, legivel por qualquer um com acesso de leitura.
 */
import { randomUUID } from 'node:crypto';

import type { Client, InStatement, InValue } from '@libsql/client';

import { pseudonymize } from '../auth/pseudonymize.js';

export interface AuditEvent {
  /**
   * Quem agiu. `null` quando a acao nao chegou a autenticar ninguem — login
   * recusado, por exemplo. E parametro OBRIGATORIO mesmo podendo ser nulo: cada
   * chamada precisa decidir conscientemente que nao ha ator, em vez de omitir.
   */
  actorId: string | null;
  /** Verbo curto e estavel: `sign_in`, `sign_in_failed`, `user_create`… */
  action: string;
  entityType: string;
  entityId: string;
  /** Estado antes e depois, ja SEM credencial. Serializados como JSON. */
  before?: unknown;
  after?: unknown;
  /** IP bruto — hasheado aqui dentro, nunca gravado como veio. */
  ip?: string | null;
}

/**
 * Bytes NUNCA entram na trilha, e recusar e melhor que descartar.
 *
 * `audit_entry` e append-only por gatilho: o que entra ali nao sai mais, nem
 * pelo expurgo de retencao que a LGPD-RF07 ainda vai exigir. Um blob de asset
 * gravado por engano seria permanente, e cresceria a tabela em megabytes por
 * envio.
 *
 * Descartar em silencio seria pior que lancar: a trilha passaria a registrar um
 * `after` incompleto sem que nada dissesse isso, e uma trilha que omite mente
 * sobre o que viu. Quem chama decide o que registrar — no caso do asset, os dois
 * `sha256`, que respondem "quem trocou quais bytes por quais" em 200 bytes.
 */
function recusarBytes(rotulo: string, valor: unknown, profundidade = 0): void {
  if (valor === null || typeof valor !== 'object' || profundidade > 4) return;
  if (ArrayBuffer.isView(valor) || valor instanceof ArrayBuffer) {
    throw new Error(
      `recordAudit: "${rotulo}" carrega bytes. A trilha e append-only — registre o ` +
        'sha256, nao o conteudo.',
    );
  }
  for (const item of Object.values(valor)) recusarBytes(rotulo, item, profundidade + 1);
}

/**
 * Instrucao de insercao na trilha, para quem precisa gravar a trilha NA MESMA
 * transacao (`client.batch`) de outra escrita. `condicao` opcional vira `WHERE`:
 * a trilha so entra se a escrita irma entrou.
 */
export function comandoDeAuditoria(
  salt: string,
  event: AuditEvent,
  condicao?: { sql: string; args: InValue[] },
): InStatement {
  recusarBytes('before', event.before);
  recusarBytes('after', event.after);
  return {
    // Relogio do BANCO, nao do processo: `occurred_at` e comparado com
    // `pack_release.blocked_at`, carimbado pelo mesmo `sqld` (P0-2, D11). Mesmo
    // formato de `toISOString()`, entao a ordem textual com linhas antigas vale.
    sql:
      `INSERT INTO audit_entry (id, actor_id, action, entity_type, entity_id, before_json, after_json, ip_hash, occurred_at)
       SELECT ?, ?, ?, ?, ?, ?, ?, ?, strftime('%Y-%m-%dT%H:%M:%fZ','now')` +
      (condicao ? ` WHERE ${condicao.sql}` : ''),
    args: [
      randomUUID(),
      event.actorId,
      event.action,
      event.entityType,
      event.entityId,
      event.before === undefined ? null : JSON.stringify(event.before),
      event.after === undefined ? null : JSON.stringify(event.after),
      event.ip ? pseudonymize(event.ip, salt) : null,
      ...(condicao?.args ?? []),
    ],
  };
}

export async function recordAudit(
  client: Client,
  salt: string,
  event: AuditEvent,
): Promise<void> {
  await client.execute(comandoDeAuditoria(salt, event));
}
