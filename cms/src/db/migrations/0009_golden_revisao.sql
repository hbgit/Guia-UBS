CREATE TABLE `golden_attestation` (
	`id` text PRIMARY KEY NOT NULL,
	`nome` text NOT NULL,
	`conselho` text NOT NULL,
	`uf` text NOT NULL,
	`categoria` text,
	`registro` text NOT NULL,
	`termo_sha256` text NOT NULL,
	`created_by` text NOT NULL,
	`created_at` text NOT NULL,
	FOREIGN KEY (`created_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action,
	CONSTRAINT "golden_attestation_conselho_valid" CHECK("golden_attestation"."conselho" IN ('CRM', 'COREN')),
	CONSTRAINT "golden_attestation_uf_valid" CHECK("golden_attestation"."uf" IN ('AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS', 'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO')),
	CONSTRAINT "golden_attestation_categoria_valid" CHECK(("golden_attestation"."conselho" = 'COREN' AND "golden_attestation"."categoria" IS NOT NULL AND "golden_attestation"."categoria" IN ('ENF')) OR ("golden_attestation"."conselho" = 'CRM' AND "golden_attestation"."categoria" IS NULL)),
	CONSTRAINT "golden_attestation_termo_hex" CHECK(length("golden_attestation"."termo_sha256") = 64 AND "golden_attestation"."termo_sha256" NOT GLOB '*[^0-9a-f]*')
);
--> statement-breakpoint
CREATE UNIQUE INDEX `golden_attestation_profissional` ON `golden_attestation` (`conselho`,`uf`,`registro`);--> statement-breakpoint
CREATE UNIQUE INDEX `golden_attestation_termo` ON `golden_attestation` (`termo_sha256`);--> statement-breakpoint
CREATE TABLE `golden_case_review` (
	`id` text PRIMARY KEY NOT NULL,
	`case_id` text NOT NULL,
	`attestation_id` text NOT NULL,
	`reviewed_at` text NOT NULL,
	`recorded_by` text NOT NULL,
	`recorded_at` text NOT NULL,
	FOREIGN KEY (`case_id`) REFERENCES `golden_case`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`attestation_id`) REFERENCES `golden_attestation`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`recorded_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `golden_case_review_case_attestation` ON `golden_case_review` (`case_id`,`attestation_id`);--> statement-breakpoint
PRAGMA foreign_keys=OFF;--> statement-breakpoint
CREATE TABLE `__new_golden_case` (
	`id` text PRIMARY KEY NOT NULL,
	`tokens_json` text NOT NULL,
	`expected_outcome_id` text NOT NULL,
	`clinical_source` text,
	`added_by` text NOT NULL,
	`active` integer DEFAULT 1 NOT NULL,
	FOREIGN KEY (`added_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
INSERT INTO `__new_golden_case`("id", "tokens_json", "expected_outcome_id", "clinical_source", "added_by", "active") SELECT "id", "tokens_json", "expected_outcome_id", "clinical_source", "added_by", "active" FROM `golden_case`;--> statement-breakpoint
DROP TABLE `golden_case`;--> statement-breakpoint
ALTER TABLE `__new_golden_case` RENAME TO `golden_case`;--> statement-breakpoint
PRAGMA foreign_keys=ON;--> statement-breakpoint
ALTER TABLE `pack_release` ADD `blocked_at` text;