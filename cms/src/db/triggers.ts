/**
 * Gatilhos do banco master — gerados a partir das constantes de `schema/index.ts`.
 *
 * ## Por que nao sao migracao do drizzle-kit
 *
 * O drizzle-kit so emite `CREATE TABLE`. O caminho obvio seria
 * `generate --custom`, que cria um arquivo numerado e IMUTAVEL no journal — e ai
 * uma tabela versionada acrescentada daqui a tres meses exigiria uma migracao
 * nova so para os gatilhos dela, com o gerador incapaz de saber quais ja foram
 * emitidos. O conjunto de gatilhos passaria a viver espalhado por N arquivos
 * historicos, e a pergunta "quais gatilhos existem hoje?" deixaria de ter
 * resposta em um lugar so.
 *
 * Em vez disso: `triggers.sql` carrega o conjunto COMPLETO e atual, cada gatilho
 * precedido de `DROP TRIGGER IF EXISTS`. `runMigrations()` aplica as migracoes
 * do drizzle e entao este arquivo, sempre. Gatilho nao e dado; recria-lo e
 * idempotente e barato.
 *
 * ## Expurgo de retencao (lgpd.md LGPD-RF07 x LGPD-RT10)
 *
 * `BEFORE DELETE` incondicional colide com o prazo de retencao, que obriga a
 * eliminar. A resolucao e deliberada: o gatilho FICA incondicional, e o expurgo
 * e procedimento nomeado que derruba e recria os gatilhos dentro de uma
 * transacao, registrando a propria execucao em `audit_entry`.
 *
 * Assim o caminho de aplicacao — uma rota, um bug de ORM, uma sessao
 * comprometida — continua incapaz de apagar, que e a ameaca real, sem tornar
 * impossivel a obrigacao legal. O script do expurgo continua PENDENTE: depende
 * da tabela de retencao aprovada pelo encarregado, que ainda nao existe. O item
 * 19 nao o entregou, e a lacuna esta declarada em arquitetura.md 5.12.
 */
import { getTableName } from 'drizzle-orm';

import {
  APPEND_ONLY_TABLES,
  VERSION_COLUMN,
  VERSIONED_TABLES,
  approval,
  routingRule,
} from './schema/index.js';

/** Mesmo marcador que o drizzle-kit usa — um so jeito de partir SQL no repo. */
export const STATEMENT_BREAK = '--> statement-breakpoint';

const HEADER = `-- GERADO por src/db/triggers.ts — nao editar a mao.
-- Rode: npm run cms:triggers
--
-- Aplicado por runMigrations() DEPOIS das migracoes do drizzle, a cada
-- execucao. Conjunto completo e idempotente: cada CREATE e precedido do DROP
-- correspondente.
`;

/** Uma sentenca SQL por gatilho, ja com o DROP na frente. */
function trigger(name: string, definition: string): string[] {
  return [`DROP TRIGGER IF EXISTS \`${name}\``, definition.trim()];
}

/** Bloqueia UPDATE e DELETE: a linha existe para ser irrefutavel. */
function appendOnly(tableName: string, requirement: string): string[] {
  const message = `${tableName} e append-only (${requirement})`;
  return [
    ...trigger(
      `${tableName}_no_update`,
      `CREATE TRIGGER \`${tableName}_no_update\`
BEFORE UPDATE ON \`${tableName}\`
BEGIN
  SELECT RAISE(ABORT, '${message}');
END`,
    ),
    ...trigger(
      `${tableName}_no_delete`,
      `CREATE TRIGGER \`${tableName}_no_delete\`
BEFORE DELETE ON \`${tableName}\`
BEGIN
  SELECT RAISE(ABORT, '${message}');
END`,
    ),
  ];
}

/**
 * `version` sobe de exatamente 1 por UPDATE.
 *
 * Nao e `>` e sim `= OLD + 1`: um salto tambem denuncia escrita que nao passou
 * pelo caminho do travamento otimista, e o custo de ser estrito e zero para quem
 * usa `SET version = version + 1 WHERE id = ? AND version = ?`.
 */
function versionMonotonic(tableName: string): string[] {
  const name = `${tableName}_version_monotonic`;
  return trigger(
    name,
    `CREATE TRIGGER \`${name}\`
BEFORE UPDATE ON \`${tableName}\`
WHEN NEW.\`${VERSION_COLUMN}\` <> OLD.\`${VERSION_COLUMN}\` + 1
BEGIN
  SELECT RAISE(ABORT, '${tableName}: version precisa subir de 1 a cada UPDATE (travamento otimista)');
END`,
  );
}

/**
 * Regra aprovada nao e editada in-place: gera linha nova (arquitetura.md 4.3-B).
 *
 * O documento ja dizia isso. Uma frase de documento que nada aplica e uma frase
 * que alguem contraria sem perceber — e o que se contraria aqui e conteudo
 * clinico ja revisado em dupla.
 */
function approvedRuleImmutable(): string[] {
  const tableName = getTableName(routingRule);
  const name = `${tableName}_approved_immutable`;
  return trigger(
    name,
    `CREATE TRIGGER \`${name}\`
BEFORE UPDATE ON \`${tableName}\`
WHEN OLD.\`status\` = 'approved'
BEGIN
  SELECT RAISE(ABORT, 'regra aprovada nao e editada in-place: crie uma linha nova');
END`,
  );
}

/**
 * Quem cria a release nao aprova a propria release (lgpd.md LGPD-RF11).
 *
 * O item 17 deixou esta regra para o 19 argumentando que meia regra no banco
 * daria falsa impressao de que a regra inteira estava la. Com as duas metades no
 * mesmo item, a que E expressavel em SQL passa a ser estrutural — e a outra
 * ("ao menos um `clinical_reviewer`") fica em `services/approval-workflow.ts`,
 * porque e agregado sobre outras linhas e nao restricao de linha.
 *
 * Estar no banco importa: a segregacao de funcoes e a defesa contra o insider
 * (PRD, "conteudo incorreto por insider ou erro"), e uma checagem que mora so na
 * rota protege apenas contra quem passa pela rota.
 */
function noSelfApproval(): string[] {
  const tableName = getTableName(approval);
  const name = `${tableName}_no_self_approval`;
  return trigger(
    name,
    `CREATE TRIGGER \`${name}\`
BEFORE INSERT ON \`${tableName}\`
WHEN NEW.\`approver_id\` = (
  SELECT \`created_by\` FROM \`pack_release\` WHERE \`id\` = NEW.\`pack_release_id\`
)
BEGIN
  SELECT RAISE(ABORT, 'quem cria a release nao aprova a propria release (LGPD-RF11)');
END`,
  );
}

/** Todas as sentencas, na ordem em que sao aplicadas. */
export function triggerStatements(): string[] {
  return [
    ...APPEND_ONLY_TABLES.flatMap(({ table, requirement }) =>
      appendOnly(getTableName(table), requirement),
    ),
    ...VERSIONED_TABLES.flatMap((table) => versionMonotonic(getTableName(table))),
    ...approvedRuleImmutable(),
    ...noSelfApproval(),
  ];
}

/** O conteudo de `triggers.sql`. Deterministico: a ordem sai das constantes. */
export function buildTriggerSql(): string {
  return `${HEADER}\n${triggerStatements().join(`;\n${STATEMENT_BREAK}\n`)};\n`;
}
