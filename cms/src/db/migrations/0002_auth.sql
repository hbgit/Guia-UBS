CREATE TABLE `account` (
	`id` text PRIMARY KEY NOT NULL,
	`issuer` text NOT NULL,
	`account_id` text NOT NULL,
	`provider_id` text NOT NULL,
	`user_id` text NOT NULL,
	`access_token` text,
	`refresh_token` text,
	`id_token` text,
	`access_token_expires_at` integer,
	`refresh_token_expires_at` integer,
	`scope` text,
	`password` text,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `account_issuer_account_uidx` ON `account` (`issuer`,`account_id`);--> statement-breakpoint
CREATE INDEX `account_user_idx` ON `account` (`user_id`);--> statement-breakpoint
CREATE TABLE `login_attempt` (
	`subject_key` text PRIMARY KEY NOT NULL,
	`failures` integer DEFAULT 0 NOT NULL,
	`last_failure_at` text,
	`locked_until` text,
	CONSTRAINT "login_attempt_failures_positive" CHECK("login_attempt"."failures" >= 0)
);
--> statement-breakpoint
CREATE TABLE `session` (
	`id` text PRIMARY KEY NOT NULL,
	`expires_at` integer NOT NULL,
	`token` text NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	`ip_address` text,
	`user_agent` text,
	`user_id` text NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `session_token_unique` ON `session` (`token`);--> statement-breakpoint
CREATE INDEX `session_user_idx` ON `session` (`user_id`);--> statement-breakpoint
CREATE TABLE `two_factor` (
	`id` text PRIMARY KEY NOT NULL,
	`secret` text NOT NULL,
	`backup_codes` text NOT NULL,
	`user_id` text NOT NULL,
	`verified` integer DEFAULT true,
	`failed_verification_count` integer DEFAULT 0,
	`locked_until` integer,
	FOREIGN KEY (`user_id`) REFERENCES `admin_user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `two_factor_user_idx` ON `two_factor` (`user_id`);--> statement-breakpoint
CREATE TABLE `verification` (
	`id` text PRIMARY KEY NOT NULL,
	`identifier` text NOT NULL,
	`value` text NOT NULL,
	`expires_at` integer NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE INDEX `verification_identifier_idx` ON `verification` (`identifier`);--> statement-breakpoint
PRAGMA foreign_keys=OFF;--> statement-breakpoint
CREATE TABLE `__new_admin_user` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`email` text NOT NULL,
	`email_verified` integer DEFAULT false NOT NULL,
	`image` text,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	`two_factor_enabled` integer DEFAULT false,
	`role` text NOT NULL,
	`disabled_at` integer,
	CONSTRAINT "admin_user_role_valid" CHECK("__new_admin_user"."role" IN ('editor', 'clinical_reviewer', 'admin'))
);
--> statement-breakpoint
-- CORRIGIDO A MAO sobre a saida do drizzle-kit. Duas coisas ele nao tinha como
-- saber, e as duas quebram a migracao:
--
--   1. `email_verified`, `image`, `updated_at` e `two_factor_enabled` NAO existem
--      na tabela antiga. O SELECT gerado as lia da origem e falhava com
--      "no such column".
--   2. `created_at` e `disabled_at` mudam de TEXT ISO-8601 para INTEGER
--      milissegundos (o Better Auth passa objetos Date ao adapter). Copiar o
--      texto gravaria a string ISO numa coluna INTEGER, e o SQLite aceitaria
--      calado — toda data do sistema viraria lixo silencioso.
--
-- `updated_at` recebe o `created_at` convertido: a linha nunca foi editada.
INSERT INTO `__new_admin_user`("id", "name", "email", "email_verified", "image", "created_at", "updated_at", "two_factor_enabled", "role", "disabled_at")
SELECT
  "id",
  "name",
  "email",
  0,
  NULL,
  unixepoch("created_at") * 1000,
  unixepoch("created_at") * 1000,
  0,
  "role",
  CASE WHEN "disabled_at" IS NULL THEN NULL ELSE unixepoch("disabled_at") * 1000 END
FROM `admin_user`;--> statement-breakpoint
DROP TABLE `admin_user`;--> statement-breakpoint
ALTER TABLE `__new_admin_user` RENAME TO `admin_user`;--> statement-breakpoint
PRAGMA foreign_keys=ON;--> statement-breakpoint
CREATE UNIQUE INDEX `admin_user_email_unique` ON `admin_user` (`email`);