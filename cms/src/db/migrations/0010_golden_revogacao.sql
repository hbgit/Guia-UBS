CREATE TABLE `golden_case_review_revocation` (
	`id` text PRIMARY KEY NOT NULL,
	`review_id` text NOT NULL,
	`reason` text NOT NULL,
	`revoked_by` text NOT NULL,
	`revoked_at` text NOT NULL,
	FOREIGN KEY (`review_id`) REFERENCES `golden_case_review`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`revoked_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action,
	CONSTRAINT "golden_case_review_revocation_reason_len" CHECK(length(trim("golden_case_review_revocation"."reason", ' ' || char(9, 10, 13))) >= 10)
);
--> statement-breakpoint
CREATE UNIQUE INDEX `golden_case_review_revocation_review_id_unique` ON `golden_case_review_revocation` (`review_id`);--> statement-breakpoint
PRAGMA foreign_keys=OFF;--> statement-breakpoint
CREATE TABLE `__new_golden_case_review` (
	`id` text PRIMARY KEY NOT NULL,
	`case_id` text NOT NULL,
	`attestation_id` text NOT NULL,
	`reviewed_at` text NOT NULL,
	`recorded_by` text NOT NULL,
	`recorded_at` text NOT NULL,
	`reviewed_hash` text,
	FOREIGN KEY (`case_id`) REFERENCES `golden_case`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`attestation_id`) REFERENCES `golden_attestation`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`recorded_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action,
	CONSTRAINT "golden_case_review_hash_hex" CHECK(length("__new_golden_case_review"."reviewed_hash") = 64 AND "__new_golden_case_review"."reviewed_hash" NOT GLOB '*[^0-9a-f]*')
);
--> statement-breakpoint
-- Editado a mao: o drizzle-kit copiava `reviewed_hash`, que a tabela antiga nao tem. Linha legada fica com NULL.
INSERT INTO `__new_golden_case_review`("id", "case_id", "attestation_id", "reviewed_at", "recorded_by", "recorded_at") SELECT "id", "case_id", "attestation_id", "reviewed_at", "recorded_by", "recorded_at" FROM `golden_case_review`;--> statement-breakpoint
DROP TABLE `golden_case_review`;--> statement-breakpoint
ALTER TABLE `__new_golden_case_review` RENAME TO `golden_case_review`;--> statement-breakpoint
PRAGMA foreign_keys=ON;--> statement-breakpoint
ALTER TABLE `golden_case` ADD `deactivated_at` text;