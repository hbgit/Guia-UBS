PRAGMA foreign_keys=OFF;--> statement-breakpoint
CREATE TABLE `__new_pack_release` (
	`id` text PRIMARY KEY NOT NULL,
	`municipality_id` text NOT NULL,
	`pack_version` integer NOT NULL,
	`schema_version` text NOT NULL,
	`status` text DEFAULT 'draft' NOT NULL,
	`pack_sha256` text,
	`manifest_json` text,
	`signed_at` text,
	`published_at` text,
	`claimed_at` text,
	`created_by` text NOT NULL,
	`created_at` text NOT NULL,
	FOREIGN KEY (`municipality_id`) REFERENCES `municipality`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`created_by`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE no action,
	CONSTRAINT "pack_release_status_valid" CHECK("__new_pack_release"."status" IN ('draft', 'pending_review', 'approved', 'building', 'built', 'published', 'revoked')),
	CONSTRAINT "pack_release_version_positive" CHECK("__new_pack_release"."pack_version" > 0)
);
--> statement-breakpoint
-- CORRIGIDO A MAO sobre a saida do drizzle-kit, pelo mesmo motivo da 0002:
-- `claimed_at` NAO existe na tabela antiga, e o SELECT gerado a lia da origem.
-- Falharia com "no such column" em qualquer banco ja migrado.
--
-- Nenhuma release preexistente esta em `building` — o estado nasce aqui —, entao
-- NULL e o valor correto para todas.
INSERT INTO `__new_pack_release`("id", "municipality_id", "pack_version", "schema_version", "status", "pack_sha256", "manifest_json", "signed_at", "published_at", "claimed_at", "created_by", "created_at")
SELECT "id", "municipality_id", "pack_version", "schema_version", "status", "pack_sha256", "manifest_json", "signed_at", "published_at", NULL, "created_by", "created_at" FROM `pack_release`;--> statement-breakpoint
DROP TABLE `pack_release`;--> statement-breakpoint
ALTER TABLE `__new_pack_release` RENAME TO `pack_release`;--> statement-breakpoint
PRAGMA foreign_keys=ON;--> statement-breakpoint
CREATE UNIQUE INDEX `pack_release_municipality_version` ON `pack_release` (`municipality_id`,`pack_version`);