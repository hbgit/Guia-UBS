PRAGMA foreign_keys=OFF;--> statement-breakpoint
CREATE TABLE `__new_audit_entry` (
	`id` text PRIMARY KEY NOT NULL,
	`actor_id` text,
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
INSERT INTO `__new_audit_entry`("id", "actor_id", "action", "entity_type", "entity_id", "before_json", "after_json", "ip_hash", "occurred_at") SELECT "id", "actor_id", "action", "entity_type", "entity_id", "before_json", "after_json", "ip_hash", "occurred_at" FROM `audit_entry`;--> statement-breakpoint
DROP TABLE `audit_entry`;--> statement-breakpoint
ALTER TABLE `__new_audit_entry` RENAME TO `audit_entry`;--> statement-breakpoint
PRAGMA foreign_keys=ON;