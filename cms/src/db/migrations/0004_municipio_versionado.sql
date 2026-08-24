-- `municipality` ganha as colunas de autoria como qualquer entidade editavel.
--
-- CONDICAO desta migracao: a tabela precisa estar VAZIA. `updated_by` e NOT NULL
-- e referencia `admin_user`; para uma linha preexistente nao ha autor a atribuir,
-- e inventar um seria mentir na trilha de auditoria. Hoje isso e verdade em toda
-- instalacao — o CRUD que preenche `municipality` nasce neste mesmo item.
--
-- Se um dia houver linhas, a migracao falha em vez de gravar autor falso.

ALTER TABLE `municipality` ADD `version` integer DEFAULT 1 NOT NULL;--> statement-breakpoint
ALTER TABLE `municipality` ADD `updated_by` text NOT NULL REFERENCES admin_user(id);--> statement-breakpoint
ALTER TABLE `municipality` ADD `updated_at` text NOT NULL;