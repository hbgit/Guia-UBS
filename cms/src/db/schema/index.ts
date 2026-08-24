/**
 * Banco master do plano de controle — superficie unica.
 *
 * Alem de reexportar as tabelas, este modulo declara as LISTAS que governam o
 * banco: quais tabelas sao append-only, quais tem travamento otimista, quais
 * colunas carregam dado pessoal.
 *
 * Elas existem aqui, e nao dentro dos gatilhos ou dos testes, por um motivo
 * unico: `../triggers.ts` GERA o SQL a partir destas constantes e os testes as
 * PERCORREM. Uma lista redigida a parte envelhece e passa a mentir — e o mesmo
 * motivo pelo qual `app/test/prefs/lgpd_surface_test.dart` enumera colunas do
 * `user.db` em vez de conferir contra um texto escrito ao lado.
 *
 * Consequencia pratica: acrescentar tabela append-only e acrescentar uma linha
 * em `APPEND_ONLY_TABLES`. Esquecer de rodar `npm run cms:triggers` depois
 * reprova em `test/append-only.test.ts`, que verifica COMPORTAMENTO.
 */
import type { SQLiteTable } from 'drizzle-orm/sqlite-core';

import {
  asset,
  card,
  cardTranslation,
  document,
  documentTranslation,
  flowStep,
  flowStepTranslation,
  routingOutcome,
  routingRule,
  routingRuleTerm,
  service,
  serviceDocument,
  serviceTranslation,
  symptomToken,
  tokenTranslation,
  venue,
  venueTranslation,
} from './content.js';
import { auditEntry, consentRecord } from './governance.js';
import { approval } from './publishing.js';

export * from './auth.js';
export * from './content.js';
export * from './governance.js';
export * from './publishing.js';
export * from './telemetry.js';

/**
 * Tabelas onde UPDATE e DELETE sao proibidos por gatilho.
 *
 * As tres tem a mesma propriedade: seu valor esta em serem irrefutaveis. Uma
 * trilha de auditoria editavel nao prova quem fez o que; um aceite editavel nao
 * satisfaz o onus da prova do art. 8 §2 da Lei 13.709/2018; uma aprovacao
 * clinica editavel e um campo de estado, nao uma aprovacao.
 *
 * O requisito viaja junto para dentro da mensagem do RAISE — quem topar com o
 * erro em producao le por que a operacao foi recusada.
 */
export const APPEND_ONLY_TABLES: readonly { table: SQLiteTable; requirement: string }[] = [
  { table: auditEntry, requirement: 'LGPD-RT03' },
  { table: consentRecord, requirement: 'LGPD-RT05' },
  { table: approval, requirement: 'arquitetura.md 4.3-C' },
];

/**
 * Tabelas com travamento otimista: `version` precisa subir de exatamente 1 a
 * cada UPDATE.
 *
 * O gatilho e a razao de a coluna e a guarda nascerem no mesmo item. Sem ele, um
 * UPDATE que esqueca de incrementar `version` perde o travamento EM SILENCIO — a
 * proxima escrita concorrente sobrescreve sem 409, e o unico sintoma e a edicao
 * de alguem sumindo sem explicacao.
 */
export const VERSIONED_TABLES: readonly SQLiteTable[] = [
  asset,
  symptomToken,
  tokenTranslation,
  routingOutcome,
  routingRule,
  routingRuleTerm,
  venue,
  venueTranslation,
  card,
  cardTranslation,
  service,
  serviceTranslation,
  document,
  documentTranslation,
  serviceDocument,
  flowStep,
  flowStepTranslation,
];

/**
 * Colunas de dado pessoal (lgpd.md LGPD-RT02).
 *
 * O requisito pede marcacao NO SCHEMA via `COMMENT`; SQLite nao tem comentario
 * de coluna. Esta lista e o equivalente executavel: `test/invariants.test.ts`
 * reprova se qualquer coluna listada deixar de existir, o que transforma
 * "renomeei uma coluna de PII sem revisar a LGPD" em build vermelho.
 *
 * Nao ha dado de usuario final do app em lugar nenhum deste banco — o app nao
 * coleta identidade (INV-2). Os titulares aqui sao operadores do CMS e
 * participantes do piloto.
 *
 * `audit_entry.before_json` / `after_json` carregam PII quando a entidade
 * auditada e `admin_user`; sao JSON de forma livre e por isso nao entram nesta
 * lista de colunas tipadas, mas estao no alcance do expurgo por retencao.
 */
export const PII_COLUMNS: readonly string[] = [
  // Identidade do operador.
  'admin_user.email',
  'admin_user.name',
  // URL de foto exigida pelo core do Better Auth. NENHUMA rota nossa escreve
  // nela — declarada porque coluna de dado pessoal sem justificativa escrita e
  // o que a LGPD-RT02 proibe, e "existe mas ninguem usa" so vale se estiver dito.
  'admin_user.image',
  // Credenciais. O hash da senha mora em `account`, nao no usuario: e onde o
  // Better Auth procura.
  'account.password',
  'two_factor.secret',
  'two_factor.backup_codes',
  // PII de sessao VIVA, apagada no logout e na expiracao. A trilha permanente
  // guarda o IP so hasheado — sao coisas diferentes de proposito: a sessao
  // precisa do IP para detectar roubo de cookie; a trilha, nao.
  'session.ip_address',
  'session.user_agent',
  // Pseudonimizadas: hash com sal, nunca o valor em claro.
  'login_attempt.subject_key',
  'audit_entry.ip_hash',
  // Titular do aceite (operador ou participante do piloto).
  'consent_record.subject_ref',
];

/**
 * As UNICAS colunas que a autoria pode ter alem das do pack
 * (`contract/src/content-schema.ts`). Qualquer outra divergencia reprova em
 * `test/schema-conformance.test.ts`.
 */
export const AUTHORING_ONLY_COLUMNS: readonly string[] = [
  'version',
  'updated_by',
  'updated_at',
  'municipality_id',
  'storage_key',
  'status',
];

/**
 * Tabelas de conteudo da AUTORIA sem contraparte no pack, com o motivo escrito.
 * O teste de conformidade exige que toda excecao esteja aqui — nao ha "passa
 * porque sim".
 */
export const AUTHORING_TABLES_WITHOUT_PACK_COUNTERPART: Readonly<Record<string, string>> = {
  municipality:
    'o pack ja e de um municipio so; a contraparte e a coluna `pack_meta.municipality_code`',
};

/** Tabelas do PACK sem contraparte na autoria, com o motivo escrito. */
export const PACK_TABLES_WITHOUT_AUTHORING_COUNTERPART: Readonly<Record<string, string>> = {
  pack_meta:
    'carimbada pelo packer no momento do build, com versao e hash que so existem depois do artefato pronto; a contraparte e `pack_release`',
};

/** Coluna do travamento otimista. Os gatilhos e os testes leem daqui. */
export const VERSION_COLUMN = 'version';
