-- `storage_key` sai: apontava para um objeto no MinIO que ninguem enviava.
--
-- Escrita pelo CMS desde o item 16, lida por NINGUEM — `extract.ts` projeta
-- apenas `ref, kind, path, sha256, bytes`. A coluna prometia um lugar, e o lugar
-- nao existia. Mesmo motivo pelo qual `totp_secret_enc` saiu no item 17: nome
-- que promete algo que acontece em outro lugar.
--
-- Seguro apesar das restricoes de DROP COLUMN do SQLite: nao e PK, nao tem
-- indice, nao e alvo de FK e nao aparece no corpo de gatilho nenhum.

ALTER TABLE `asset` DROP COLUMN `storage_key`;
