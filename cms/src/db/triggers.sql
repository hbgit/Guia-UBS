-- GERADO por src/db/triggers.ts — nao editar a mao.
-- Rode: npm run cms:triggers
--
-- Aplicado por runMigrations() DEPOIS das migracoes do drizzle, a cada
-- execucao. Conjunto completo e idempotente: cada CREATE e precedido do DROP
-- correspondente.

DROP TRIGGER IF EXISTS `audit_entry_no_update`;
--> statement-breakpoint
CREATE TRIGGER `audit_entry_no_update`
BEFORE UPDATE ON `audit_entry`
BEGIN
  SELECT RAISE(ABORT, 'audit_entry e append-only (LGPD-RT03)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `audit_entry_no_delete`;
--> statement-breakpoint
CREATE TRIGGER `audit_entry_no_delete`
BEFORE DELETE ON `audit_entry`
BEGIN
  SELECT RAISE(ABORT, 'audit_entry e append-only (LGPD-RT03)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `consent_record_no_update`;
--> statement-breakpoint
CREATE TRIGGER `consent_record_no_update`
BEFORE UPDATE ON `consent_record`
BEGIN
  SELECT RAISE(ABORT, 'consent_record e append-only (LGPD-RT05)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `consent_record_no_delete`;
--> statement-breakpoint
CREATE TRIGGER `consent_record_no_delete`
BEFORE DELETE ON `consent_record`
BEGIN
  SELECT RAISE(ABORT, 'consent_record e append-only (LGPD-RT05)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `approval_no_update`;
--> statement-breakpoint
CREATE TRIGGER `approval_no_update`
BEFORE UPDATE ON `approval`
BEGIN
  SELECT RAISE(ABORT, 'approval e append-only (arquitetura.md 4.3-C)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `approval_no_delete`;
--> statement-breakpoint
CREATE TRIGGER `approval_no_delete`
BEFORE DELETE ON `approval`
BEGIN
  SELECT RAISE(ABORT, 'approval e append-only (arquitetura.md 4.3-C)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `municipality_version_monotonic`;
--> statement-breakpoint
CREATE TRIGGER `municipality_version_monotonic`
BEFORE UPDATE ON `municipality`
WHEN NEW.`version` <> OLD.`version` + 1
BEGIN
  SELECT RAISE(ABORT, 'municipality: version precisa subir de 1 a cada UPDATE (travamento otimista)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `asset_version_monotonic`;
--> statement-breakpoint
CREATE TRIGGER `asset_version_monotonic`
BEFORE UPDATE ON `asset`
WHEN NEW.`version` <> OLD.`version` + 1
BEGIN
  SELECT RAISE(ABORT, 'asset: version precisa subir de 1 a cada UPDATE (travamento otimista)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `symptom_token_version_monotonic`;
--> statement-breakpoint
CREATE TRIGGER `symptom_token_version_monotonic`
BEFORE UPDATE ON `symptom_token`
WHEN NEW.`version` <> OLD.`version` + 1
BEGIN
  SELECT RAISE(ABORT, 'symptom_token: version precisa subir de 1 a cada UPDATE (travamento otimista)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `token_translation_version_monotonic`;
--> statement-breakpoint
CREATE TRIGGER `token_translation_version_monotonic`
BEFORE UPDATE ON `token_translation`
WHEN NEW.`version` <> OLD.`version` + 1
BEGIN
  SELECT RAISE(ABORT, 'token_translation: version precisa subir de 1 a cada UPDATE (travamento otimista)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `routing_outcome_version_monotonic`;
--> statement-breakpoint
CREATE TRIGGER `routing_outcome_version_monotonic`
BEFORE UPDATE ON `routing_outcome`
WHEN NEW.`version` <> OLD.`version` + 1
BEGIN
  SELECT RAISE(ABORT, 'routing_outcome: version precisa subir de 1 a cada UPDATE (travamento otimista)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `routing_rule_version_monotonic`;
--> statement-breakpoint
CREATE TRIGGER `routing_rule_version_monotonic`
BEFORE UPDATE ON `routing_rule`
WHEN NEW.`version` <> OLD.`version` + 1
BEGIN
  SELECT RAISE(ABORT, 'routing_rule: version precisa subir de 1 a cada UPDATE (travamento otimista)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `routing_rule_term_version_monotonic`;
--> statement-breakpoint
CREATE TRIGGER `routing_rule_term_version_monotonic`
BEFORE UPDATE ON `routing_rule_term`
WHEN NEW.`version` <> OLD.`version` + 1
BEGIN
  SELECT RAISE(ABORT, 'routing_rule_term: version precisa subir de 1 a cada UPDATE (travamento otimista)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `venue_version_monotonic`;
--> statement-breakpoint
CREATE TRIGGER `venue_version_monotonic`
BEFORE UPDATE ON `venue`
WHEN NEW.`version` <> OLD.`version` + 1
BEGIN
  SELECT RAISE(ABORT, 'venue: version precisa subir de 1 a cada UPDATE (travamento otimista)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `venue_translation_version_monotonic`;
--> statement-breakpoint
CREATE TRIGGER `venue_translation_version_monotonic`
BEFORE UPDATE ON `venue_translation`
WHEN NEW.`version` <> OLD.`version` + 1
BEGIN
  SELECT RAISE(ABORT, 'venue_translation: version precisa subir de 1 a cada UPDATE (travamento otimista)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `card_version_monotonic`;
--> statement-breakpoint
CREATE TRIGGER `card_version_monotonic`
BEFORE UPDATE ON `card`
WHEN NEW.`version` <> OLD.`version` + 1
BEGIN
  SELECT RAISE(ABORT, 'card: version precisa subir de 1 a cada UPDATE (travamento otimista)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `card_translation_version_monotonic`;
--> statement-breakpoint
CREATE TRIGGER `card_translation_version_monotonic`
BEFORE UPDATE ON `card_translation`
WHEN NEW.`version` <> OLD.`version` + 1
BEGIN
  SELECT RAISE(ABORT, 'card_translation: version precisa subir de 1 a cada UPDATE (travamento otimista)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `service_version_monotonic`;
--> statement-breakpoint
CREATE TRIGGER `service_version_monotonic`
BEFORE UPDATE ON `service`
WHEN NEW.`version` <> OLD.`version` + 1
BEGIN
  SELECT RAISE(ABORT, 'service: version precisa subir de 1 a cada UPDATE (travamento otimista)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `service_translation_version_monotonic`;
--> statement-breakpoint
CREATE TRIGGER `service_translation_version_monotonic`
BEFORE UPDATE ON `service_translation`
WHEN NEW.`version` <> OLD.`version` + 1
BEGIN
  SELECT RAISE(ABORT, 'service_translation: version precisa subir de 1 a cada UPDATE (travamento otimista)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `document_version_monotonic`;
--> statement-breakpoint
CREATE TRIGGER `document_version_monotonic`
BEFORE UPDATE ON `document`
WHEN NEW.`version` <> OLD.`version` + 1
BEGIN
  SELECT RAISE(ABORT, 'document: version precisa subir de 1 a cada UPDATE (travamento otimista)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `document_translation_version_monotonic`;
--> statement-breakpoint
CREATE TRIGGER `document_translation_version_monotonic`
BEFORE UPDATE ON `document_translation`
WHEN NEW.`version` <> OLD.`version` + 1
BEGIN
  SELECT RAISE(ABORT, 'document_translation: version precisa subir de 1 a cada UPDATE (travamento otimista)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `service_document_version_monotonic`;
--> statement-breakpoint
CREATE TRIGGER `service_document_version_monotonic`
BEFORE UPDATE ON `service_document`
WHEN NEW.`version` <> OLD.`version` + 1
BEGIN
  SELECT RAISE(ABORT, 'service_document: version precisa subir de 1 a cada UPDATE (travamento otimista)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `flow_step_version_monotonic`;
--> statement-breakpoint
CREATE TRIGGER `flow_step_version_monotonic`
BEFORE UPDATE ON `flow_step`
WHEN NEW.`version` <> OLD.`version` + 1
BEGIN
  SELECT RAISE(ABORT, 'flow_step: version precisa subir de 1 a cada UPDATE (travamento otimista)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `flow_step_translation_version_monotonic`;
--> statement-breakpoint
CREATE TRIGGER `flow_step_translation_version_monotonic`
BEFORE UPDATE ON `flow_step_translation`
WHEN NEW.`version` <> OLD.`version` + 1
BEGIN
  SELECT RAISE(ABORT, 'flow_step_translation: version precisa subir de 1 a cada UPDATE (travamento otimista)');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `routing_rule_approved_immutable`;
--> statement-breakpoint
CREATE TRIGGER `routing_rule_approved_immutable`
BEFORE UPDATE ON `routing_rule`
WHEN OLD.`status` = 'approved'
BEGIN
  SELECT RAISE(ABORT, 'regra aprovada nao e editada in-place: crie uma linha nova');
END;
--> statement-breakpoint
DROP TRIGGER IF EXISTS `approval_no_self_approval`;
--> statement-breakpoint
CREATE TRIGGER `approval_no_self_approval`
BEFORE INSERT ON `approval`
WHEN NEW.`approver_id` = (
  SELECT `created_by` FROM `pack_release` WHERE `id` = NEW.`pack_release_id`
)
BEGIN
  SELECT RAISE(ABORT, 'quem cria a release nao aprova a propria release (LGPD-RF11)');
END;
