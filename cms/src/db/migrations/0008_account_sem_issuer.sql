DROP INDEX `account_issuer_account_uidx`;--> statement-breakpoint
CREATE UNIQUE INDEX `account_provider_account_uidx` ON `account` (`provider_id`,`account_id`);--> statement-breakpoint
ALTER TABLE `account` DROP COLUMN `issuer`;