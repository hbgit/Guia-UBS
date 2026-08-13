CREATE TABLE `asset` (
	`ref` text PRIMARY KEY NOT NULL,
	`kind` text NOT NULL,
	`path` text NOT NULL,
	`sha256` text NOT NULL,
	`bytes` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `card` (
	`id` text PRIMARY KEY NOT NULL,
	`kind` text NOT NULL,
	`icon_ref` text NOT NULL,
	`color_token` text NOT NULL,
	`sort_order` integer DEFAULT 0 NOT NULL,
	FOREIGN KEY (`icon_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `card_translation` (
	`card_id` text NOT NULL,
	`lang` text NOT NULL,
	`title` text NOT NULL,
	`body` text,
	`audio_ref` text,
	PRIMARY KEY(`card_id`, `lang`),
	FOREIGN KEY (`card_id`) REFERENCES `card`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`audio_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `document` (
	`id` text PRIMARY KEY NOT NULL,
	`icon_ref` text NOT NULL,
	`image_ref` text,
	FOREIGN KEY (`icon_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`image_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `document_translation` (
	`document_id` text NOT NULL,
	`lang` text NOT NULL,
	`label` text NOT NULL,
	`hint` text,
	`audio_ref` text,
	PRIMARY KEY(`document_id`, `lang`),
	FOREIGN KEY (`document_id`) REFERENCES `document`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`audio_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `flow_step` (
	`id` text PRIMARY KEY NOT NULL,
	`venue_id` text NOT NULL,
	`step_order` integer NOT NULL,
	`icon_ref` text NOT NULL,
	FOREIGN KEY (`venue_id`) REFERENCES `venue`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`icon_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `flow_step_translation` (
	`step_id` text NOT NULL,
	`lang` text NOT NULL,
	`title` text NOT NULL,
	`body` text,
	`audio_ref` text,
	PRIMARY KEY(`step_id`, `lang`),
	FOREIGN KEY (`step_id`) REFERENCES `flow_step`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`audio_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `pack_meta` (
	`id` integer PRIMARY KEY NOT NULL,
	`pack_version` integer NOT NULL,
	`schema_version` text NOT NULL,
	`municipality_code` text,
	`built_at` text NOT NULL,
	`default_outcome_id` text NOT NULL,
	`source_commit` text
);
--> statement-breakpoint
CREATE TABLE `routing_outcome` (
	`id` text PRIMARY KEY NOT NULL,
	`severity_level` integer NOT NULL,
	`card_id` text NOT NULL,
	`venue_id` text NOT NULL,
	FOREIGN KEY (`card_id`) REFERENCES `card`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`venue_id`) REFERENCES `venue`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `routing_rule` (
	`id` text PRIMARY KEY NOT NULL,
	`priority` integer NOT NULL,
	`outcome_id` text NOT NULL,
	`rationale` text,
	`clinical_source` text,
	FOREIGN KEY (`outcome_id`) REFERENCES `routing_outcome`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `routing_rule_term` (
	`rule_id` text NOT NULL,
	`group_no` integer NOT NULL,
	`token_id` text NOT NULL,
	`negated` integer DEFAULT 0 NOT NULL,
	PRIMARY KEY(`rule_id`, `group_no`, `token_id`),
	FOREIGN KEY (`rule_id`) REFERENCES `routing_rule`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`token_id`) REFERENCES `symptom_token`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `service` (
	`id` text PRIMARY KEY NOT NULL,
	`venue_id` text NOT NULL,
	`icon_ref` text NOT NULL,
	`sort_order` integer DEFAULT 0 NOT NULL,
	FOREIGN KEY (`venue_id`) REFERENCES `venue`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`icon_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `service_document` (
	`service_id` text NOT NULL,
	`document_id` text NOT NULL,
	`required` integer DEFAULT 1 NOT NULL,
	PRIMARY KEY(`service_id`, `document_id`),
	FOREIGN KEY (`service_id`) REFERENCES `service`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`document_id`) REFERENCES `document`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `service_translation` (
	`service_id` text NOT NULL,
	`lang` text NOT NULL,
	`label` text NOT NULL,
	`audio_ref` text,
	PRIMARY KEY(`service_id`, `lang`),
	FOREIGN KEY (`service_id`) REFERENCES `service`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`audio_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `symptom_token` (
	`id` text PRIMARY KEY NOT NULL,
	`kind` text NOT NULL,
	`icon_ref` text NOT NULL,
	`sort_order` integer DEFAULT 0 NOT NULL,
	`deprecated` integer DEFAULT 0 NOT NULL,
	FOREIGN KEY (`icon_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `token_translation` (
	`token_id` text NOT NULL,
	`lang` text NOT NULL,
	`label` text NOT NULL,
	`audio_ref` text,
	PRIMARY KEY(`token_id`, `lang`),
	FOREIGN KEY (`token_id`) REFERENCES `symptom_token`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`audio_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `venue` (
	`id` text PRIMARY KEY NOT NULL,
	`icon_ref` text NOT NULL,
	`color_token` text NOT NULL,
	FOREIGN KEY (`icon_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `venue_translation` (
	`venue_id` text NOT NULL,
	`lang` text NOT NULL,
	`label` text NOT NULL,
	`audio_ref` text,
	PRIMARY KEY(`venue_id`, `lang`),
	FOREIGN KEY (`venue_id`) REFERENCES `venue`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`audio_ref`) REFERENCES `asset`(`ref`) ON UPDATE no action ON DELETE no action
);
