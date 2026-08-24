CREATE TABLE `admin_user` (
	`id` text PRIMARY KEY NOT NULL,
	`email` text NOT NULL,
	`name` text NOT NULL,
	`password_hash` text NOT NULL,
	`role` text NOT NULL,
	`totp_secret_enc` text,
	`disabled_at` text,
	`created_at` text NOT NULL,
	CONSTRAINT "admin_user_role_valid" CHECK("admin_user"."role" IN ('editor', 'clinical_reviewer', 'admin'))
);
--> statement-breakpoint
CREATE UNIQUE INDEX `admin_user_email_unique` ON `admin_user` (`email`);--> statement-breakpoint
CREATE TABLE `asset` (
	`ref` text PRIMARY KEY NOT NULL,
	`kind` text NOT NULL,
	`path` text NOT NULL,
	`sha256` text NOT NULL,
	`bytes` integer NOT NULL,
	`storage_key` text NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_by` text NOT NULL,
	`updated_at` text NOT NULL,
	FOREIGN KEY (`updated_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `card` (
	`id` text PRIMARY KEY NOT NULL,
	`kind` text NOT NULL,
	`icon_ref` text NOT NULL,
	`color_token` text NOT NULL,
	`sort_order` integer DEFAULT 0 NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_by` text NOT NULL,
	`updated_at` text NOT NULL,
	FOREIGN KEY (`icon_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`updated_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action,
	CONSTRAINT "card_color_valid" CHECK("card"."color_token" IN ('green', 'red', 'blue'))
);
--> statement-breakpoint
CREATE TABLE `card_translation` (
	`card_id` text NOT NULL,
	`lang` text NOT NULL,
	`title` text NOT NULL,
	`body` text,
	`audio_ref` text,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_by` text NOT NULL,
	`updated_at` text NOT NULL,
	PRIMARY KEY(`card_id`, `lang`),
	FOREIGN KEY (`card_id`) REFERENCES `card`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`audio_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`updated_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `card_translation_lang_idx` ON `card_translation` (`lang`);--> statement-breakpoint
CREATE TABLE `document` (
	`municipality_id` text NOT NULL,
	`id` text NOT NULL,
	`icon_ref` text NOT NULL,
	`image_ref` text,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_by` text NOT NULL,
	`updated_at` text NOT NULL,
	PRIMARY KEY(`municipality_id`, `id`),
	FOREIGN KEY (`municipality_id`) REFERENCES `municipality`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`icon_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`image_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`updated_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `document_translation` (
	`municipality_id` text NOT NULL,
	`document_id` text NOT NULL,
	`lang` text NOT NULL,
	`label` text NOT NULL,
	`hint` text,
	`audio_ref` text,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_by` text NOT NULL,
	`updated_at` text NOT NULL,
	PRIMARY KEY(`municipality_id`, `document_id`, `lang`),
	FOREIGN KEY (`audio_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`updated_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`municipality_id`,`document_id`) REFERENCES `document`(`municipality_id`,`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `flow_step` (
	`municipality_id` text NOT NULL,
	`id` text NOT NULL,
	`venue_id` text NOT NULL,
	`step_order` integer NOT NULL,
	`icon_ref` text NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_by` text NOT NULL,
	`updated_at` text NOT NULL,
	PRIMARY KEY(`municipality_id`, `id`),
	FOREIGN KEY (`municipality_id`) REFERENCES `municipality`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`venue_id`) REFERENCES `venue`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`icon_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`updated_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `flow_step_venue_order_idx` ON `flow_step` (`municipality_id`,`venue_id`,`step_order`);--> statement-breakpoint
CREATE TABLE `flow_step_translation` (
	`municipality_id` text NOT NULL,
	`step_id` text NOT NULL,
	`lang` text NOT NULL,
	`title` text NOT NULL,
	`body` text,
	`audio_ref` text,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_by` text NOT NULL,
	`updated_at` text NOT NULL,
	PRIMARY KEY(`municipality_id`, `step_id`, `lang`),
	FOREIGN KEY (`audio_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`updated_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`municipality_id`,`step_id`) REFERENCES `flow_step`(`municipality_id`,`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `municipality` (
	`id` text PRIMARY KEY NOT NULL,
	`code` text NOT NULL,
	`name` text NOT NULL,
	`active` integer DEFAULT 1 NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `municipality_code_unique` ON `municipality` (`code`);--> statement-breakpoint
CREATE TABLE `routing_outcome` (
	`id` text PRIMARY KEY NOT NULL,
	`severity_level` integer NOT NULL,
	`card_id` text NOT NULL,
	`venue_id` text NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_by` text NOT NULL,
	`updated_at` text NOT NULL,
	FOREIGN KEY (`card_id`) REFERENCES `card`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`venue_id`) REFERENCES `venue`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`updated_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `routing_rule` (
	`id` text PRIMARY KEY NOT NULL,
	`priority` integer NOT NULL,
	`outcome_id` text NOT NULL,
	`rationale` text,
	`clinical_source` text,
	`status` text DEFAULT 'draft' NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_by` text NOT NULL,
	`updated_at` text NOT NULL,
	FOREIGN KEY (`outcome_id`) REFERENCES `routing_outcome`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`updated_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action,
	CONSTRAINT "routing_rule_status_valid" CHECK("routing_rule"."status" IN ('draft', 'approved'))
);
--> statement-breakpoint
CREATE TABLE `routing_rule_term` (
	`rule_id` text NOT NULL,
	`group_no` integer NOT NULL,
	`token_id` text NOT NULL,
	`negated` integer DEFAULT 0 NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_by` text NOT NULL,
	`updated_at` text NOT NULL,
	PRIMARY KEY(`rule_id`, `group_no`, `token_id`),
	FOREIGN KEY (`rule_id`) REFERENCES `routing_rule`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`token_id`) REFERENCES `symptom_token`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`updated_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `routing_rule_term_token_idx` ON `routing_rule_term` (`token_id`);--> statement-breakpoint
CREATE TABLE `service` (
	`municipality_id` text NOT NULL,
	`id` text NOT NULL,
	`venue_id` text NOT NULL,
	`icon_ref` text NOT NULL,
	`sort_order` integer DEFAULT 0 NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_by` text NOT NULL,
	`updated_at` text NOT NULL,
	PRIMARY KEY(`municipality_id`, `id`),
	FOREIGN KEY (`municipality_id`) REFERENCES `municipality`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`venue_id`) REFERENCES `venue`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`icon_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`updated_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `service_document` (
	`municipality_id` text NOT NULL,
	`service_id` text NOT NULL,
	`document_id` text NOT NULL,
	`required` integer DEFAULT 1 NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_by` text NOT NULL,
	`updated_at` text NOT NULL,
	PRIMARY KEY(`municipality_id`, `service_id`, `document_id`),
	FOREIGN KEY (`updated_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`municipality_id`,`service_id`) REFERENCES `service`(`municipality_id`,`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`municipality_id`,`document_id`) REFERENCES `document`(`municipality_id`,`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `service_document_document_idx` ON `service_document` (`municipality_id`,`document_id`);--> statement-breakpoint
CREATE TABLE `service_translation` (
	`municipality_id` text NOT NULL,
	`service_id` text NOT NULL,
	`lang` text NOT NULL,
	`label` text NOT NULL,
	`audio_ref` text,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_by` text NOT NULL,
	`updated_at` text NOT NULL,
	PRIMARY KEY(`municipality_id`, `service_id`, `lang`),
	FOREIGN KEY (`audio_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`updated_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`municipality_id`,`service_id`) REFERENCES `service`(`municipality_id`,`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `symptom_token` (
	`id` text PRIMARY KEY NOT NULL,
	`kind` text NOT NULL,
	`icon_ref` text NOT NULL,
	`sort_order` integer DEFAULT 0 NOT NULL,
	`deprecated` integer DEFAULT 0 NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_by` text NOT NULL,
	`updated_at` text NOT NULL,
	FOREIGN KEY (`icon_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`updated_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `token_translation` (
	`token_id` text NOT NULL,
	`lang` text NOT NULL,
	`label` text NOT NULL,
	`audio_ref` text,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_by` text NOT NULL,
	`updated_at` text NOT NULL,
	PRIMARY KEY(`token_id`, `lang`),
	FOREIGN KEY (`token_id`) REFERENCES `symptom_token`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`audio_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`updated_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `venue` (
	`id` text PRIMARY KEY NOT NULL,
	`icon_ref` text NOT NULL,
	`color_token` text NOT NULL,
	`sort_order` integer DEFAULT 0 NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_by` text NOT NULL,
	`updated_at` text NOT NULL,
	FOREIGN KEY (`icon_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`updated_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action,
	CONSTRAINT "venue_color_valid" CHECK("venue"."color_token" IN ('green', 'red', 'blue'))
);
--> statement-breakpoint
CREATE TABLE `venue_translation` (
	`venue_id` text NOT NULL,
	`lang` text NOT NULL,
	`label` text NOT NULL,
	`audio_ref` text,
	`version` integer DEFAULT 1 NOT NULL,
	`updated_by` text NOT NULL,
	`updated_at` text NOT NULL,
	PRIMARY KEY(`venue_id`, `lang`),
	FOREIGN KEY (`venue_id`) REFERENCES `venue`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`audio_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`updated_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `audit_entry` (
	`id` text PRIMARY KEY NOT NULL,
	`actor_id` text NOT NULL,
	`action` text NOT NULL,
	`entity_type` text NOT NULL,
	`entity_id` text NOT NULL,
	`before_json` text,
	`after_json` text,
	`ip_hash` text,
	`occurred_at` text NOT NULL,
	FOREIGN KEY (`actor_id`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `consent_record` (
	`id` text PRIMARY KEY NOT NULL,
	`subject_ref` text NOT NULL,
	`doc_type` text NOT NULL,
	`doc_version` text NOT NULL,
	`doc_hash` text NOT NULL,
	`method` text NOT NULL,
	`accepted_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `legal_document` (
	`id` text PRIMARY KEY NOT NULL,
	`type` text NOT NULL,
	`version` text NOT NULL,
	`content_md` text NOT NULL,
	`content_hash` text NOT NULL,
	`effective_from` text NOT NULL,
	CONSTRAINT "legal_document_type_valid" CHECK("legal_document"."type" IN ('tos', 'privacy', 'consent'))
);
--> statement-breakpoint
CREATE UNIQUE INDEX `legal_document_type_version` ON `legal_document` (`type`,`version`);--> statement-breakpoint
CREATE TABLE `approval` (
	`id` text PRIMARY KEY NOT NULL,
	`pack_release_id` text NOT NULL,
	`approver_id` text NOT NULL,
	`role` text NOT NULL,
	`decision` text NOT NULL,
	`comment` text,
	`decided_at` text NOT NULL,
	FOREIGN KEY (`pack_release_id`) REFERENCES `pack_release`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`approver_id`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action,
	CONSTRAINT "approval_decision_valid" CHECK("approval"."decision" IN ('approve', 'reject')),
	CONSTRAINT "approval_role_valid" CHECK("approval"."role" IN ('editor', 'clinical_reviewer', 'admin'))
);
--> statement-breakpoint
CREATE TABLE `golden_case` (
	`id` text PRIMARY KEY NOT NULL,
	`tokens_json` text NOT NULL,
	`expected_outcome_id` text NOT NULL,
	`clinical_source` text,
	`added_by` text NOT NULL,
	`reviewed_by` text,
	`active` integer DEFAULT 1 NOT NULL,
	FOREIGN KEY (`added_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`reviewed_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `golden_run` (
	`id` text PRIMARY KEY NOT NULL,
	`pack_release_id` text NOT NULL,
	`passed` integer NOT NULL,
	`total` integer NOT NULL,
	`failures_json` text,
	`ran_at` text NOT NULL,
	FOREIGN KEY (`pack_release_id`) REFERENCES `pack_release`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `pack_release` (
	`id` text PRIMARY KEY NOT NULL,
	`municipality_id` text NOT NULL,
	`pack_version` integer NOT NULL,
	`schema_version` text NOT NULL,
	`status` text DEFAULT 'draft' NOT NULL,
	`pack_sha256` text,
	`manifest_json` text,
	`signed_at` text,
	`published_at` text,
	`created_by` text NOT NULL,
	`created_at` text NOT NULL,
	FOREIGN KEY (`municipality_id`) REFERENCES `municipality`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`created_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action,
	CONSTRAINT "pack_release_status_valid" CHECK("pack_release"."status" IN ('draft', 'pending_review', 'approved', 'built', 'published', 'revoked')),
	CONSTRAINT "pack_release_version_positive" CHECK("pack_release"."pack_version" > 0)
);
--> statement-breakpoint
CREATE UNIQUE INDEX `pack_release_municipality_version` ON `pack_release` (`municipality_id`,`pack_version`);--> statement-breakpoint
CREATE TABLE `signing_key` (
	`key_id` text PRIMARY KEY NOT NULL,
	`public_key` text NOT NULL,
	`activated_at` text NOT NULL,
	`retired_at` text
);
--> statement-breakpoint
CREATE TABLE `telemetry_batch` (
	`id` text PRIMARY KEY NOT NULL,
	`cohort_key` text NOT NULL,
	`bucket_day` text NOT NULL,
	`metrics_json` text NOT NULL,
	`k_count` integer NOT NULL,
	`received_at` text NOT NULL,
	CONSTRAINT "telemetry_batch_k_anonymity" CHECK("telemetry_batch"."k_count" >= 20)
);
--> statement-breakpoint
CREATE UNIQUE INDEX `telemetry_batch_cohort_day` ON `telemetry_batch` (`cohort_key`,`bucket_day`);